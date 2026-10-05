package sysusage

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// Busy share is (dtotal - didle) / dtotal, and idle counts iowait: a CPU
// waiting on I/O is not busy.
func TestCPUPercent(t *testing.T) {
	root := t.TempDir()
	s := &Sampler{Root: root}
	stat := filepath.Join(root, "proc/stat")

	write(t, stat, "cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 1 2 3 4\n")
	if got := s.cpuPercent(); got != -1 {
		t.Fatalf("first sample = %v, want -1 (nothing to compare with)", got)
	}
	write(t, stat, "cpu  150 0 150 800 100 0 0 0 0 0\n")
	if got := s.cpuPercent(); got != 50 {
		t.Fatalf("cpu = %v, want 50", got)
	}
	// A counter that went backwards (a reset) is unknown, not negative.
	write(t, stat, "cpu  100 0 100 700 100 0 0 0 0 0\n")
	if got := s.cpuPercent(); got != -1 {
		t.Fatalf("after reset = %v, want -1", got)
	}
}

func TestCPUPercentGarbage(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/stat"), "intr 1 2 3\n")
	if got := (&Sampler{Root: root}).cpuPercent(); got != -1 {
		t.Fatalf("no cpu line = %v, want -1", got)
	}
}

// Used is MemTotal - MemAvailable, which is what free(1) prints as used.
func TestMem(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/meminfo"),
		"MemTotal:       32554964 kB\nMemFree:  1 kB\nMemAvailable:   18094064 kB\n"+
			"SwapCached: 0 kB\nSwapTotal:      1000 kB\nSwapFree:       250 kB\n")
	m := (&Sampler{Root: root}).mem()
	if m == nil {
		t.Fatal("mem = nil")
	}
	if m.UsedKiB != 14460900 {
		t.Errorf("used = %d, want 14460900", m.UsedKiB)
	}
	if got := float64(int(m.Percent*100+0.5)) / 100; got != 44.42 {
		t.Errorf("percent = %v, want 44.42", got)
	}
	if m.SwapUsedKiB != 750 {
		t.Errorf("swap used = %d, want 750", m.SwapUsedKiB)
	}
}

// MemAvailable only exists since Linux 3.14.
func TestMemFallback(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/meminfo"),
		"MemTotal: 100 kB\nMemFree: 50 kB\nBuffers: 10 kB\nCached: 10 kB\n")
	m := (&Sampler{Root: root}).mem()
	if m == nil || m.Percent != 30 {
		t.Fatalf("percent = %v, want 30", m)
	}
}

func TestMemGarbage(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/meminfo"), "")
	if m := (&Sampler{Root: root}).mem(); m != nil {
		t.Fatalf("mem = %v, want nil", m)
	}
}

// The process list is the CPU share between two ticks, highest first, which is
// what `top -b -n 2` used to be forked for.
func TestProcesses(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/meminfo"), "MemTotal: 1000 kB\nMemAvailable: 500 kB\n")
	proc := func(pid, jiffies int, comm string) {
		dir := filepath.Join(root, "proc", itoa(pid))
		fields := "R 1 1 1 0 -1 0 0 0 0 0 " + itoa(jiffies) + " 0 0 0 20 0 1 0 0 0 1"
		write(t, filepath.Join(dir, "stat"), itoa(pid)+" ("+comm+") "+fields+"\n")
		write(t, filepath.Join(dir, "status"), "Name:\t"+comm+"\nUid:\t1000\t1000\t1000\t1000\n")
	}
	proc(10, 100, "quiet")
	proc(11, 100, "busy")

	s := &Sampler{Root: root}
	if got := s.processes(8); len(got) != 0 {
		t.Fatalf("first tick = %v, want nothing (no previous sample)", got)
	}
	proc(10, 110, "quiet")
	proc(11, 400, "busy")
	got := s.processes(8)
	if len(got) != 2 {
		t.Fatalf("got %d processes, want 2", len(got))
	}
	if got[0].Command != "busy" {
		t.Errorf("first = %q, want the busiest (busy)", got[0].Command)
	}
	if got[0].CPU <= got[1].CPU {
		t.Errorf("not sorted by cpu: %v", got)
	}
	if got[0].PID != 11 {
		t.Errorf("pid = %d, want 11", got[0].PID)
	}
	// A comm with spaces and parentheses still parses: the fields after it are
	// taken from the last ')', not the first space.
	proc(12, 100, "Web Content")
	s2 := &Sampler{Root: root}
	s2.processes(8)
	proc(12, 200, "Web Content")
	found := false
	for _, p := range s2.processes(8) {
		if p.PID == 12 && p.Command == "Web Content" {
			found = true
		}
	}
	if !found {
		t.Error("a command with a space was not read back")
	}
}

func TestProcessLimit(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "proc/meminfo"), "MemTotal: 1000 kB\n")
	for pid := 10; pid < 30; pid++ {
		dir := filepath.Join(root, "proc", itoa(pid))
		write(t, filepath.Join(dir, "stat"), itoa(pid)+" (p) R 1 1 1 0 -1 0 0 0 0 0 1 0 0 0 20 0 1 0 0 0 1\n")
		write(t, filepath.Join(dir, "status"), "Uid:\t1000\t1000\t1000\t1000\n")
	}
	s := &Sampler{Root: root}
	s.processes(8)
	for pid := 10; pid < 30; pid++ {
		dir := filepath.Join(root, "proc", itoa(pid))
		write(t, filepath.Join(dir, "stat"), itoa(pid)+" (p) R 1 1 1 0 -1 0 0 0 0 0 9 0 0 0 20 0 1 0 0 0 1\n")
	}
	if got := s.processes(8); len(got) != 8 {
		t.Fatalf("got %d, want the 8 asked for", len(got))
	}
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	digits := ""
	for v > 0 {
		digits = string(rune('0'+v%10)) + digits
		v /= 10
	}
	return digits
}
