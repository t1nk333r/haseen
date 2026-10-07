package palette

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"testing"
)

// Every mode the generator accepts (validateMode), not only the ones the CLI
// help lists.
var allModes = append(append([]string{}, Modes...),
	"fire", "ocean", "forest", "earthtone", "neon", "sunset", "vaporwave", "midnight", "aurora")

// writeFuncImage paints pix(x, y) over a 96x96 image: enough distinct pixels
// for the extractor's eight dominant colours, while staying low-contrast.
func writeFuncImage(t *testing.T, path string, pix func(x, y int) color.RGBA) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 96, 96))
	for y := range 96 {
		for x := range 96 {
			img.Set(x, y, pix(x, y))
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

// Wallpapers that leave the generator little contrast to work with.
var lowContrastImages = map[string]func(x, y int) color.RGBA{
	// Near-uniform mid-grey, 118-139 per channel.
	"mid-grey": func(x, y int) color.RGBA {
		v := uint8(118 + (x+y)%22)
		return color.RGBA{v, v, v + uint8(x%3), 255}
	},
	// Pale pastel wash: high lightness, low saturation, every hue.
	"pastel": func(x, y int) color.RGBA {
		rgb := HSLToRGB(float64(x)*360/96, 35, 82+float64(y%8))
		return color.RGBA{uint8(rgb.R), uint8(rgb.G), uint8(rgb.B), 255}
	},
	// Muddy mid-tone colour field.
	"mid-tone": func(x, y int) color.RGBA {
		rgb := HSLToRGB(float64(x*3+y)*360/384, 30, 45+float64(y%10))
		return color.RGBA{uint8(rgb.R), uint8(rgb.G), uint8(rgb.B), 255}
	},
	// Greyed hue washes: in light mode the generator's own selection comes out
	// under 4.5:1 against its foreground (3.5:1 and 3.7:1 before the clamp).
	"grey-wash": hueWash(42.5, 15),
	"pale-wash": hueWash(40, 40),
}

// hueWash sweeps every hue at 15% HSL saturation, lightness from lo to lo+span.
func hueWash(lo, span float64) func(x, y int) color.RGBA {
	return func(x, y int) color.RGBA {
		rgb := HSLToRGB(float64(x)*360/96, 15, lo+float64(y)*span/96)
		return color.RGBA{uint8(rgb.R), uint8(rgb.G), uint8(rgb.B), 255}
	}
}

func assertAnchorsReadable(t *testing.T, p [16]string, selection string) {
	t.Helper()
	bg, fg, accent := p[slotBackground], p[slotForeground], p[slotAccent]
	if c := ContrastRatio(fg, bg); c < minTextContrast {
		t.Errorf("foreground %s on background %s: %.2f:1", fg, bg, c)
	}
	if c := ContrastRatio(accent, bg); c < minAccentContrast {
		t.Errorf("accent %s on background %s: %.2f:1", accent, bg, c)
	}
	if c := ContrastRatio(fg, selection); c < minTextContrast {
		t.Errorf("foreground %s on selection %s: %.2f:1", fg, selection, c)
	}
}

// hueShift is the OKLab hue difference ΔH = 2·√(C1·C2)·sin(Δh/2): a hue swing
// on a near-grey colour, which 8-bit rounding causes, weighs almost nothing.
func hueShift(a, b string) float64 {
	x, y := HexToOKLCH(a), HexToOKLCH(b)
	return 2 * math.Sqrt(x.C*y.C) * math.Abs(math.Sin((x.H-y.H)*math.Pi/360))
}

const maxHueShift = 0.01

// Generated themes from low-contrast wallpapers meet every floor, in every
// mode, light and dark, whether the palette is fresh or from the cache; the
// anchors keep their hue, and the background is never touched.
func TestGeneratedThemesKeepAnchorContrast(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	clamped := 0
	for name, pix := range lowContrastImages {
		path := filepath.Join(dir, name+".png")
		writeFuncImage(t, path, pix)
		for _, light := range []bool{false, true} {
			for _, mode := range allModes {
				result, err := Generate(path, light, mode)
				if err != nil {
					t.Fatalf("%s light=%t %s: %v", name, light, mode, err)
				}
				assertAnchorsReadable(t, result.Palette, result.Selection)

				raw, ok := loadCached(cacheKey(result.Seed, mode, light))
				if !ok {
					t.Fatalf("%s light=%t %s: no cache entry", name, light, mode)
				}
				if result.Palette[slotBackground] != raw[slotBackground] {
					t.Errorf("%s light=%t %s: the background moved", name, light, mode)
				}
				rawSelection := baseSelection(raw[slotBackground], light)
				for role, pair := range map[string][2]string{
					"foreground": {raw[slotForeground], result.Palette[slotForeground]},
					"accent":     {raw[slotAccent], result.Palette[slotAccent]},
					"selection":  {rawSelection, result.Selection},
				} {
					if d := hueShift(pair[0], pair[1]); d > maxHueShift {
						t.Errorf("%s light=%t %s: %s %s -> %s shifted hue by %.4f", name, light, mode, role, pair[0], pair[1], d)
					}
				}
				if result.Palette != raw || result.Selection != rawSelection {
					clamped++
					t.Logf("%s light=%t %s: bg %s; fg %s %.2f -> %s %.2f; accent %s %.2f -> %s %.2f; fg on selection %s %.2f -> %s %.2f",
						name, light, mode, raw[slotBackground],
						raw[slotForeground], ContrastRatio(raw[slotForeground], raw[slotBackground]),
						result.Palette[slotForeground], ContrastRatio(result.Palette[slotForeground], raw[slotBackground]),
						raw[slotAccent], ContrastRatio(raw[slotAccent], raw[slotBackground]),
						result.Palette[slotAccent], ContrastRatio(result.Palette[slotAccent], raw[slotBackground]),
						rawSelection, ContrastRatio(raw[slotForeground], rawSelection),
						result.Selection, ContrastRatio(result.Palette[slotForeground], result.Selection))
				}

				again, err := Generate(path, light, mode)
				if err != nil || !again.Cached || again.Palette != result.Palette || again.Selection != result.Selection {
					t.Errorf("%s light=%t %s: the cached run differs from the fresh one", name, light, mode)
				}
			}
		}
	}
	// Keeps the images honest: if the generator stops producing an unreadable
	// anchor for all of them, this test no longer covers the clamp.
	if clamped == 0 {
		t.Error("no generated palette needed the clamp; pick lower-contrast images")
	}
}

// The clamp only moves lightness, by the least that meets the floor, toward
// the end of the axis with more room; a colour can cross the background to get
// there.
func TestClampAnchorsOnLowContrastSets(t *testing.T) {
	cases := []struct {
		name                string
		bg, fg, accent      string
		light               bool
		wantFgUp, wantAccUp bool
	}{
		{"dark mid-grey", "#6e6e6e", "#9a9a9a", "#7a8cb0", false, true, true},
		{"light pastel", "#e9dff0", "#c9b8d6", "#a9c7e8", true, false, false},
		{"fg on the near side", "#5a5a5a", "#4a4060", "#4c5a80", false, true, true},
		{"saturated accent", "#202020", "#3a3a3a", "#1030ff", false, true, true},
	}
	for _, tc := range cases {
		var p [16]string
		for i := range p {
			p[i] = tc.bg
		}
		p[slotForeground], p[slotAccent] = tc.fg, tc.accent
		got, selection := ClampAnchors(p, tc.light)
		assertAnchorsReadable(t, got, selection)
		for role, pair := range map[string][2]string{
			"foreground": {tc.fg, got[slotForeground]},
			"accent":     {tc.accent, got[slotAccent]},
			"selection":  {baseSelection(tc.bg, tc.light), selection},
		} {
			if d := hueShift(pair[0], pair[1]); d > maxHueShift {
				t.Errorf("%s: %s %s -> %s shifted hue by %.4f", tc.name, role, pair[0], pair[1], d)
			}
		}
		if up := HexToOKLab(got[slotForeground]).L > HexToOKLab(tc.fg).L; up != tc.wantFgUp {
			t.Errorf("%s: foreground went up=%t", tc.name, up)
		}
		if up := HexToOKLab(got[slotAccent]).L > HexToOKLab(tc.accent).L; up != tc.wantAccUp {
			t.Errorf("%s: accent went up=%t", tc.name, up)
		}
		if got[slotForeground+8] != GenerateBrightVersion(got[slotForeground]) ||
			got[slotAccent+8] != GenerateBrightVersion(got[slotAccent]) {
			t.Errorf("%s: a moved anchor left its bright slot behind", tc.name)
		}
		// Least move: one 8-bit lightness step back toward the original fails.
		for role, pair := range map[string][3]string{
			"foreground": {tc.fg, got[slotForeground], tc.bg},
			"accent":     {tc.accent, got[slotAccent], tc.bg},
		} {
			target := minTextContrast
			if role == "accent" {
				target = minAccentContrast
			}
			lch := HexToOKLCH(pair[1])
			lch.L += math.Copysign(0.01, HexToOKLab(pair[0]).L-lch.L)
			if back := OKLCHToHex(fitChroma(lch)); ContrastRatio(back, pair[2]) >= target {
				t.Errorf("%s: %s %s overshot: %s also passes", tc.name, role, pair[1], back)
			}
		}
		// Idempotent: the clamped palette passes, so nothing moves again.
		if again, sel := ClampAnchors(got, tc.light); again != got || sel != selection {
			t.Errorf("%s: a second clamp changed the palette", tc.name)
		}
		t.Logf("%s: fg %s %.2f->%s %.2f, accent %s %.2f->%s %.2f, fg on selection %.2f->%.2f", tc.name,
			tc.fg, ContrastRatio(tc.fg, tc.bg), got[slotForeground], ContrastRatio(got[slotForeground], tc.bg),
			tc.accent, ContrastRatio(tc.accent, tc.bg), got[slotAccent], ContrastRatio(got[slotAccent], tc.bg),
			ContrastRatio(tc.fg, baseSelection(tc.bg, tc.light)), ContrastRatio(got[slotForeground], selection))
	}
}

// A palette that already reads is returned byte for byte, selection included.
func TestClampAnchorsKeepsPassingColours(t *testing.T) {
	for _, light := range []bool{false, true} {
		p := [16]string{"#1a1b26", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
			"#414868", "#ff7a93", "#b9f27c", "#ff9e64", "#7da6ff", "#bb9af7", "#0db9d7", "#e6ebff"}
		if light {
			p[slotBackground], p[slotForeground], p[slotAccent] = "#f4f4f6", "#343b58", "#34548a"
		}
		got, selection := ClampAnchors(p, light)
		if got != p {
			t.Errorf("light=%t: a passing palette changed: %v", light, got)
		}
		if want := baseSelection(p[slotBackground], light); selection != want {
			t.Errorf("light=%t: selection %s, want the unclamped %s", light, selection, want)
		}
	}
}

// OKLab conversions must be inverses: the clamp moves lightness in OKLab and
// writes hex, so any drift there would show up as a hue shift.
func TestOKLabRoundTrip(t *testing.T) {
	for _, hex := range []string{"#0000ff", "#1030ff", "#7aa2f7", "#ff0000", "#00ff00", "#808080", "#ffffff", "#000000", "#e9dff0"} {
		if got := OKLabToHex(HexToOKLab(hex)); got != hex {
			t.Errorf("%s -> OKLab -> %s", hex, got)
		}
	}
}

// White and black are each the only in-gamut colour at their lightness, so
// fitChroma must shed all chroma there rather than clip a channel.
func TestFitChromaKeepsHue(t *testing.T) {
	for _, h := range []float64{0, 29, 110, 142, 264, 330} {
		for _, l := range []float64{0.2, 0.5, 0.8} {
			lch := fitChroma(OKLCH{L: l, C: 0.4, H: h})
			if !inGamut(lch) || lch.C <= 0 || lch.C >= 0.4 {
				t.Errorf("L=%.1f H=%.0f: fitted chroma %.3f", l, h, lch.C)
			}
		}
		if got := OKLCHToHex(fitChroma(OKLCH{L: 1, C: 0.2, H: h})); got != "#ffffff" {
			t.Errorf("L=1 H=%.0f: %s, want #ffffff", h, got)
		}
	}
}
