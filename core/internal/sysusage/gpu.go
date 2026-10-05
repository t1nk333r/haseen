package sysusage

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// GPU is one DRM card and how its busy share can be read without root.
// The shape is the one haseen.sysusage's Usage.js already draws from, so the
// QML side did not change: method is busy (amdgpu percent), rc6 (Intel idle
// residency in ms, busy = 1 - idle/wall), freq (Intel clock ratio, shown as
// "GPU freq"), nvidia (nvidia-smi for that PCI slot) or none.
//
// Ported from share/haseen/shell/plugins/haseen.sysusage/gpu-probe.sh, itself
// haseen's own. The probe ran once per shell start; here it runs once per
// daemon and is shared by every subscriber.
type GPU struct {
	Card    string   `json:"card"`
	Driver  string   `json:"driver"`
	BootVGA bool     `json:"bootVga"`
	Method  string   `json:"method"`
	Args    []string `json:"args"`
}

type gpuState struct {
	probed     bool
	cards      []GPU
	prevIdleMs float64
	prevIdleAt time.Time
	nvidia     *nvidiaStream
}

var cardRe = regexp.MustCompile(`^card[0-9]+$`)

func (s *Sampler) probeGPUs() []GPU {
	if s.gpu.probed {
		return s.gpu.cards
	}
	s.gpu.probed = true
	entries, err := os.ReadDir(s.path("/sys/class/drm"))
	if err != nil {
		return nil
	}
	for _, entry := range entries {
		name := entry.Name()
		// Connectors (card1-eDP-1) live in the same directory.
		if !cardRe.MatchString(name) {
			continue
		}
		dir := s.path("/sys/class/drm/" + name)
		uevent := readFile(dir + "/device/uevent")
		if uevent == "" {
			continue
		}
		card := GPU{Card: name, Driver: "unknown", Method: "none", Args: []string{}}
		for _, line := range strings.Split(uevent, "\n") {
			if v, ok := strings.CutPrefix(line, "DRIVER="); ok {
				card.Driver = v
			}
			if v, ok := strings.CutPrefix(line, "PCI_SLOT_NAME="); ok {
				card.Args = []string{v} // kept only for the nvidia case below
			}
		}
		slot := ""
		if len(card.Args) > 0 {
			slot = card.Args[0]
		}
		card.Args = []string{}
		card.BootVGA = strings.TrimSpace(readFile(dir+"/device/boot_vga")) == "1"

		switch card.Driver {
		case "amdgpu":
			if busy := dir + "/device/gpu_busy_percent"; readable(busy) {
				card.Method, card.Args = "busy", []string{busy}
			}
		case "nvidia":
			if slot != "" {
				if _, err := exec.LookPath("nvidia-smi"); err == nil {
					card.Method, card.Args = "nvidia", []string{slot}
				}
			}
		case "i915", "xe":
			for _, f := range []string{
				dir + "/gt/gt0/rc6_residency_ms",
				dir + "/power/rc6_residency_ms",
				dir + "/device/tile0/gt0/gtidle/idle_residency_ms",
			} {
				if readable(f) {
					card.Method, card.Args = "rc6", []string{f}
					break
				}
			}
			if card.Method == "none" {
				for _, pair := range [][2]string{
					{dir + "/gt_act_freq_mhz", dir + "/gt_max_freq_mhz"},
					{dir + "/device/tile0/gt0/freq0/act_freq", dir + "/device/tile0/gt0/freq0/max_freq"},
				} {
					if readable(pair[0]) && readable(pair[1]) {
						card.Method, card.Args = "freq", []string{pair[0], pair[1]}
						break
					}
				}
			}
		}
		s.gpu.cards = append(s.gpu.cards, card)
	}
	return s.gpu.cards
}

// pickGPU mirrors Usage.js pickGpu: "off" shows none, a card name shows that
// card, "auto" takes the boot VGA device. On a hybrid laptop that is the iGPU,
// so auto never wakes a runtime-suspended dGPU.
func pickGPU(cards []GPU, choice string) *GPU {
	if len(cards) == 0 || choice == "off" {
		return nil
	}
	if choice != "" && choice != "auto" {
		for i := range cards {
			if cards[i].Card == choice {
				return &cards[i]
			}
		}
		return nil
	}
	for i := range cards {
		if cards[i].BootVGA {
			return &cards[i]
		}
	}
	return &cards[0]
}

func (s *Sampler) gpuSample(choice string) ([]GPU, *GPU, float64) {
	cards := s.probeGPUs()
	chosen := pickGPU(cards, choice)
	if chosen == nil {
		s.stopNvidia()
		return cards, nil, -1
	}
	if chosen.Method != "nvidia" {
		s.stopNvidia()
	}

	switch chosen.Method {
	case "busy":
		v, err := strconv.ParseFloat(strings.TrimSpace(readFile(chosen.Args[0])), 64)
		if err != nil {
			return cards, chosen, -1
		}
		return cards, chosen, clamp(v)
	case "rc6":
		cur, err := strconv.ParseFloat(strings.TrimSpace(readFile(chosen.Args[0])), 64)
		now := time.Now()
		prev, prevAt := s.gpu.prevIdleMs, s.gpu.prevIdleAt
		if err == nil {
			s.gpu.prevIdleMs, s.gpu.prevIdleAt = cur, now
		}
		wallMs := float64(now.Sub(prevAt).Milliseconds())
		if err != nil || prevAt.IsZero() || wallMs <= 0 || cur < prev {
			return cards, chosen, -1
		}
		return cards, chosen, clamp(100 * (1 - (cur-prev)/wallMs))
	case "freq":
		act, err1 := strconv.ParseFloat(strings.TrimSpace(readFile(chosen.Args[0])), 64)
		max, err2 := strconv.ParseFloat(strings.TrimSpace(readFile(chosen.Args[1])), 64)
		if err1 != nil || err2 != nil || max <= 0 {
			return cards, chosen, -1
		}
		return cards, chosen, clamp(100 * act / max)
	case "nvidia":
		return cards, chosen, s.nvidiaValue(chosen.Args[0])
	}
	return cards, chosen, -1
}

func readFile(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(raw)
}

func readable(path string) bool {
	f, err := os.Open(filepath.Clean(path))
	if err != nil {
		return false
	}
	buf := make([]byte, 1)
	_, readErr := f.Read(buf)
	f.Close()
	// A sysfs node can exist and still fail to read (no permission, no device).
	return readErr == nil || readErr.Error() == "EOF"
}
