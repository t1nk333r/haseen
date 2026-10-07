package borderwipe

import (
	"strconv"
	"time"
)

// MinFrame caps the loop at 10 frames a second: the pace of the loop on luna
// (1 degree every ~0.1 s), and each frame makes Hyprland redraw every border.
const MinFrame = 100 * time.Millisecond

// Pace is one turn cut into frames: how many, and how long each one lasts.
type Pace struct {
	Frames   int
	Interval time.Duration
}

// PaceFor splits a turn of `seconds` into whole frames no shorter than
// minFrame, at most one a degree. 36 s is 360 frames of 1 degree every 100 ms.
func PaceFor(seconds float64, minFrame time.Duration) Pace {
	turn := time.Duration(seconds * float64(time.Second))
	frames := 360
	if minFrame > 0 {
		if fit := int(turn / minFrame); fit < frames {
			frames = fit
		}
	}
	if frames < 1 {
		frames = 1
	}
	return Pace{Frames: frames, Interval: turn / time.Duration(frames)}
}

// Tenths is frame i's angle in tenths of a degree. It is worked out from the
// frame number, not added up, so rounding never drifts the turn.
func (p Pace) Tenths(i int) int { return (i % p.Frames) * 3600 / p.Frames }

// Frame builds the request for one angle. The colours are fixed per theme, so
// everything but the two angles is laid down once, and every frame appends
// into the same buffer: no allocation per frame.
type Frame struct {
	head, mid, tail []byte
	buf             []byte
}

// NewFrame lays down the request for these colours. The Lua is the one the
// Python loop sent: the window border and the group border, same gradient.
func NewFrame(colors []string) *Frame {
	list := []byte("{")
	for i, c := range colors {
		if i > 0 {
			list = append(list, ',', ' ')
		}
		list = append(list, '"')
		list = append(list, c...)
		list = append(list, '"')
	}
	list = append(list, '}')

	f := &Frame{}
	f.head = append([]byte("eval hl.config({ general = { col = { active_border = { colors = "), list...)
	f.head = append(f.head, ", angle = "...)
	f.mid = append([]byte(" } } }, group = { col = { border_active = { colors = "), list...)
	f.mid = append(f.mid, ", angle = "...)
	f.tail = []byte(" } } } })")
	f.buf = make([]byte, 0, len(f.head)+len(f.mid)+len(f.tail)+16)
	return f
}

// Request is the bytes to send for an angle given in tenths of a degree. The
// slice is reused by the next call.
func (f *Frame) Request(tenths int) []byte {
	b := append(f.buf[:0], f.head...)
	b = appendTenths(b, tenths)
	b = append(b, f.mid...)
	b = appendTenths(b, tenths)
	b = append(b, f.tail...)
	f.buf = b
	return b
}

func appendTenths(b []byte, tenths int) []byte {
	b = strconv.AppendInt(b, int64(tenths/10), 10)
	if frac := tenths % 10; frac != 0 {
		b = append(b, '.', byte('0'+frac))
	}
	return b
}
