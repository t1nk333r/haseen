package borderwipe

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"path/filepath"
	"strings"
	"syscall"
)

// SocketPaths are Hyprland's request socket and its event socket for one
// instance.
func SocketPaths(runtimeDir, signature string) (request, events string) {
	dir := filepath.Join(runtimeDir, "hypr", signature)
	return filepath.Join(dir, ".socket.sock"), filepath.Join(dir, ".socket2.sock")
}

// hypr talks to Hyprland's request socket. It answers one request per
// connection and then closes, so every call is connect/send/recv/close, as in
// hyprctl. Raw syscalls on one reused address and one reused reply buffer keep
// a frame free of allocations and of the runtime poller.
type hypr struct {
	addr    syscall.SockaddrUnix
	timeout syscall.Timeval
	reply   []byte
}

func newHypr(path string) *hypr {
	return &hypr{
		addr:    syscall.SockaddrUnix{Name: path},
		timeout: syscall.Timeval{Sec: 2},
		reply:   make([]byte, 0, 512),
	}
}

// errTimeout is a send or receive that took longer than two seconds: a
// Hyprland that is stuck, which counts as not answering.
var errTimeout = errors.New("hyprland did not answer within 2 s")

// request sends msg and returns the whole answer. The slice is reused by the
// next call.
func (h *hypr) request(msg []byte) ([]byte, error) {
	fd, err := syscall.Socket(syscall.AF_UNIX, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(fd)
	_ = syscall.SetsockoptTimeval(fd, syscall.SOL_SOCKET, syscall.SO_RCVTIMEO, &h.timeout)
	_ = syscall.SetsockoptTimeval(fd, syscall.SOL_SOCKET, syscall.SO_SNDTIMEO, &h.timeout)
	for {
		err = syscall.Connect(fd, &h.addr)
		if err != syscall.EINTR {
			break
		}
	}
	if err != nil {
		return nil, err
	}
	for sent := 0; sent < len(msg); {
		n, err := syscall.Write(fd, msg[sent:])
		if err == syscall.EINTR {
			continue
		}
		if err == syscall.EAGAIN {
			return nil, errTimeout
		}
		if err != nil {
			return nil, err
		}
		sent += n
	}
	h.reply = h.reply[:0]
	for {
		if len(h.reply) == cap(h.reply) {
			h.reply = append(h.reply, 0)[:len(h.reply)]
		}
		n, err := syscall.Read(fd, h.reply[len(h.reply):cap(h.reply)])
		if err == syscall.EINTR {
			continue
		}
		if err == syscall.EAGAIN {
			return nil, errTimeout
		}
		if err != nil {
			return nil, err
		}
		if n == 0 {
			return h.reply, nil
		}
		h.reply = h.reply[:len(h.reply)+n]
	}
}

// Requests the loop makes, laid down once.
var (
	reqAnimations     = []byte("j/animations")
	reqAnimationsOn   = []byte("j/getoption animations:enabled")
	reqActiveWindow   = []byte("j/activewindow")
	reqReload         = []byte("reload")
	replyErrorPrefix  = []byte("error")
	activeWindowField = []byte(`"address"`)
)

type leaf struct {
	Name       string `json:"name"`
	Overridden bool   `json:"overridden"`
	Enabled    bool   `json:"enabled"`
	Style      string `json:"style"`
}

// NativeLoop says Hyprland's borderangle animation already turns the border:
// the leaf exists, is enabled and loops. A leaf that is not overridden takes
// everything from its parent, `global` (borderangle is a direct child of it,
// beside `border`). A build without the leaf has no native wipe at all.
//
// `hyprctl -j animations` is [[leaves...], [curves...]].
func NativeLoop(reply []byte) (bool, error) {
	var doc []json.RawMessage
	if err := json.Unmarshal(reply, &doc); err != nil {
		return false, err
	}
	var leaves []leaf
	if len(doc) > 0 && bytes.HasPrefix(bytes.TrimSpace(doc[0]), []byte("[")) {
		if err := json.Unmarshal(doc[0], &leaves); err != nil {
			return false, err
		}
	} else if err := json.Unmarshal(reply, &leaves); err != nil {
		return false, err
	}
	var angle, global *leaf
	for i := range leaves {
		switch leaves[i].Name {
		case "borderangle":
			angle = &leaves[i]
		case "global":
			global = &leaves[i]
		}
	}
	if angle == nil {
		return false, nil
	}
	if !angle.Overridden && global != nil {
		angle = global
	}
	return angle.Enabled && strings.HasPrefix(angle.Style, "loop"), nil
}

// AnimationsOn reads `j/getoption animations:enabled`: {"bool": true} on
// Hyprland 0.56, {"int": 1} on older builds.
func AnimationsOn(reply []byte) (bool, error) {
	var opt struct {
		Bool *bool `json:"bool"`
		Int  *int  `json:"int"`
	}
	if err := json.Unmarshal(reply, &opt); err != nil {
		return false, err
	}
	switch {
	case opt.Bool != nil:
		return *opt.Bool, nil
	case opt.Int != nil:
		return *opt.Int != 0, nil
	}
	return false, errors.New("animations:enabled: no value in the answer")
}

// HasFocus reads `j/activewindow`: `{}` when no window has focus.
func HasFocus(reply []byte) bool { return bytes.Contains(reply, activeWindowField) }

// event is one line of Hyprland's event socket the loop cares about.
type event struct {
	reload  bool // configreloaded: the theme may have changed
	focus   bool // activewindowv2: whether a window has focus now
	isFocus bool
	gone    bool // the event socket closed: Hyprland went away
}

// watchEvents reads the event socket until it closes, then reports `gone`.
// Only configreloaded and activewindowv2 matter; the rest is skipped.
func watchEvents(conn net.Conn, out chan<- event, done <-chan struct{}) {
	scan := bufio.NewScanner(conn)
	scan.Buffer(make([]byte, 0, 1024), 64*1024)
	send := func(e event) bool {
		select {
		case out <- e:
			return true
		case <-done:
			return false
		}
	}
	for scan.Scan() {
		name, data, ok := strings.Cut(scan.Text(), ">>")
		if !ok {
			continue
		}
		switch name {
		case "configreloaded":
			if !send(event{reload: true}) {
				return
			}
		case "activewindowv2":
			if !send(event{isFocus: true, focus: data != "" && data != ","}) {
				return
			}
		}
	}
	send(event{gone: true})
}
