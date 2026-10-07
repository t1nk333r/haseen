package sysusage

import (
	"bufio"
	"bytes"
	"os"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// System is what DankMaterialShell desktop plugins (dms-conky) read from DMS's
// DgopService: CPU temperature and clock, network throughput and the mounted
// disks. haseen's compat DgopService reads it from this stream. It is sampled
// only when a subscriber asks for `system`, and Sample embeds it as a pointer:
// when nobody asks, the fields are absent from the JSON and haseen.sysusage's
// payload and cost stay what they were.
type System struct {
	CPUTempC   float64 `json:"cpuTempC"`   // -1 = unknown
	CPUFreqMHz float64 `json:"cpuFreqMHz"` // mean over online CPUs; -1 = unknown
	Net        NetRate `json:"net"`
	Disks      []Disk  `json:"disks"`
}

// NetRate is bytes per second since the previous system sample, summed over
// every interface but lo; both are -1 when there is no previous sample.
type NetRate struct {
	RxBps float64 `json:"rxBps"`
	TxBps float64 `json:"txBps"`
}

// Disk is one block-device filesystem. Sizes follow df: percent is
// used / (used + avail), so blocks reserved for root do not count as free.
type Disk struct {
	Mount    string  `json:"mount"`
	Device   string  `json:"device"`
	FSType   string  `json:"fstype"`
	TotalKiB int64   `json:"totalKiB"`
	UsedKiB  int64   `json:"usedKiB"`
	AvailKiB int64   `json:"availKiB"`
	Percent  float64 `json:"percent"`
}

type sysState struct {
	tempProbed bool
	tempPath   string
	freqProbed bool
	freqPaths  []string

	// Per interface, so an interface that goes away (a VPN going down) does
	// not make the sum drop and the rate go negative.
	net     map[string]*netCounter
	netTick uint64
	netAt   time.Time

	// Scratch for single-integer sysfs nodes: one per CPU every tick, and
	// os.ReadFile would allocate a 512-byte buffer for each.
	buf [32]byte
}

type netCounter struct {
	rx, tx int64
	tick   uint64
}

func (s *Sampler) system() *System {
	return &System{
		CPUTempC:   s.cpuTemp(),
		CPUFreqMHz: s.cpuFreq(),
		Net:        s.netRate(),
		Disks:      s.disks(),
	}
}

// hwmon drivers that report the CPU package, most preferred first, with the
// labels naming the package sensor. Tdie comes before Tctl: on some Ryzen and
// Threadripper parts Tctl carries a fan-control offset of up to 27 °C.
var cpuSensors = []struct {
	driver string
	labels []string
}{
	{"coretemp", []string{"Package id 0"}},
	{"k10temp", []string{"Tdie", "Tctl"}},
	{"zenpower", []string{"Tdie", "Tctl"}},
}

// cpuTemp is the CPU package temperature in °C; -1 when there is no sensor.
// The sensor is looked up once and re-probed only when it stops answering.
func (s *Sampler) cpuTemp() float64 {
	if !s.sys.tempProbed {
		s.sys.tempProbed = true
		s.sys.tempPath = s.probeTemp()
	}
	if s.sys.tempPath == "" {
		return -1
	}
	v, ok := s.readInt(s.sys.tempPath)
	if !ok {
		// hwmonN numbers are not stable across a driver reload.
		s.sys.tempProbed = false
		return -1
	}
	return float64(v) / 1000
}

// probeTemp returns the input node of the best CPU package sensor: a package
// hwmon sensor first, then the x86_pkg_temp thermal zone (Intel's package
// sensor without coretemp loaded), else "".
func (s *Sampler) probeTemp() string {
	hwmons, _ := os.ReadDir(s.path("/sys/class/hwmon"))
	for _, sensor := range cpuSensors {
		for _, entry := range hwmons {
			dir := s.path("/sys/class/hwmon/" + entry.Name())
			if strings.TrimSpace(readFile(dir+"/name")) != sensor.driver {
				continue
			}
			if input := hwmonInput(dir, sensor.labels); input != "" {
				return input
			}
		}
	}
	zones, _ := os.ReadDir(s.path("/sys/class/thermal"))
	for _, entry := range zones {
		if !strings.HasPrefix(entry.Name(), "thermal_zone") {
			continue
		}
		dir := s.path("/sys/class/thermal/" + entry.Name())
		if strings.TrimSpace(readFile(dir+"/type")) == "x86_pkg_temp" {
			return dir + "/temp"
		}
	}
	return ""
}

// hwmonInput finds tempN_input for the first label that matches. A driver that
// labels nothing (k10temp before Linux 4.15) has its package sensor as temp1.
func hwmonInput(dir string, labels []string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	labelled := false
	for _, want := range labels {
		for _, entry := range entries {
			name := entry.Name()
			base, ok := strings.CutSuffix(name, "_label")
			if !ok || !strings.HasPrefix(name, "temp") {
				continue
			}
			labelled = true
			if strings.TrimSpace(readFile(dir+"/"+name)) == want {
				return dir + "/" + base + "_input"
			}
		}
	}
	if !labelled && readable(dir+"/temp1_input") {
		return dir + "/temp1_input"
	}
	return ""
}

// cpuFreq is the mean current clock over online CPUs in MHz, from cpufreq,
// else from /proc/cpuinfo (a VM without cpufreq), else -1.
func (s *Sampler) cpuFreq() float64 {
	if !s.sys.freqProbed {
		s.sys.freqProbed = true
		s.sys.freqPaths = s.probeFreq()
	}
	var sum int64
	n := 0
	for _, p := range s.sys.freqPaths {
		// An offline CPU's policy answers EBUSY, which is what leaves it out
		// of the mean.
		if v, ok := s.readInt(p); ok && v > 0 {
			sum += v
			n++
		}
	}
	if n > 0 {
		return float64(sum) / float64(n) / 1000 // kHz
	}
	return s.cpuinfoMHz()
}

func (s *Sampler) probeFreq() []string {
	entries, err := os.ReadDir(s.path("/sys/devices/system/cpu"))
	if err != nil {
		return nil
	}
	var paths []string
	for _, entry := range entries {
		num, ok := strings.CutPrefix(entry.Name(), "cpu")
		if !ok || num == "" || strings.Trim(num, "0123456789") != "" {
			continue
		}
		p := s.path("/sys/devices/system/cpu/" + entry.Name() + "/cpufreq/scaling_cur_freq")
		if _, err := os.Stat(p); err == nil {
			paths = append(paths, p)
		}
	}
	return paths
}

func (s *Sampler) cpuinfoMHz() float64 {
	f, err := os.Open(s.path("/proc/cpuinfo"))
	if err != nil {
		return -1
	}
	defer f.Close()
	var sum float64
	n := 0
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		line := scan.Bytes()
		if !bytes.HasPrefix(line, []byte("cpu MHz")) {
			continue
		}
		_, value, ok := bytes.Cut(line, []byte(":"))
		if !ok {
			continue
		}
		if v, err := strconv.ParseFloat(string(bytes.TrimSpace(value)), 64); err == nil && v > 0 {
			sum += v
			n++
		}
	}
	if n == 0 {
		return -1
	}
	return sum / float64(n)
}

// netRate reads the byte counters of /proc/net/dev and returns the rate since
// the previous call. A counter that went backwards (a driver reload) or an
// interface that just appeared contributes nothing this tick rather than a
// spike or a negative rate.
func (s *Sampler) netRate() NetRate {
	out := NetRate{RxBps: -1, TxBps: -1}
	f, err := os.Open(s.path("/proc/net/dev"))
	if err != nil {
		s.sys.net = nil
		return out
	}
	defer f.Close()

	now := time.Now()
	had := s.sys.net != nil
	if !had {
		s.sys.net = map[string]*netCounter{}
	}
	prevTick := s.sys.netTick
	s.sys.netTick++
	tick := s.sys.netTick

	var rxSum, txSum int64
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		line := scan.Bytes()
		colon := bytes.IndexByte(line, ':')
		if colon < 0 { // the two header lines
			continue
		}
		name := bytes.TrimSpace(line[:colon])
		if string(name) == "lo" {
			continue
		}
		rx, tx, ok := netBytes(line[colon+1:])
		if !ok {
			continue
		}
		c := s.sys.net[string(name)]
		if c == nil {
			s.sys.net[string(name)] = &netCounter{rx: rx, tx: tx, tick: tick}
			continue
		}
		if c.tick == prevTick {
			rxSum += max(rx-c.rx, 0)
			txSum += max(tx-c.tx, 0)
		}
		c.rx, c.tx, c.tick = rx, tx, tick
	}
	for name, c := range s.sys.net {
		if c.tick != tick {
			delete(s.sys.net, name)
		}
	}

	elapsed := now.Sub(s.sys.netAt).Seconds()
	s.sys.netAt = now
	if !had || elapsed <= 0 {
		return out
	}
	return NetRate{RxBps: float64(rxSum) / elapsed, TxBps: float64(txSum) / elapsed}
}

// netBytes takes the fields after "iface:" in /proc/net/dev: receive bytes is
// the first, transmit bytes the ninth.
func netBytes(fields []byte) (rx, tx int64, ok bool) {
	var okRx bool
	for i := 0; ; i++ {
		var field []byte
		field, fields = nextField(fields)
		if field == nil {
			return 0, 0, false
		}
		switch i {
		case 0:
			rx, okRx = parseInt(field)
		case 8:
			tx, ok = parseInt(field)
			return rx, tx, ok && okRx
		}
	}
}

// Filesystems that sit on a block device yet are not a disk worth a row:
// read-only images, always 100 % full. This is a denylist, not an allowlist:
// the /dev/ source test already drops every pseudo filesystem (proc, sysfs,
// tmpfs and overlay have no /dev/ source), and an allowlist would silently hide
// f2fs, bcachefs or an NTFS stick mounted as fuseblk.
var imageFS = map[string]bool{"squashfs": true, "erofs": true, "iso9660": true}

// Block devices that are not disks: loop images and RAM disks (zram included,
// which is RAM however it is formatted).
var notDisks = []string{"/dev/loop", "/dev/ram", "/dev/zram"}

// disks lists the block-device filesystems from /proc/self/mounts, one per
// device: btrfs mounts one device at every subvolume's mountpoint, and the
// shortest path is the one a person recognises (/ rather than /var/log).
func (s *Sampler) disks() []Disk {
	out := []Disk{}
	f, err := os.Open(s.path("/proc/self/mounts"))
	if err != nil {
		return out
	}
	defer f.Close()

	scan := bufio.NewScanner(f)
	for scan.Scan() {
		line := scan.Bytes()
		if !bytes.HasPrefix(line, []byte("/dev/")) {
			continue
		}
		device, rest := nextField(line)
		mount, rest := nextField(rest)
		fstype, _ := nextField(rest)
		if fstype == nil || imageFS[string(fstype)] || isNotDisk(device) {
			continue
		}
		mountPath := unescapeMount(mount)
		i := slices.IndexFunc(out, func(d Disk) bool { return d.Device == string(device) })
		if i < 0 {
			out = append(out, Disk{Mount: mountPath, Device: string(device), FSType: string(fstype)})
			continue
		}
		if len(mountPath) < len(out[i].Mount) || len(mountPath) == len(out[i].Mount) && mountPath < out[i].Mount {
			out[i].Mount = mountPath
		}
	}

	statfs := s.Statfs
	if statfs == nil {
		statfs = syscall.Statfs
	}
	kept := out[:0]
	for _, d := range out {
		var st syscall.Statfs_t
		if err := statfs(s.path(d.Mount), &st); err != nil {
			continue
		}
		bs := int64(st.Frsize)
		if bs <= 0 {
			bs = int64(st.Bsize)
		}
		d.TotalKiB = int64(st.Blocks) * bs / 1024
		d.AvailKiB = int64(st.Bavail) * bs / 1024
		d.UsedKiB = int64(st.Blocks-st.Bfree) * bs / 1024
		if d.TotalKiB <= 0 {
			continue
		}
		if d.UsedKiB+d.AvailKiB > 0 {
			d.Percent = clamp(100 * float64(d.UsedKiB) / float64(d.UsedKiB+d.AvailKiB))
		}
		kept = append(kept, d)
	}
	slices.SortFunc(kept, func(a, b Disk) int { return strings.Compare(a.Mount, b.Mount) })
	return kept
}

func isNotDisk(device []byte) bool {
	for _, prefix := range notDisks {
		if bytes.HasPrefix(device, []byte(prefix)) {
			return true
		}
	}
	return false
}

// unescapeMount undoes the octal escapes /proc/self/mounts uses for space, tab,
// newline and backslash in a mountpoint (`/media/My\040Disk`).
func unescapeMount(b []byte) string {
	if bytes.IndexByte(b, '\\') < 0 {
		return string(b)
	}
	out := make([]byte, 0, len(b))
	// Classic loop: the body skips the three escape digits by advancing i.
	for i := 0; i < len(b); i++ {
		if b[i] == '\\' && i+3 < len(b) && isOctal(b[i+1]) && isOctal(b[i+2]) && isOctal(b[i+3]) {
			out = append(out, (b[i+1]-'0')<<6|(b[i+2]-'0')<<3|(b[i+3]-'0'))
			i += 3
			continue
		}
		out = append(out, b[i])
	}
	return string(out)
}

func isOctal(c byte) bool { return c >= '0' && c <= '7' }

// readInt reads a node holding one integer into the sampler's scratch buffer.
func (s *Sampler) readInt(path string) (int64, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	n, _ := f.Read(s.sys.buf[:])
	f.Close()
	if n == 0 {
		return 0, false
	}
	return parseInt(bytes.TrimSpace(s.sys.buf[:n]))
}

// parseInt is strconv.ParseInt without the string conversion, which would
// allocate for every node read.
func parseInt(b []byte) (int64, bool) {
	neg := len(b) > 0 && b[0] == '-'
	if neg {
		b = b[1:]
	}
	if len(b) == 0 {
		return 0, false
	}
	var v int64
	for _, c := range b {
		if c < '0' || c > '9' {
			return 0, false
		}
		v = v*10 + int64(c-'0')
	}
	if neg {
		v = -v
	}
	return v, true
}

func nextField(b []byte) (field, rest []byte) {
	i := 0
	for i < len(b) && (b[i] == ' ' || b[i] == '\t') {
		i++
	}
	j := i
	for j < len(b) && b[j] != ' ' && b[j] != '\t' {
		j++
	}
	if i == j {
		return nil, nil
	}
	return b[i:j], b[j:]
}
