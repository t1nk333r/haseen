// Package server is the sidecar: one unix socket, JSON lines, and a sampler
// that runs only while somebody is subscribed.
//
// Adapted from DankMaterialShell core/internal/server (MIT, Copyright (c) 2025
// Avenge Media LLC): a single daemon the shell connects to, capabilities
// announced on connect, and per-stream subscriptions instead of a request per
// frame. haseen keeps this to one stream.
package server

import (
	"bufio"
	"encoding/json"
	"errors"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/t1nk333r/haseen/core/internal/proto"
	"github.com/t1nk333r/haseen/core/internal/sysusage"
)

const (
	// DefaultInterval matches the 3 s tick haseen.sysusage used in QML.
	DefaultInterval = 3 * time.Second
	minInterval     = 500 * time.Millisecond
)

type Options struct {
	Socket string
	// Version is reported in the hello frame; the installer passes
	// share/haseen/VERSION so a stale binary is visible.
	Version string
	// IdleTimeout exits the daemon once the last client has gone, so nothing
	// lingers on a machine that never opens the widget. Zero disables it.
	IdleTimeout time.Duration
	// Root is the filesystem the sampler reads ("" = this machine).
	Root string
}

type subscription struct {
	interval time.Duration
	gpu      string
	top      bool
	system   bool
}

type client struct {
	conn net.Conn
	enc  *json.Encoder
	mu   sync.Mutex
	sub  *subscription
}

func (c *client) send(v any) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.enc.Encode(v); err != nil {
		_ = c.conn.Close()
	}
}

type Server struct {
	opts    Options
	ln      net.Listener
	sampler sysusage.Sampler

	mu      sync.Mutex
	clients map[*client]struct{}
	ticker  *time.Timer
	lastGo  time.Time
	done    chan struct{}
	once    sync.Once
}

func Capabilities() []string { return []string{proto.StreamSysusage} }

// ErrAlreadyRunning says a live daemon already owns the socket. The caller that
// started this one on demand wants the socket, not this process, so it reports
// the socket as ready and exits.
var ErrAlreadyRunning = errors.New("another sidecar already owns the socket")

func Listen(opts Options) (*Server, error) {
	if opts.Socket == "" {
		return nil, errors.New("no socket path")
	}
	if err := os.MkdirAll(filepath.Dir(opts.Socket), 0o700); err != nil {
		return nil, err
	}
	// A socket left by a daemon that died is not an owner: connect first, and
	// only remove it when nothing answers.
	if conn, err := net.Dial("unix", opts.Socket); err == nil {
		conn.Close()
		return nil, ErrAlreadyRunning
	}
	_ = os.Remove(opts.Socket)

	ln, err := net.Listen("unix", opts.Socket)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(opts.Socket, 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	return &Server{
		opts:    opts,
		ln:      ln,
		sampler: sysusage.Sampler{Root: opts.Root},
		clients: map[*client]struct{}{},
		lastGo:  time.Now(),
		done:    make(chan struct{}),
	}, nil
}

func (s *Server) Addr() string { return s.opts.Socket }

func (s *Server) Close() {
	s.once.Do(func() {
		close(s.done)
		_ = s.ln.Close()
		_ = os.Remove(s.opts.Socket)
	})
}

// Serve accepts clients until Close. It returns when the listener is closed or
// the idle timeout expires with nobody connected.
func (s *Server) Serve() error {
	go s.idleWatch()
	for {
		conn, err := s.ln.Accept()
		if err != nil {
			select {
			case <-s.done:
				return nil
			default:
				return err
			}
		}
		go s.handle(conn)
	}
}

func (s *Server) idleWatch() {
	if s.opts.IdleTimeout <= 0 {
		return
	}
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-tick.C:
			s.mu.Lock()
			idle := len(s.clients) == 0 && time.Since(s.lastGo) > s.opts.IdleTimeout
			s.mu.Unlock()
			if idle {
				log.Printf("no clients for %s, exiting", s.opts.IdleTimeout)
				s.Close()
				return
			}
		}
	}
}

func (s *Server) handle(conn net.Conn) {
	c := &client{conn: conn, enc: json.NewEncoder(conn)}
	s.mu.Lock()
	s.clients[c] = struct{}{}
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		delete(s.clients, c)
		s.lastGo = time.Now()
		s.mu.Unlock()
		s.reschedule()
		_ = conn.Close()
	}()

	c.send(proto.Hello{
		Type:         proto.TypeHello,
		Protocol:     proto.Version,
		Version:      s.opts.Version,
		PID:          os.Getpid(),
		Capabilities: Capabilities(),
	})

	scan := bufio.NewScanner(conn)
	scan.Buffer(make([]byte, 0, 4096), 1<<20)
	for scan.Scan() {
		line := scan.Bytes()
		if len(line) == 0 {
			continue
		}
		var req proto.Request
		if err := json.Unmarshal(line, &req); err != nil {
			c.send(proto.Reply{Type: proto.TypeReply, OK: false, Error: "bad json"})
			continue
		}
		s.dispatch(c, req)
	}
}

func (s *Server) dispatch(c *client, req proto.Request) {
	reply := proto.Reply{Type: proto.TypeReply, ID: req.ID, OK: true}
	switch req.Method {
	case proto.MethodCapabilities:
		reply.Capabilities = Capabilities()
	case proto.MethodSubscribe:
		if req.Stream != proto.StreamSysusage {
			reply.OK, reply.Error = false, "unknown stream: "+req.Stream
			break
		}
		sub := &subscription{interval: DefaultInterval, gpu: "auto"}
		if v, ok := req.Params["intervalMs"].(float64); ok && v > 0 {
			sub.interval = time.Duration(v) * time.Millisecond
			if sub.interval < minInterval {
				sub.interval = minInterval
			}
		}
		if v, ok := req.Params["gpu"].(string); ok && v != "" {
			sub.gpu = v
		}
		sub.top, _ = req.Params["processes"].(bool)
		sub.system, _ = req.Params["system"].(bool)
		s.mu.Lock()
		c.sub = sub
		s.mu.Unlock()
		s.reschedule()
		// Answer the first sample immediately: a widget that just appeared
		// should not show "?" for a whole interval.
		go s.sampleOnce()
	case proto.MethodUnsubscribe:
		s.mu.Lock()
		c.sub = nil
		s.mu.Unlock()
		s.reschedule()
	case proto.MethodShutdown:
		c.send(reply)
		s.Close()
		return
	default:
		reply.OK, reply.Error = false, "unknown method: "+req.Method
	}
	if req.ID != 0 || !reply.OK {
		c.send(reply)
	}
}

// reschedule starts, re-times or stops the sampling timer. The daemon samples
// only while at least one client is subscribed, at the shortest interval asked
// for: nothing runs while the widget is hidden.
func (s *Server) reschedule() {
	s.mu.Lock()
	defer s.mu.Unlock()

	var interval time.Duration
	for c := range s.clients {
		if c.sub == nil {
			continue
		}
		if interval == 0 || c.sub.interval < interval {
			interval = c.sub.interval
		}
	}
	if s.ticker != nil {
		s.ticker.Stop()
		s.ticker = nil
	}
	if interval == 0 {
		return
	}
	s.ticker = time.AfterFunc(interval, s.tick)
}

func (s *Server) tick() {
	s.sampleOnce()
	s.reschedule()
}

func (s *Server) sampleOnce() {
	s.mu.Lock()
	subs := make([]*client, 0, len(s.clients))
	gpu, top, system := "off", false, false
	for c := range s.clients {
		if c.sub == nil {
			continue
		}
		subs = append(subs, c)
		if c.sub.gpu != "off" {
			gpu = c.sub.gpu
		}
		top = top || c.sub.top
		system = system || c.sub.system
	}
	s.mu.Unlock()
	if len(subs) == 0 {
		return
	}

	// One sample for every subscriber: two bars on two screens and the panel
	// read the same files once, which the per-widget QML sampler could not do.
	// The process list and the system stats are read when anyone asks, and
	// everyone receives them.
	sample := s.sampler.Sample(gpu, top, system)
	event := proto.Event{Type: proto.TypeEvent, Stream: proto.StreamSysusage, Data: sample}
	for _, c := range subs {
		c.send(event)
	}
}
