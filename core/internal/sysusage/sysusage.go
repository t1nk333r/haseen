// Package sysusage samples what haseen.sysusage shows: CPU, memory, GPU busy
// and the top processes. The QML plugin used to do this itself, with a 3 s
// Timer, five FileViews and a `top -b -n 2` process per tick; here it is one
// sampler shared by every subscriber, and the process list is read straight
// from /proc instead of forking top.
package sysusage

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Root is the filesystem the sampler reads. Tests point it at a fixture tree;
// it is "" (the live machine) everywhere else.
type Sampler struct {
	Root string

	prevCPU    cpuTimes
	havePrev   bool
	prevProc   map[int]procTimes
	prevProcAt time.Time
	gpu        gpuState
}

type Sample struct {
	CPU       float64   `json:"cpu"`
	Mem       *Mem      `json:"mem"`
	GPU       float64   `json:"gpu"`
	GPUs      []GPU     `json:"gpus"`
	GPUInfo   *GPU      `json:"gpuInfo"`
	Processes []Process `json:"processes"`
}

type Mem struct {
	TotalKiB     int64   `json:"totalKiB"`
	AvailableKiB int64   `json:"availableKiB"`
	UsedKiB      int64   `json:"usedKiB"`
	Percent      float64 `json:"percent"`
	SwapTotalKiB int64   `json:"swapTotalKiB"`
	SwapUsedKiB  int64   `json:"swapUsedKiB"`
}

type Process struct {
	PID     int     `json:"pid"`
	User    string  `json:"user"`
	CPU     float64 `json:"cpu"`
	Mem     float64 `json:"mem"`
	Command string  `json:"command"`
}

type cpuTimes struct{ total, idle int64 }

type procTimes struct {
	jiffies int64
	command string
	uid     string
	rssKiB  int64
}

func (s *Sampler) path(p string) string { return filepath.Join(s.Root, p) }

// Sample reads one tick. gpuChoice is "auto", "off" or a card name, the same
// values haseen.sysusage's `gpu` setting takes. wantProcesses adds the process
// list, which only the panel needs.
func (s *Sampler) Sample(gpuChoice string, wantProcesses bool) Sample {
	out := Sample{CPU: -1, GPU: -1, Processes: []Process{}}
	out.CPU = s.cpuPercent()
	out.Mem = s.mem()
	out.GPUs, out.GPUInfo, out.GPU = s.gpuSample(gpuChoice)
	if wantProcesses {
		out.Processes = s.processes(8)
	}
	return out
}

// cpuPercent is the busy share since the previous call; -1 on the first one.
// Idle counts idle + iowait: a CPU waiting on I/O is not busy.
func (s *Sampler) cpuPercent() float64 {
	f, err := os.Open(s.path("/proc/stat"))
	if err != nil {
		return -1
	}
	defer f.Close()

	var cur cpuTimes
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		fields := strings.Fields(scan.Text())
		if len(fields) < 5 || fields[0] != "cpu" {
			continue
		}
		for i, field := range fields[1:] {
			if i >= 8 {
				break
			}
			v, err := strconv.ParseInt(field, 10, 64)
			if err != nil {
				return -1
			}
			cur.total += v
			if i == 3 || i == 4 { // idle, iowait
				cur.idle += v
			}
		}
		break
	}
	if cur.total == 0 {
		return -1
	}
	prev := s.prevCPU
	had := s.havePrev
	s.prevCPU, s.havePrev = cur, true
	if !had {
		return -1
	}
	dt := cur.total - prev.total
	di := cur.idle - prev.idle
	if dt <= 0 || di < 0 {
		return -1
	}
	return clamp(100 * float64(dt-di) / float64(dt))
}

func (s *Sampler) mem() *Mem {
	f, err := os.Open(s.path("/proc/meminfo"))
	if err != nil {
		return nil
	}
	defer f.Close()

	kv := map[string]int64{}
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		name, rest, ok := strings.Cut(scan.Text(), ":")
		if !ok {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) == 0 {
			continue
		}
		if v, err := strconv.ParseInt(fields[0], 10, 64); err == nil {
			kv[name] = v
		}
	}
	total := kv["MemTotal"]
	if total <= 0 {
		return nil
	}
	// MemAvailable exists since Linux 3.14; estimate it on older kernels.
	available, ok := kv["MemAvailable"]
	if !ok {
		available = kv["MemFree"] + kv["Buffers"] + kv["Cached"]
	}
	used := total - available
	if used < 0 {
		used = 0
	}
	swapUsed := kv["SwapTotal"] - kv["SwapFree"]
	if swapUsed < 0 {
		swapUsed = 0
	}
	return &Mem{
		TotalKiB:     total,
		AvailableKiB: available,
		UsedKiB:      used,
		Percent:      clamp(100 * float64(used) / float64(total)),
		SwapTotalKiB: kv["SwapTotal"],
		SwapUsedKiB:  swapUsed,
	}
}

// processes reads /proc directly: the CPU share of each task between this tick
// and the last, which is what `top` prints, without forking anything.
//
// Only /proc/<pid>/stat is read for every task; the owner and the command line
// are two more files each and are read for the handful of rows that are
// actually shown. On this laptop that is ~700 reads a tick instead of ~2100.
func (s *Sampler) processes(limit int) []Process {
	entries, err := os.ReadDir(s.path("/proc"))
	if err != nil {
		return []Process{}
	}
	now := time.Now()
	cur := make(map[int]procTimes, len(entries))
	memTotal := float64(0)
	if m := s.mem(); m != nil {
		memTotal = float64(m.TotalKiB)
	}
	hz := float64(100) // CONFIG_HZ for the USER_HZ /proc/<pid>/stat uses.
	elapsed := now.Sub(s.prevProcAt).Seconds()

	out := make([]Process, 0, len(entries))
	for _, entry := range entries {
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}
		pt, ok := s.readProcStat(pid)
		if !ok {
			continue
		}
		cur[pid] = pt
		prev, had := s.prevProc[pid]
		if !had || elapsed <= 0 {
			continue
		}
		delta := float64(pt.jiffies-prev.jiffies) / hz
		if delta < 0 {
			continue
		}
		memPct := float64(0)
		if memTotal > 0 {
			memPct = 100 * float64(pt.rssKiB) / memTotal
		}
		out = append(out, Process{
			PID:     pid,
			CPU:     100 * delta / elapsed,
			Mem:     memPct,
			Command: pt.command,
		})
	}
	s.prevProc, s.prevProcAt = cur, now

	sort.Slice(out, func(i, j int) bool {
		if out[i].CPU != out[j].CPU {
			return out[i].CPU > out[j].CPU
		}
		return out[i].Mem > out[j].Mem
	})
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	for i := range out {
		dir := s.path("/proc/" + strconv.Itoa(out[i].PID))
		out[i].User = procUser(dir)
		if cmdline := commandLine(dir); cmdline != "" {
			out[i].Command = cmdline
		}
	}
	return out
}

// readProcStat is the one file per task this sampler reads every tick.
func (s *Sampler) readProcStat(pid int) (procTimes, bool) {
	raw, err := os.ReadFile(s.path("/proc/" + strconv.Itoa(pid) + "/stat"))
	if err != nil {
		return procTimes{}, false
	}
	// comm is parenthesised and may hold spaces, so split after the last ')'.
	line := string(raw)
	open := strings.IndexByte(line, '(')
	closeIdx := strings.LastIndexByte(line, ')')
	if open < 0 || closeIdx < open {
		return procTimes{}, false
	}
	fields := strings.Fields(line[closeIdx+1:])
	if len(fields) < 22 {
		return procTimes{}, false
	}
	// After the state field: utime is index 11, stime 12, rss (pages) 21.
	utime, _ := strconv.ParseInt(fields[11], 10, 64)
	stime, _ := strconv.ParseInt(fields[12], 10, 64)
	rssPages, _ := strconv.ParseInt(fields[21], 10, 64)
	return procTimes{
		jiffies: utime + stime,
		command: line[open+1 : closeIdx],
		rssKiB:  rssPages * int64(os.Getpagesize()) / 1024,
	}, true
}

// commandLine is friendlier than comm when it is readable (a kernel thread has
// none, and another user's process may be hidden by hidepid).
func commandLine(dir string) string {
	raw, err := os.ReadFile(dir + "/cmdline")
	if err != nil || len(raw) == 0 {
		return ""
	}
	parts := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
	if parts[0] == "" {
		return ""
	}
	return strings.Join(parts, " ")
}

func procUser(dir string) string {
	raw, err := os.ReadFile(dir + "/status")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(raw), "\n") {
		if rest, ok := strings.CutPrefix(line, "Uid:"); ok {
			fields := strings.Fields(rest)
			if len(fields) > 0 {
				return userName(fields[0])
			}
		}
	}
	return ""
}

var userCache = map[string]string{}

// userName maps a uid to a login name through /etc/passwd. os/user would do it
// too, but it links cgo's name service switch into the daemon for one field.
func userName(uid string) string {
	if name, ok := userCache[uid]; ok {
		return name
	}
	name := uid
	if raw, err := os.ReadFile("/etc/passwd"); err == nil {
		for _, line := range strings.Split(string(raw), "\n") {
			fields := strings.Split(line, ":")
			if len(fields) > 2 && fields[2] == uid {
				name = fields[0]
				break
			}
		}
	}
	userCache[uid] = name
	return name
}

func clamp(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}
