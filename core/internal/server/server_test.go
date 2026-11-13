package server

import (
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

// fixtureRoot is a /proc with what the system sample reads, so the test
// reads no live counters.
func fixtureRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"proc/stat":        "cpu  100 0 50 1000 10 0 0 0 0 0\n",
		"proc/meminfo":     "MemTotal: 16148070 kB\nMemAvailable: 9000000 kB\n",
		"proc/net/dev":     "Inter-|Receive\n face |bytes\n  eth0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n  wlan0: 3000 30 0 0 0 0 0 0 4000 40 0 0 0 0 0 0\n",
		"proc/self/mounts": "/dev/nvme0n1p2 / btrfs rw 0 0\n",
		"proc/cpuinfo":     "processor\t: 0\ncpu MHz\t\t: 2400.000\n",
	}
	for name, body := range files {
		p := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// A subscribe samples at once while the ticker may be sampling too (plan
// 165). Run under -race, or plainly: before sampleMu, the system sample's
// maps were written from two goroutines and the runtime killed the daemon
// ("concurrent map iteration and map write").
func TestConcurrentSamplesAreSerialised(t *testing.T) {
	s, err := Listen(Options{Socket: filepath.Join(t.TempDir(), "s.sock"), Root: fixtureRoot(t)})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	a, b := net.Pipe()
	defer a.Close()
	go func() { _, _ = io.Copy(io.Discard, b) }()
	c := &client{conn: a, enc: json.NewEncoder(a), sub: &subscription{interval: DefaultInterval, gpu: "off", system: true}}
	s.mu.Lock()
	s.clients[c] = struct{}{}
	s.mu.Unlock()
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 200; j++ {
				s.sampleOnce()
			}
		}()
	}
	wg.Wait()
}
