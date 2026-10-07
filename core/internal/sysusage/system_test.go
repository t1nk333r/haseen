package sysusage

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// hwmon builds one fixture hwmon device with labelled temperature inputs,
// given as label, millidegrees pairs.
func hwmon(t *testing.T, root, dir, name string, sensors ...string) {
	t.Helper()
	base := filepath.Join(root, "sys/class/hwmon", dir)
	write(t, filepath.Join(base, "name"), name+"\n")
	for i := 0; i+1 < len(sensors); i += 2 {
		n := "temp" + itoa(i/2+1)
		write(t, filepath.Join(base, n+"_label"), sensors[i]+"\n")
		write(t, filepath.Join(base, n+"_input"), sensors[i+1]+"\n")
	}
}

func zone(t *testing.T, root, dir, kind, milli string) {
	t.Helper()
	base := filepath.Join(root, "sys/class/thermal", dir)
	write(t, filepath.Join(base, "type"), kind+"\n")
	write(t, filepath.Join(base, "temp"), milli+"\n")
}

// The package sensor wins over everything else: coretemp, then k10temp (Tdie
// before Tctl), then the x86_pkg_temp thermal zone; ACPI zones and NVMe never.
func TestCPUTempPrecedence(t *testing.T) {
	root := t.TempDir()
	if got := (&Sampler{Root: root}).cpuTemp(); got != -1 {
		t.Fatalf("no sensor = %v, want -1", got)
	}

	hwmon(t, root, "hwmon0", "acpitz", "", "99000")
	hwmon(t, root, "hwmon1", "nvme", "Composite", "38000")
	zone(t, root, "thermal_zone0", "acpitz", "98000")
	zone(t, root, "thermal_zone1", "x86_pkg_temp", "51000")
	if got := (&Sampler{Root: root}).cpuTemp(); got != 51 {
		t.Fatalf("thermal zone = %v, want 51", got)
	}

	hwmon(t, root, "hwmon2", "k10temp", "Tctl", "70500", "Tdie", "43500", "Tccd1", "40000")
	if got := (&Sampler{Root: root}).cpuTemp(); got != 43.5 {
		t.Fatalf("k10temp = %v, want Tdie 43.5", got)
	}

	hwmon(t, root, "hwmon3", "coretemp", "Core 0", "60000", "Package id 0", "62000")
	s := &Sampler{Root: root}
	if got := s.cpuTemp(); got != 62 {
		t.Fatalf("coretemp = %v, want Package id 0 = 62", got)
	}

	// A sensor that disappears (driver reload renumbers hwmon) is unknown
	// for one tick and looked up again on the next.
	if err := os.RemoveAll(filepath.Join(root, "sys/class/hwmon/hwmon3")); err != nil {
		t.Fatal(err)
	}
	if got := s.cpuTemp(); got != -1 {
		t.Fatalf("vanished sensor = %v, want -1", got)
	}
	if got := s.cpuTemp(); got != 43.5 {
		t.Fatalf("after re-probe = %v, want 43.5", got)
	}
}

// k10temp before Linux 4.15 labels nothing; its temp1 is the package.
func TestCPUTempUnlabelled(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "sys/class/hwmon/hwmon0/name"), "k10temp\n")
	write(t, filepath.Join(root, "sys/class/hwmon/hwmon0/temp1_input"), "45250\n")
	if got := (&Sampler{Root: root}).cpuTemp(); got != 45.25 {
		t.Fatalf("unlabelled k10temp = %v, want 45.25", got)
	}
}

func TestCPUFreq(t *testing.T) {
	root := t.TempDir()
	cpu := filepath.Join(root, "sys/devices/system/cpu")
	write(t, filepath.Join(cpu, "cpu0/cpufreq/scaling_cur_freq"), "2000000\n")
	write(t, filepath.Join(cpu, "cpu1/cpufreq/scaling_cur_freq"), "3000000\n")
	// No cpufreq for this one, and the policy directory is not a CPU.
	if err := os.MkdirAll(filepath.Join(cpu, "cpu2"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(cpu, "cpufreq/policy0/scaling_cur_freq"), "9000000\n")
	write(t, filepath.Join(root, "proc/cpuinfo"), "cpu MHz\t\t: 100.0\n")

	if got := (&Sampler{Root: root}).cpuFreq(); got != 2500 {
		t.Fatalf("cpufreq mean = %v, want 2500", got)
	}
}

// Without cpufreq (a VM), /proc/cpuinfo's per-CPU "cpu MHz" is the source.
func TestCPUFreqFallback(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/cpuinfo"),
		"processor\t: 0\ncpu MHz\t\t: 1000.500\n\nprocessor\t: 1\ncpu MHz\t\t: 3000.500\n")
	if got := (&Sampler{Root: root}).cpuFreq(); got != 2000.5 {
		t.Fatalf("cpuinfo mean = %v, want 2000.5", got)
	}
	if got := (&Sampler{Root: t.TempDir()}).cpuFreq(); got != -1 {
		t.Fatalf("nothing = %v, want -1", got)
	}
}

const netHeader = "Inter-|   Receive                                                |  Transmit\n" +
	" face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"

func netLine(name string, rx, tx int) string {
	return "  " + name + ": " + itoa(rx) + " 10 0 0 0 0 0 0 " + itoa(tx) + " 10 0 0 0 0 0 0\n"
}

// Rates are per second over the wall time between system samples, lo is not
// traffic, and an interface that comes or goes moves nothing.
func TestNetRate(t *testing.T) {
	root := t.TempDir()
	dev := filepath.Join(root, "proc/net/dev")
	s := &Sampler{Root: root}

	write(t, dev, netHeader+netLine("lo", 5000, 5000)+netLine("wlan0", 1000, 100)+netLine("eth0", 7000, 700))
	if got := s.netRate(); got.RxBps != -1 || got.TxBps != -1 {
		t.Fatalf("first sample = %+v, want -1/-1", got)
	}

	s.sys.netAt = s.sys.netAt.Add(-2 * time.Second)
	write(t, dev, netHeader+netLine("lo", 900000, 900000)+netLine("wlan0", 5000, 1100)+netLine("tun0", 99999, 99999))
	got := s.netRate()
	// 4000 B and 1000 B over a little more than 2 s.
	if got.RxBps <= 1900 || got.RxBps > 2000 || got.TxBps <= 475 || got.TxBps > 500 {
		t.Fatalf("rate = %+v, want ~2000/~500", got)
	}
	if _, ok := s.sys.net["eth0"]; ok {
		t.Fatal("eth0 went away and is still tracked")
	}

	// A counter that went backwards is zero, not negative.
	s.sys.netAt = s.sys.netAt.Add(-time.Second)
	write(t, dev, netHeader+netLine("wlan0", 10, 10)+netLine("tun0", 99999, 99999))
	if got := s.netRate(); got.RxBps != 0 || got.TxBps != 0 {
		t.Fatalf("after reset = %+v, want 0/0", got)
	}
}

// fakeStatfs answers for fixture mountpoints: 1000 blocks of 4 KiB, 400 free,
// 300 of them available to users; /mnt/gone fails like an unplugged disk.
func fakeStatfs(root string) func(string, *syscall.Statfs_t) error {
	return func(path string, st *syscall.Statfs_t) error {
		mount := strings.TrimPrefix(path, root)
		if mount == "" {
			mount = "/"
		}
		if mount == "/mnt/gone" {
			return errors.New("no such device")
		}
		*st = syscall.Statfs_t{Bsize: 4096, Frsize: 4096, Blocks: 1000, Bfree: 400, Bavail: 300}
		if mount == "/mnt/empty" {
			st.Blocks = 0
		}
		return nil
	}
}

func TestDisks(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/self/mounts"), strings.Join([]string{
		"proc /proc proc rw,nosuid 0 0",
		"tmpfs /run tmpfs rw 0 0",
		"/dev/mapper/root /var/log btrfs rw,subvol=/@log 0 0",
		"/dev/mapper/root / btrfs rw,subvol=/@ 0 0",
		"/dev/mapper/root /home btrfs rw,subvol=/@home 0 0",
		"/dev/nvme0n1p1 /boot vfat rw 0 0",
		"/dev/loop0 /snap/core/1 squashfs ro 0 0",
		"/dev/sr0 /run/media/cd iso9660 ro 0 0",
		"/dev/zram0 /tmp ext4 rw 0 0",
		"/dev/mapper/verity /usr erofs ro 0 0",
		`/dev/sdb1 /media/My\040Disk fuseblk rw 0 0`,
		"/dev/sdc1 /mnt/gone ext4 rw 0 0",
		"/dev/sdd1 /mnt/empty ext4 rw 0 0",
		"overlay /var/lib/docker/overlay2/x/merged overlay rw 0 0",
	}, "\n")+"\n")

	s := &Sampler{Root: root, Statfs: fakeStatfs(root)}
	got := s.disks()
	want := []Disk{
		{Mount: "/", Device: "/dev/mapper/root", FSType: "btrfs"},
		{Mount: "/boot", Device: "/dev/nvme0n1p1", FSType: "vfat"},
		{Mount: "/media/My Disk", Device: "/dev/sdb1", FSType: "fuseblk"},
	}
	if len(got) != len(want) {
		t.Fatalf("disks = %+v, want %d rows", got, len(want))
	}
	for i, d := range got {
		w := want[i]
		w.TotalKiB, w.UsedKiB, w.AvailKiB = 4000, 2400, 1200
		// df's percent: used / (used + available), reserved blocks excluded.
		w.Percent = 100 * 2400.0 / 3600.0
		if d != w {
			t.Fatalf("disk %d = %+v, want %+v", i, d, w)
		}
	}
}

// Nobody asking for `system` leaves the payload exactly as haseen.sysusage
// knew it; asking adds all four fields, net starting at -1.
func TestSystemFieldsOnRequest(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/net/dev"), netHeader+netLine("wlan0", 1, 1))
	s := &Sampler{Root: root, Statfs: fakeStatfs(root)}
	keys := []string{"cpuTempC", "cpuFreqMHz", "net", "disks"}

	decode := func(sample Sample) map[string]any {
		raw, err := json.Marshal(sample)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(raw, &m); err != nil {
			t.Fatal(err)
		}
		return m
	}

	plain := decode(s.Sample("off", false, false))
	for _, k := range keys {
		if _, ok := plain[k]; ok {
			t.Fatalf("%q present without system: %v", k, plain)
		}
	}
	if _, ok := plain["cpu"]; !ok {
		t.Fatalf("base payload lost: %v", plain)
	}

	full := decode(s.Sample("off", false, true))
	for _, k := range keys {
		if _, ok := full[k]; !ok {
			t.Fatalf("%q missing with system: %v", k, full)
		}
	}
	if full["cpuTempC"] != -1.0 || full["cpuFreqMHz"] != -1.0 {
		t.Fatalf("unknown temp/freq = %v/%v, want -1", full["cpuTempC"], full["cpuFreqMHz"])
	}
	if net := full["net"].(map[string]any); net["rxBps"] != -1.0 || net["txBps"] != -1.0 {
		t.Fatalf("first net = %v, want -1/-1", net)
	}
	if disks, ok := full["disks"].([]any); !ok || len(disks) != 0 {
		t.Fatalf("disks = %v, want []", full["disks"])
	}

	// Dropping `system` forgets the counters: asking again starts at -1, not
	// at the average over the gap.
	s.Sample("off", false, true)
	s.Sample("off", false, false)
	again := decode(s.Sample("off", false, true))
	if net := again["net"].(map[string]any); net["rxBps"] != -1.0 {
		t.Fatalf("net after a gap = %v, want -1", net)
	}
}
