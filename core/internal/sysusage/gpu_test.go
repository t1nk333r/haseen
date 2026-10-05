package sysusage

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// card builds one fixture DRM card: driver, boot_vga and whichever sysfs nodes
// the probe looks for.
func card(t *testing.T, root, name, driver, bootVGA string, files ...string) {
	t.Helper()
	dir := filepath.Join(root, "sys/class/drm", name)
	write(t, filepath.Join(dir, "device/uevent"), "DRIVER="+driver+"\nPCI_SLOT_NAME=0000:0"+name[len(name)-1:]+":00.0\n")
	write(t, filepath.Join(dir, "device/boot_vga"), bootVGA+"\n")
	for _, f := range files {
		write(t, filepath.Join(dir, f), "42\n")
	}
	// Connectors live in the same directory and must be skipped.
	if err := os.MkdirAll(filepath.Join(root, "sys/class/drm", name+"-eDP-1"), 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestProbeIntelResidency(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card1", "i915", "1", "gt/gt0/rc6_residency_ms", "gt_act_freq_mhz", "gt_max_freq_mhz")
	cards := (&Sampler{Root: root}).probeGPUs()
	if len(cards) != 1 {
		t.Fatalf("got %d cards, want 1 (the connector is not a card)", len(cards))
	}
	if cards[0].Method != "rc6" {
		t.Fatalf("method = %q, want rc6 (residency wins over frequency)", cards[0].Method)
	}
	if !cards[0].BootVGA {
		t.Error("boot_vga not read")
	}
}

func TestProbeIntelFrequencyFallback(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "i915", "1", "gt_act_freq_mhz", "gt_max_freq_mhz")
	cards := (&Sampler{Root: root}).probeGPUs()
	if cards[0].Method != "freq" || len(cards[0].Args) != 2 {
		t.Fatalf("got %+v, want freq with act and max", cards[0])
	}
}

func TestProbeXeGtidle(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "xe", "1", "device/tile0/gt0/gtidle/idle_residency_ms")
	if got := (&Sampler{Root: root}).probeGPUs()[0].Method; got != "rc6" {
		t.Fatalf("method = %q, want rc6", got)
	}
}

func TestProbeAmdAndNvidia(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "amdgpu", "0", "device/gpu_busy_percent")
	card(t, root, "card1", "nvidia", "1")
	cards := (&Sampler{Root: root}).probeGPUs()
	if len(cards) != 2 {
		t.Fatalf("got %d cards, want 2", len(cards))
	}
	if cards[0].Method != "busy" {
		t.Errorf("amdgpu method = %q, want busy", cards[0].Method)
	}
	// nvidia-smi is not on PATH in the test environment, so that card has no
	// unprivileged source and must say so instead of guessing.
	if _, err := os.Stat("/usr/bin/nvidia-smi"); os.IsNotExist(err) && cards[1].Method != "none" {
		t.Errorf("nvidia method = %q, want none without nvidia-smi", cards[1].Method)
	}
}

func TestProbeEmpty(t *testing.T) {
	if got := (&Sampler{Root: t.TempDir()}).probeGPUs(); len(got) != 0 {
		t.Fatalf("got %v, want no cards", got)
	}
}

// auto picks the boot VGA device: on a hybrid laptop that is the iGPU, so the
// sampler never wakes a runtime-suspended dGPU.
func TestPickGPU(t *testing.T) {
	cards := []GPU{
		{Card: "card0", Driver: "nvidia", Method: "nvidia"},
		{Card: "card1", Driver: "i915", BootVGA: true, Method: "rc6"},
	}
	if got := pickGPU(cards, "auto"); got == nil || got.Card != "card1" {
		t.Errorf("auto = %v, want card1", got)
	}
	if got := pickGPU(cards, "card0"); got == nil || got.Method != "nvidia" {
		t.Errorf("explicit = %v, want card0", got)
	}
	if got := pickGPU(cards, "off"); got != nil {
		t.Errorf("off = %v, want nil", got)
	}
	if got := pickGPU(cards, "card9"); got != nil {
		t.Errorf("unknown card = %v, want nil", got)
	}
	first := []GPU{{Card: "card0", Method: "busy"}}
	if got := pickGPU(first, "auto"); got == nil || got.Card != "card0" {
		t.Errorf("no boot vga = %v, want the first card", got)
	}
}

func TestGPUSampleBusyAndFreq(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "amdgpu", "1", "device/gpu_busy_percent")
	write(t, filepath.Join(root, "sys/class/drm/card0/device/gpu_busy_percent"), "37\n")
	_, chosen, value := (&Sampler{Root: root}).gpuSample("auto")
	if chosen == nil || value != 37 {
		t.Fatalf("busy = %v, want 37", value)
	}

	root = t.TempDir()
	card(t, root, "card0", "i915", "1", "gt_act_freq_mhz", "gt_max_freq_mhz")
	write(t, filepath.Join(root, "sys/class/drm/card0/gt_act_freq_mhz"), "350\n")
	write(t, filepath.Join(root, "sys/class/drm/card0/gt_max_freq_mhz"), "1400\n")
	if _, _, got := (&Sampler{Root: root}).gpuSample("auto"); got != 25 {
		t.Fatalf("freq = %v, want 25", got)
	}
}

// Residency is an idle counter: busy = 1 - idle time / wall time, and the first
// sample has nothing to subtract from.
func TestGPUSampleResidency(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "i915", "1", "gt/gt0/rc6_residency_ms")
	path := filepath.Join(root, "sys/class/drm/card0/gt/gt0/rc6_residency_ms")
	write(t, path, "1000\n")
	s := &Sampler{Root: root}
	if _, _, got := s.gpuSample("auto"); got != -1 {
		t.Fatalf("first residency sample = %v, want -1", got)
	}
	// Pretend 2 s passed and the GPU idled for 1.7 s of it.
	s.gpu.prevIdleAt = time.Now().Add(-2 * time.Second)
	write(t, path, "2700\n")
	_, _, got := s.gpuSample("auto")
	if got < 10 || got > 20 {
		t.Fatalf("residency busy = %v, want about 15", got)
	}
}

func TestGPUSampleOff(t *testing.T) {
	root := t.TempDir()
	card(t, root, "card0", "amdgpu", "1", "device/gpu_busy_percent")
	cards, chosen, value := (&Sampler{Root: root}).gpuSample("off")
	if len(cards) != 1 || chosen != nil || value != -1 {
		t.Fatalf("off = (%v, %v, %v), want the card list with nothing chosen", cards, chosen, value)
	}
}
