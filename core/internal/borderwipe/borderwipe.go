package borderwipe

import (
	"bytes"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// States, in the order a subscription usually meets them.
const (
	// StateOff: nobody subscribed, or the theme asks for no wipe.
	StateOff = "off"
	// StateWaiting: the theme asks, but Hyprland is not answering (not
	// started yet, restarting, or it refused a frame). Retried every gate.
	StateWaiting = "waiting"
	// StateNative: Hyprland's borderangle animation loops; the loop stands
	// aside so the two never run together.
	StateNative = "native"
	// StatePaused: the loop is ours but holds still (game context,
	// animations off, no window focused).
	StatePaused = "paused"
	// StateRunning: a frame every Pace.Interval.
	StateRunning = "running"
)

// Status is what the sidecar reports: as a `borderwipe` event when State,
// Reason or the pace changes, and with Angle and Frames from `status`.
type Status struct {
	State          string  `json:"state"`
	Reason         string  `json:"reason,omitempty"`
	SecondsPerTurn float64 `json:"secondsPerTurn,omitempty"`
	Angle          float64 `json:"angle"`
	Frames         uint64  `json:"frames"`
}

type Options struct {
	// StateDir is haseen's user state ($HASEEN_USER_STATE): the theme is
	// current/theme/colors.toml and the context is flags/context.
	StateDir string
	// RuntimeDir holds Hyprland's sockets under hypr/<signature>/.
	RuntimeDir string
	// Signature is the instance to use when a subscriber names none.
	Signature string
	// Gate is how often a loop that is ours re-reads the context flag and
	// animations:enabled, and how often a missing Hyprland is retried.
	// Default 2 s, the shortest poll haseen allows (architecture §6).
	Gate time.Duration
	// MinFrame is the shortest frame; default MinFrame (10 frames a second).
	MinFrame time.Duration
	// OnChange is called from the loop's goroutine when the status changes.
	OnChange func(Status)
}

type control struct {
	active    bool
	signature string
	announce  bool
}

// Controller owns the loop. Set says whether anyone wants it and for which
// Hyprland instance; Run does the rest on one goroutine.
type Controller struct {
	opts    Options
	ctl     chan control
	stopped chan struct{}

	mu     sync.Mutex
	status Status

	tenths atomic.Int64
	frames atomic.Uint64
}

func New(opts Options) *Controller {
	if opts.Gate <= 0 {
		opts.Gate = 2 * time.Second
	}
	if opts.MinFrame <= 0 {
		opts.MinFrame = MinFrame
	}
	return &Controller{
		opts:    opts,
		ctl:     make(chan control, 8),
		stopped: make(chan struct{}),
		status:  Status{State: StateOff, Reason: "nobody subscribed"},
	}
}

// Set turns the loop on for a Hyprland instance (signature "" = the default
// one) or off. Asking for what is already so does nothing. It never blocks on
// a loop that has ended.
func (c *Controller) Set(active bool, signature string) {
	c.send(control{active: active, signature: signature})
}

// Announce hands the status to OnChange once the requests before it are
// handled, changed or not: a new subscriber learns the state it joined.
func (c *Controller) Announce() { c.send(control{announce: true}) }

func (c *Controller) send(ctl control) {
	select {
	case c.ctl <- ctl:
	case <-c.stopped:
	}
}

// Status is the current state with the angle last sent and the frame count.
func (c *Controller) Status() Status {
	c.mu.Lock()
	s := c.status
	c.mu.Unlock()
	s.Angle = float64(c.tenths.Load()) / 10
	s.Frames = c.frames.Load()
	return s
}

func (c *Controller) publish(state, reason string, seconds float64) {
	c.mu.Lock()
	changed := c.status.State != state || c.status.Reason != reason || c.status.SecondsPerTurn != seconds
	c.status.State, c.status.Reason, c.status.SecondsPerTurn = state, reason, seconds
	c.mu.Unlock()
	if changed && c.opts.OnChange != nil {
		c.opts.OnChange(c.Status())
	}
}

// Run is the loop; it returns when done closes.
func (c *Controller) Run(done <-chan struct{}) {
	l := &loop{c: c}
	defer close(c.stopped)
	defer l.disconnect()
	for {
		var frameC, gateC <-chan time.Time
		if l.frameT != nil {
			frameC = l.frameT.C
		}
		if l.gateT != nil {
			gateC = l.gateT.C
		}
		select {
		case <-done:
			l.stopFrames()
			l.stopGate()
			return
		case ctl := <-c.ctl:
			if ctl.announce {
				if c.opts.OnChange != nil {
					c.opts.OnChange(c.Status())
				}
				continue
			}
			if ctl.active == l.active && ctl.signature == l.signature {
				continue
			}
			if ctl.signature != l.signature {
				l.disconnect()
			}
			l.active, l.signature = ctl.active, ctl.signature
			l.full()
		case <-frameC:
			l.frame()
		case <-gateC:
			l.gate()
		case e := <-l.events:
			l.event(e)
		}
	}
}

// loop is the state Run keeps between wake-ups. Only Run's goroutine touches it.
type loop struct {
	c         *Controller
	active    bool
	signature string

	hy        *hypr
	events    chan event
	eventsEnd chan struct{}
	conn      net.Conn

	theme  Theme
	pace   Pace
	frameB *Frame
	i      int

	state      string
	focused    bool
	animations bool
	game       bool
	// Frames went out since the last configreloaded: a frame Hyprland took
	// after the reload would outlive it.
	sentSinceReload bool

	frameT *time.Ticker
	gateT  *time.Ticker
}

func (l *loop) set(state, reason string) {
	l.state = state
	l.c.publish(state, reason, l.theme.Seconds)
}

// full works everything out again: on (un)subscribe, after a reload, and
// while Hyprland is missing.
func (l *loop) full() {
	if !l.active {
		l.disconnect()
		l.stopGate()
		l.theme = Theme{}
		l.set(StateOff, "nobody subscribed")
		return
	}
	theme, err := ReadTheme(filepath.Join(l.c.opts.StateDir, "current", "theme", "colors.toml"))
	if err != nil {
		theme = Theme{}
	}
	if !sameTheme(theme, l.theme) {
		l.stopFrames()
		l.theme = theme
		l.i = 0
		if theme.Wants() {
			l.pace = PaceFor(theme.Seconds, l.c.opts.MinFrame)
			l.frameB = NewFrame(theme.Colors)
		}
	}
	connected := l.connect()
	if !theme.Wants() {
		l.stopFrames()
		// Without the event socket a theme switch (which reloads Hyprland)
		// would go unseen; keep trying to reach it.
		l.gateWhile(!connected)
		reason := "the theme asks for no wipe"
		if err != nil {
			reason = "colors.toml: " + err.Error()
		}
		l.set(StateOff, reason)
		return
	}
	if !connected {
		l.waiting("Hyprland is not answering")
		return
	}
	reply, err := l.hy.request(reqAnimations)
	if err != nil {
		l.waiting("Hyprland is not answering")
		return
	}
	native, err := NativeLoop(reply)
	if err != nil {
		l.waiting("hyprctl animations: " + err.Error())
		return
	}
	if native {
		// Nothing changes the leaf but a reload, which is an event: no gate.
		l.stopFrames()
		l.stopGate()
		l.set(StateNative, "Hyprland's borderangle animation turns it")
		return
	}
	reply, err = l.hy.request(reqActiveWindow)
	if err != nil {
		l.waiting("Hyprland is not answering")
		return
	}
	l.focused = HasFocus(reply)
	l.light()
}

// light re-reads what changes without a reload: the context flag and
// animations:enabled (`haseen context game` and `haseen toggle animations`
// set it with eval).
func (l *loop) light() {
	flag, _ := os.ReadFile(filepath.Join(l.c.opts.StateDir, "flags", "context"))
	l.game = strings.TrimSpace(string(flag)) == "game"
	reply, err := l.hy.request(reqAnimationsOn)
	if err != nil {
		l.waiting("Hyprland is not answering")
		return
	}
	on, err := AnimationsOn(reply)
	if err != nil {
		l.waiting("hyprctl getoption: " + err.Error())
		return
	}
	l.animations = on
	l.decide()
}

// decide runs or pauses a loop that is ours, from what light and the events
// last saw.
func (l *loop) decide() {
	l.gateWhile(true)
	switch {
	case l.game:
		l.pause("game context")
	case !l.animations:
		l.pause("animations are off")
	case !l.focused:
		l.pause("no window has focus")
	default:
		if l.frameT == nil {
			l.frameT = time.NewTicker(l.pace.Interval)
		}
		l.set(StateRunning, "")
	}
}

func (l *loop) pause(reason string) {
	l.stopFrames()
	l.set(StatePaused, reason)
}

func (l *loop) waiting(reason string) {
	l.disconnect()
	l.gateWhile(true)
	l.set(StateWaiting, reason)
}

func (l *loop) ours() bool { return l.state == StateRunning || l.state == StatePaused }

func (l *loop) gate() {
	if l.conn != nil && l.ours() {
		l.light()
		return
	}
	l.full()
}

func (l *loop) frame() {
	tenths := l.pace.Tenths(l.i)
	reply, err := l.hy.request(l.frameB.Request(tenths))
	if err != nil {
		l.waiting("Hyprland is not answering")
		return
	}
	if bytes.HasPrefix(reply, replyErrorPrefix) {
		line, _, _ := bytes.Cut(reply, []byte("\n"))
		l.waiting("Hyprland refused the frame: " + string(line))
		return
	}
	l.i = (l.i + 1) % l.pace.Frames
	l.sentSinceReload = true
	l.c.tenths.Store(int64(tenths))
	l.c.frames.Add(1)
}

func (l *loop) event(e event) {
	switch {
	case e.gone:
		// Waiting when the theme asks for a wipe, off when it does not.
		l.disconnect()
		l.full()
	case e.reload:
		sent := l.sentSinceReload
		l.sentSinceReload = false
		l.full()
		// The reload handed the border back (a theme without a wipe, or one
		// borderangle turns). A frame of ours in flight may have landed after
		// it, with the old theme's colours; one more reload makes the new
		// config stand as written. That reload's own event finds nothing sent.
		if sent && (l.state == StateOff || l.state == StateNative) && l.hy != nil {
			_, _ = l.hy.request(reqReload)
		}
	case e.isFocus:
		l.focused = e.focus
		if l.ours() {
			l.decide()
		}
	}
}

func (l *loop) connect() bool {
	if l.conn != nil {
		return true
	}
	sig := l.signature
	if sig == "" {
		sig = l.c.opts.Signature
	}
	if sig == "" {
		return false
	}
	request, events := SocketPaths(l.c.opts.RuntimeDir, sig)
	conn, err := net.DialTimeout("unix", events, 2*time.Second)
	if err != nil {
		return false
	}
	l.conn = conn
	l.hy = newHypr(request)
	l.events = make(chan event)
	l.eventsEnd = make(chan struct{})
	go watchEvents(conn, l.events, l.eventsEnd)
	return true
}

func (l *loop) disconnect() {
	l.stopFrames()
	if l.conn == nil {
		return
	}
	close(l.eventsEnd)
	_ = l.conn.Close()
	l.conn, l.events, l.eventsEnd = nil, nil, nil
}

func (l *loop) stopFrames() {
	if l.frameT != nil {
		l.frameT.Stop()
		l.frameT = nil
	}
}

func (l *loop) gateWhile(on bool) {
	if !on {
		l.stopGate()
		return
	}
	if l.gateT == nil {
		l.gateT = time.NewTicker(l.c.opts.Gate)
	}
}

func (l *loop) stopGate() {
	if l.gateT != nil {
		l.gateT.Stop()
		l.gateT = nil
	}
}

func sameTheme(a, b Theme) bool {
	if a.Seconds != b.Seconds || len(a.Colors) != len(b.Colors) {
		return false
	}
	for i := range a.Colors {
		if a.Colors[i] != b.Colors[i] {
			return false
		}
	}
	return true
}
