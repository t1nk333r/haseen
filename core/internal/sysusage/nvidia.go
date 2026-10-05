package sysusage

import (
	"bufio"
	"os/exec"
	"strconv"
	"strings"
	"sync"
)

// nvidiaStream is one long-running `nvidia-smi -l` per daemon, exactly what
// Sampler.qml ran per shell: polling it per tick would start a process every
// three seconds instead.
type nvidiaStream struct {
	slot string
	cmd  *exec.Cmd

	mu    sync.Mutex
	value float64
}

func (s *Sampler) nvidiaValue(slot string) float64 {
	if s.gpu.nvidia == nil || s.gpu.nvidia.slot != slot {
		s.stopNvidia()
		s.gpu.nvidia = startNvidia(slot)
	}
	if s.gpu.nvidia == nil {
		return -1
	}
	s.gpu.nvidia.mu.Lock()
	defer s.gpu.nvidia.mu.Unlock()
	return s.gpu.nvidia.value
}

func (s *Sampler) stopNvidia() {
	if s.gpu.nvidia == nil {
		return
	}
	if s.gpu.nvidia.cmd != nil && s.gpu.nvidia.cmd.Process != nil {
		_ = s.gpu.nvidia.cmd.Process.Kill()
		_ = s.gpu.nvidia.cmd.Wait()
	}
	s.gpu.nvidia = nil
}

func startNvidia(slot string) *nvidiaStream {
	cmd := exec.Command("nvidia-smi",
		"--query-gpu=utilization.gpu", "--format=csv,noheader,nounits",
		"-i", slot, "-l", "3")
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil
	}
	if err := cmd.Start(); err != nil {
		return nil
	}
	stream := &nvidiaStream{slot: slot, cmd: cmd, value: -1}
	go func() {
		scan := bufio.NewScanner(out)
		for scan.Scan() {
			v, err := strconv.ParseFloat(strings.TrimSpace(scan.Text()), 64)
			stream.mu.Lock()
			if err == nil {
				stream.value = clamp(v)
			}
			stream.mu.Unlock()
		}
	}()
	return stream
}
