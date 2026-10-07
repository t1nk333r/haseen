// Package borderwipe turns the active window border's gradient for themes
// that ask for a clockwise wipe, when Hyprland's own borderangle animation
// cannot (plan 069).
//
// A theme asks in its colors.toml:
//
//	border_wipe = "rgba(F25623ff) rgba(F25623cc) rgba(F2562311) rgba(F25623cc)"
//	border_wipe_seconds = 36
//
// The theme's hyprland.lua reads the same two keys. Up to 10 s a turn it turns
// the border with borderangle in `loop` style; Hyprland refuses an animation
// speed above 100 ds, so anything slower is this package's job. The loop is a
// port of the owner's hypr-border-wipe.py from luna: every frame one `eval
// hl.config(...)` over Hyprland's request socket, connect/send/recv/close.
package borderwipe

import (
	"bufio"
	"errors"
	"os"
	"regexp"
	"strconv"
	"strings"
)

// Theme is what colors.toml declares.
type Theme struct {
	Colors  []string
	Seconds float64
}

// Wants says the declaration is complete: at least two stops to turn and a
// pace. One colour has no visible angle.
func (t Theme) Wants() bool { return len(t.Colors) >= 2 && t.Seconds > 0 }

// Each colour goes into Lua source verbatim, so only the hex forms Hyprland
// takes are allowed: nothing in colors.toml can turn into code.
var colourRE = regexp.MustCompile(`^(rgba\([0-9a-fA-F]{8}\)|rgb\([0-9a-fA-F]{6}\)|0x[0-9a-fA-F]{8})$`)

var ErrBadColour = errors.New("border_wipe: a colour is not rgba(RRGGBBAA), rgb(RRGGBB) or 0xAARRGGBB")

// ReadTheme reads the two keys from a colors.toml. A missing file or missing
// keys is an empty Theme, not an error: most themes ask for no wipe.
func ReadTheme(path string) (Theme, error) {
	var t Theme
	f, err := os.Open(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return t, nil
		}
		return t, err
	}
	defer f.Close()
	scan := bufio.NewScanner(f)
	for scan.Scan() {
		key, value, ok := strings.Cut(scan.Text(), "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.Trim(strings.TrimSpace(value), `"'`)
		switch key {
		case "border_wipe":
			t.Colors = strings.Fields(value)
		case "border_wipe_seconds":
			t.Seconds, _ = strconv.ParseFloat(value, 64)
		}
	}
	if err := scan.Err(); err != nil {
		return Theme{}, err
	}
	for _, c := range t.Colors {
		if !colourRE.MatchString(c) {
			return Theme{}, ErrBadColour
		}
	}
	return t, nil
}
