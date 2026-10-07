package borderwipe

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

var wipeColours = []string{"rgba(F25623ff)", "rgba(F25623cc)", "rgba(F2562311)", "rgba(F25623cc)"}

func TestPaceCutsATurnIntoFrames(t *testing.T) {
	cases := []struct {
		seconds  float64
		frames   int
		interval time.Duration
		tenths   []int // frames 0, 1, 2 and the last
	}{
		// luna's loop: a degree every 100 ms.
		{36, 360, 100 * time.Millisecond, []int{0, 10, 20, 3590}},
		// Faster than a degree per 100 ms: fewer, bigger steps, never more
		// than 10 frames a second.
		{10, 100, 100 * time.Millisecond, []int{0, 36, 72, 3564}},
		{1, 10, 100 * time.Millisecond, []int{0, 360, 720, 3240}},
		// Slower: still a degree a frame, the frames just last longer.
		{72, 360, 200 * time.Millisecond, []int{0, 10, 20, 3590}},
	}
	for _, tc := range cases {
		p := PaceFor(tc.seconds, MinFrame)
		if p.Frames != tc.frames || p.Interval != tc.interval {
			t.Errorf("%v s: got %d frames of %v, want %d of %v", tc.seconds, p.Frames, p.Interval, tc.frames, tc.interval)
		}
		got := []int{p.Tenths(0), p.Tenths(1), p.Tenths(2), p.Tenths(p.Frames - 1)}
		if fmt.Sprint(got) != fmt.Sprint(tc.tenths) {
			t.Errorf("%v s: angles %v, want %v", tc.seconds, got, tc.tenths)
		}
		if p.Tenths(p.Frames) != 0 {
			t.Errorf("%v s: the turn does not come back to 0", tc.seconds)
		}
	}
}

func TestFrameIsTheEvalTheLoopOnLunaSent(t *testing.T) {
	f := NewFrame(wipeColours)
	list := `{"rgba(F25623ff)", "rgba(F25623cc)", "rgba(F2562311)", "rgba(F25623cc)"}`
	want := "eval hl.config({ general = { col = { active_border = { colors = " + list + ", angle = 37 } } }," +
		" group = { col = { border_active = { colors = " + list + ", angle = 37 } } } })"
	if got := string(f.Request(370)); got != want {
		t.Fatalf("frame:\n got %s\nwant %s", got, want)
	}
	if got := string(f.Request(36)); !strings.Contains(got, "angle = 3.6 }") {
		t.Errorf("a fractional angle is written with its tenth: %s", got)
	}
	if allocs := testing.AllocsPerRun(200, func() { f.Request(1234) }); allocs != 0 {
		t.Errorf("a frame allocates %v times; it must reuse its buffer", allocs)
	}
}

func writeTheme(t *testing.T, state, body string) {
	t.Helper()
	dir := filepath.Join(state, "current", "theme")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "colors.toml"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadTheme(t *testing.T) {
	state := t.TempDir()
	path := filepath.Join(state, "current", "theme", "colors.toml")

	if th, err := ReadTheme(path); err != nil || th.Wants() {
		t.Errorf("no colors.toml: %+v %v, want no wipe and no error", th, err)
	}

	writeTheme(t, state, "accent = \"#F25623\"\n")
	if th, _ := ReadTheme(path); th.Wants() {
		t.Errorf("a theme without the keys asks for a wipe: %+v", th)
	}

	writeTheme(t, state, "# wipe\nborder_wipe = \"rgba(F25623ff) rgba(F25623cc) rgba(F2562311) rgba(F25623cc)\"\nborder_wipe_seconds = 36\n")
	th, err := ReadTheme(path)
	if err != nil || !th.Wants() || th.Seconds != 36 || fmt.Sprint(th.Colors) != fmt.Sprint(wipeColours) {
		t.Errorf("the haseen declaration: %+v %v", th, err)
	}

	writeTheme(t, state, "border_wipe = \"rgba(F25623ff)\"\nborder_wipe_seconds = 36\n")
	if th, _ := ReadTheme(path); th.Wants() {
		t.Errorf("one colour has no angle to turn, yet it asks: %+v", th)
	}

	// The colours go into Lua source: anything but hex is refused.
	writeTheme(t, state, "border_wipe = \"rgba(F25623ff) os.execute('x')\"\nborder_wipe_seconds = 36\n")
	if _, err := ReadTheme(path); !errors.Is(err, ErrBadColour) {
		t.Errorf("a colour that is code: %v, want ErrBadColour", err)
	}
}

// Hyprland 0.56.2's `hyprctl -j animations`, cut to the leaves that matter.
func animationsJSON(angle string) string {
	return `[[
{"name": "global", "overridden": true, "bezier": "haseenOut", "enabled": true, "speed": 4.00, "style": ""},
{"name": "border", "overridden": true, "bezier": "default", "enabled": false, "speed": 1.00, "style": ""},
` + angle + `
],[{"name": "linear", "X0": 0.00, "Y0": 0.00, "X1": 1.00, "Y1": 1.00}]]`
}

const (
	angleLoop     = `{"name": "borderangle", "overridden": true, "bezier": "linear", "enabled": true, "speed": 100.00, "style": "loop"}`
	angleOff      = `{"name": "borderangle", "overridden": true, "bezier": "default", "enabled": false, "speed": 1.00, "style": ""}`
	angleInherits = `{"name": "borderangle", "overridden": false, "bezier": "", "enabled": true, "speed": 0.00, "style": "loop"}`
	angleMissing  = `{"name": "fadeIn", "overridden": false, "bezier": "", "enabled": true, "speed": 0.00, "style": ""}`
)

func TestNativeLoop(t *testing.T) {
	cases := map[string]bool{
		angleLoop: true,
		angleOff:  false,
		// Not overridden: the leaf's own fields are not in force, global's
		// are, and global does not loop.
		angleInherits: false,
		// A build without the leaf has no native wipe.
		angleMissing: false,
	}
	for leaf, want := range cases {
		got, err := NativeLoop([]byte(animationsJSON(leaf)))
		if err != nil || got != want {
			t.Errorf("%s: %v %v, want %v", leaf, got, err, want)
		}
	}
	if _, err := NativeLoop([]byte("unknown request")); err == nil {
		t.Error("an answer that is not JSON is not an error")
	}
}

func TestOptionAndFocusAnswers(t *testing.T) {
	for reply, want := range map[string]bool{
		`{"option": "animations:enabled", "bool": true, "set": false }`: true,
		`{"option": "animations:enabled", "bool": false, "set": true }`: false,
		`{"option": "animations:enabled", "int": 1, "set": false }`:     true,
	} {
		if got, err := AnimationsOn([]byte(reply)); err != nil || got != want {
			t.Errorf("%s: %v %v", reply, got, err)
		}
	}
	if HasFocus([]byte("{}")) || !HasFocus([]byte(`{"address": "0x55d0", "class": "foot"}`)) {
		t.Error("activewindow: {} is no focus, an address is focus")
	}
}

// fakeHypr is a Hyprland for the loop: a request socket that answers one
// request per connection, as Hyprland does, and an event socket.
type fakeHypr struct {
	t          *testing.T
	req, ev    net.Listener
	reqPath    string
	evPath     string
	mu         sync.Mutex
	native     bool
	animations bool
	focused    bool
	evals      []string
	reloads    int
	evConns    []net.Conn
	wg         sync.WaitGroup
}

func startFake(t *testing.T, runtime, sig string) *fakeHypr {
	t.Helper()
	f := &fakeHypr{t: t, animations: true, focused: true}
	f.reqPath, f.evPath = SocketPaths(runtime, sig)
	f.listen()
	t.Cleanup(f.stop)
	return f
}

func (f *fakeHypr) listen() {
	if err := os.MkdirAll(filepath.Dir(f.reqPath), 0o700); err != nil {
		f.t.Fatal(err)
	}
	var err error
	if f.req, err = net.Listen("unix", f.reqPath); err != nil {
		f.t.Fatal(err)
	}
	if f.ev, err = net.Listen("unix", f.evPath); err != nil {
		f.t.Fatal(err)
	}
	req, ev := f.req, f.ev
	f.wg.Add(2)
	go func() {
		defer f.wg.Done()
		for {
			conn, err := req.Accept()
			if err != nil {
				return
			}
			f.answer(conn)
		}
	}()
	go func() {
		defer f.wg.Done()
		for {
			conn, err := ev.Accept()
			if err != nil {
				return
			}
			f.mu.Lock()
			f.evConns = append(f.evConns, conn)
			f.mu.Unlock()
		}
	}()
}

func (f *fakeHypr) answer(conn net.Conn) {
	defer conn.Close()
	buf := make([]byte, 4096)
	n, _ := conn.Read(buf)
	msg := string(buf[:n])
	f.mu.Lock()
	defer f.mu.Unlock()
	var reply string
	switch {
	case msg == "j/animations":
		leaf := angleOff
		if f.native {
			leaf = angleLoop
		}
		reply = animationsJSON(leaf)
	case msg == "j/getoption animations:enabled":
		reply = fmt.Sprintf(`{"option": "animations:enabled", "bool": %v, "set": false }`, f.animations)
	case msg == "j/activewindow":
		reply = "{}"
		if f.focused {
			reply = `{"address": "0x55d0"}`
		}
	case msg == "reload":
		f.reloads++
		reply = "ok"
	case strings.HasPrefix(msg, "eval "):
		f.evals = append(f.evals, msg)
		reply = "ok"
	default:
		reply = "unknown request"
	}
	_, _ = conn.Write([]byte(reply))
}

// push writes one event line to every event-socket client.
func (f *fakeHypr) push(line string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, c := range f.evConns {
		_, _ = c.Write([]byte(line + "\n"))
	}
}

// stop is Hyprland going away: both sockets close and their files go.
func (f *fakeHypr) stop() {
	if f.req == nil {
		return
	}
	f.req.Close()
	f.ev.Close()
	f.mu.Lock()
	for _, c := range f.evConns {
		c.Close()
	}
	f.evConns = nil
	f.mu.Unlock()
	f.wg.Wait()
	f.req, f.ev = nil, nil
}

func (f *fakeHypr) set(fn func(f *fakeHypr)) {
	f.mu.Lock()
	fn(f)
	f.mu.Unlock()
}

func (f *fakeHypr) evalCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.evals)
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// harness: a theme that asks for a wipe of 3.6 s a turn (a degree every
// 10 ms), a fake Hyprland, and a running controller.
type harness struct {
	c     *Controller
	fake  *fakeHypr
	state string
}

func start(t *testing.T, native bool) *harness {
	t.Helper()
	runtime, state := t.TempDir(), t.TempDir()
	writeTheme(t, state, "border_wipe = \"rgba(F25623ff) rgba(F2562311)\"\nborder_wipe_seconds = 3.6\n")
	fake := startFake(t, runtime, "sig")
	fake.native = native
	c := New(Options{StateDir: state, RuntimeDir: runtime, Gate: 20 * time.Millisecond, MinFrame: 10 * time.Millisecond})
	done := make(chan struct{})
	go c.Run(done)
	t.Cleanup(func() { close(done); <-c.stopped })
	c.Set(true, "sig")
	return &harness{c: c, fake: fake, state: state}
}

func (h *harness) waitState(t *testing.T, state, reason string) {
	t.Helper()
	waitFor(t, state+" "+reason, func() bool {
		s := h.c.Status()
		return s.State == state && strings.Contains(s.Reason, reason)
	})
}

func TestNeverRunsBesideTheNativeLoop(t *testing.T) {
	h := start(t, true)
	h.waitState(t, StateNative, "borderangle")
	time.Sleep(150 * time.Millisecond)
	if n := h.fake.evalCount(); n != 0 {
		t.Fatalf("%d frames sent while borderangle loops", n)
	}
}

func TestTurnsTheBorderOneDegreeAFrame(t *testing.T) {
	h := start(t, false)
	h.waitState(t, StateRunning, "")
	waitFor(t, "five frames", func() bool { return h.fake.evalCount() >= 5 })
	h.fake.mu.Lock()
	evals := append([]string(nil), h.fake.evals[:5]...)
	h.fake.mu.Unlock()
	for i, e := range evals {
		if want := fmt.Sprintf("angle = %d }", i); !strings.Contains(e, want) {
			t.Errorf("frame %d: %q lacks %q", i, e, want)
		}
		if !strings.Contains(e, `colors = {"rgba(F25623ff)", "rgba(F2562311)"}`) {
			t.Errorf("frame %d does not carry the theme's colours: %s", i, e)
		}
	}
	if s := h.c.Status(); s.Frames < 5 || s.SecondsPerTurn != 3.6 {
		t.Errorf("status: %+v", s)
	}
}

func TestPausesAndResumes(t *testing.T) {
	h := start(t, false)
	h.waitState(t, StateRunning, "")
	flag := filepath.Join(h.state, "flags", "context")
	if err := os.MkdirAll(filepath.Dir(flag), 0o755); err != nil {
		t.Fatal(err)
	}

	stillWhile := func(what string) {
		t.Helper()
		n := h.fake.evalCount()
		time.Sleep(100 * time.Millisecond)
		if m := h.fake.evalCount(); m != n {
			t.Errorf("%d frames sent while paused for %s", m-n, what)
		}
	}
	resumes := func(what string) {
		t.Helper()
		h.waitState(t, StateRunning, "")
		n := h.fake.evalCount()
		waitFor(t, "frames after "+what, func() bool { return h.fake.evalCount() > n+2 })
	}

	if err := os.WriteFile(flag, []byte("game\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	h.waitState(t, StatePaused, "game context")
	angle := h.c.Status().Angle
	stillWhile("the game context")
	if err := os.WriteFile(flag, []byte("focus\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	resumes("leaving game")
	if a := h.c.Status().Angle; a <= angle {
		t.Errorf("the turn starts over after a pause: %v then %v", angle, a)
	}

	h.fake.set(func(f *fakeHypr) { f.animations = false })
	h.waitState(t, StatePaused, "animations are off")
	stillWhile("animations off")
	h.fake.set(func(f *fakeHypr) { f.animations = true })
	resumes("animations on")

	h.fake.push("activewindowv2>>")
	h.waitState(t, StatePaused, "no window has focus")
	stillWhile("no focus")
	h.fake.push("activewindowv2>>55d0a1b2c3")
	resumes("a window took focus")
}

func TestReconnectsWhenHyprlandComesBack(t *testing.T) {
	h := start(t, false)
	h.waitState(t, StateRunning, "")
	h.fake.stop()
	h.waitState(t, StateWaiting, "not answering")
	if _, err := os.Stat(h.fake.reqPath); !os.IsNotExist(err) {
		t.Fatalf("the fake's socket is still there: %v", err)
	}
	h.fake.listen()
	h.waitState(t, StateRunning, "")
	n := h.fake.evalCount()
	waitFor(t, "frames on the new socket", func() bool { return h.fake.evalCount() > n+2 })
}

func TestReloadHandsTheBorderBack(t *testing.T) {
	h := start(t, false)
	h.waitState(t, StateRunning, "")
	waitFor(t, "a frame", func() bool { return h.fake.evalCount() > 0 })

	// `haseen theme set` swaps the theme, then reloads Hyprland.
	writeTheme(t, h.state, "accent = \"#7aa2f7\"\n")
	h.fake.push("configreloaded>>")
	h.waitState(t, StateOff, "no wipe")
	waitFor(t, "the reload that drops a late frame", func() bool {
		h.fake.mu.Lock()
		defer h.fake.mu.Unlock()
		return h.fake.reloads == 1
	})
	n := h.fake.evalCount()
	// That reload's own event finds nothing sent and asks for no other.
	h.fake.push("configreloaded>>")
	time.Sleep(100 * time.Millisecond)
	h.fake.mu.Lock()
	reloads := h.fake.reloads
	h.fake.mu.Unlock()
	if reloads != 1 || h.fake.evalCount() != n {
		t.Errorf("after the hand-back: %d reloads, %d new frames", reloads, h.fake.evalCount()-n)
	}

	// Back to a wipe theme, now drawn by borderangle: still no frames.
	writeTheme(t, h.state, "border_wipe = \"rgba(F25623ff) rgba(F2562311)\"\nborder_wipe_seconds = 10\n")
	h.fake.set(func(f *fakeHypr) { f.native = true })
	h.fake.push("configreloaded>>")
	h.waitState(t, StateNative, "")
	if h.fake.evalCount() != n {
		t.Error("frames went out beside the native loop")
	}
}

func TestOffWithoutASubscriber(t *testing.T) {
	h := start(t, false)
	h.waitState(t, StateRunning, "")
	waitFor(t, "a frame", func() bool { return h.fake.evalCount() > 0 })
	h.c.Set(false, "")
	h.waitState(t, StateOff, "nobody subscribed")
	n := h.fake.evalCount()
	time.Sleep(80 * time.Millisecond)
	if h.fake.evalCount() != n {
		t.Error("frames after the last subscriber left")
	}
}
