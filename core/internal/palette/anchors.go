package palette

import "math"

// Contrast floors for the colours a generated theme names. Foreground text and
// the shell's text on `selection` are body text (WCAG AA, 4.5:1); the accent
// marks focus rings, indicators and icons, which WCAG 1.4.11 holds to 3:1.
const (
	minTextContrast   = 4.5
	minAccentContrast = 3.0
)

// The palette slots colors.toml names: background, accent and foreground (which
// is also the cursor). Slot+8 is each one's bright variant.
const (
	slotBackground = 0
	slotAccent     = 4
	slotForeground = 7
)

// baseSelection is the selection shade before the clamp: a surface step off
// the background, following aether internal/template/variables.go.
func baseSelection(bg string, light bool) string {
	if light {
		return DarkenRGB(bg, 85)
	}
	return LightenRGB(bg, 10)
}

// ClampAnchors is the last step between the generator and colors.toml. A
// wallpaper decides the background, so a pale or mid-grey image can leave the
// foreground, the accent or the selection unreadable against it whatever the
// mode. The background stays as the image gave it; the foreground and accent
// move away from it until they reach their floor, and the selection is derived
// from the clamped colours and moved away from the foreground until text on it
// reads. A colour that already passes is returned unchanged, so the clamp is
// idempotent. A moved anchor takes its bright slot with it, because
// finalizePalette derives that slot from the anchor.
func ClampAnchors(p [16]string, light bool) (palette [16]string, selection string) {
	bg := p[slotBackground]
	for _, a := range [...]struct {
		slot   int
		target float64
	}{{slotForeground, minTextContrast}, {slotAccent, minAccentContrast}} {
		if c := clampContrast(p[a.slot], bg, a.target); c != p[a.slot] {
			p[a.slot], p[a.slot+8] = c, GenerateBrightVersion(c)
		}
	}
	return p, clampContrast(baseSelection(bg, light), p[slotForeground], minTextContrast)
}

// clampContrast moves hex's OKLab lightness, keeping its hue, by the least
// amount that brings its WCAG contrast against ref up to target. It heads for
// the end of the lightness axis (white or black) with more contrast against
// ref, starting no nearer than ref's own lightness, so contrast only grows
// along the search and bisection finds the smallest move. If even that end
// falls short, the search returns the end itself, the most any colour reaches
// against ref. Black or white is at least 4.58:1 against anything, so the
// floors above are always met.
func clampContrast(hex, ref string, target float64) string {
	if ContrastRatio(hex, ref) >= target {
		return hex
	}
	lch := HexToOKLCH(hex)
	refL := HexToOKLab(ref).L
	near, far := math.Min(lch.L, refL), 0.0
	if ContrastRatio(ref, "#ffffff") >= ContrastRatio(ref, "#000000") {
		near, far = math.Max(lch.L, refL), 1
	}
	at := func(l float64) string {
		return OKLCHToHex(fitChroma(OKLCH{L: l, C: lch.C, H: lch.H}))
	}
	best := at(far)
	// 24 halvings resolve L far below one 8-bit step.
	for range 24 {
		mid := (near + far) / 2
		if c := at(mid); ContrastRatio(c, ref) >= target {
			far, best = mid, c
		} else {
			near = mid
		}
	}
	return best
}

// fitChroma lowers lch's chroma only as far as it must to land inside sRGB.
// Clipping channels instead (what OKLabToRGB does) would shift the hue.
func fitChroma(lch OKLCH) OKLCH {
	if inGamut(lch) {
		return lch
	}
	lo, hi := 0.0, lch.C
	for range 20 {
		mid := (lo + hi) / 2
		if inGamut(OKLCH{L: lch.L, C: mid, H: lch.H}) {
			lo = mid
		} else {
			hi = mid
		}
	}
	lch.C = lo
	return lch
}

func inGamut(lch OKLCH) bool {
	const eps = 1e-6 // matrix round-off at the gamut edge, e.g. white
	r, g, b := oklabToLinearRGB(OKLCHToOKLab(lch))
	return r >= -eps && r <= 1+eps && g >= -eps && g <= 1+eps && b >= -eps && b <= 1+eps
}
