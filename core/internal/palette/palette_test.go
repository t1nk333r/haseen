package palette

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeImage paints a few flat bands, which is enough for the extractor to find
// dominant colours without depending on a binary fixture.
func writeImage(t *testing.T, path string, bands []color.RGBA) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 120, 120))
	height := 120 / len(bands)
	for y := range 120 {
		band := bands[min(y/height, len(bands)-1)]
		for x := range 120 {
			img.Set(x, y, band)
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

func sampleImage(t *testing.T, dir, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	writeImage(t, path, []color.RGBA{
		{R: 18, G: 22, B: 40, A: 255},
		{R: 190, G: 80, B: 70, A: 255},
		{R: 60, G: 140, B: 120, A: 255},
		{R: 230, G: 210, B: 150, A: 255},
	})
	return path
}

func TestGenerateIsCachedBySeed(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	image := sampleImage(t, dir, "wall.png")

	first, err := Generate(image, false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	if first.Cached {
		t.Fatal("the first run cannot be a cache hit")
	}
	for i, c := range first.Palette {
		if !strings.HasPrefix(c, "#") || len(c) != 7 {
			t.Fatalf("colour %d = %q, want #rrggbb", i, c)
		}
	}

	second, err := Generate(image, false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	if !second.Cached {
		t.Fatal("the same seed must come from the cache")
	}
	if second.Palette != first.Palette {
		t.Fatal("the cached palette differs from the generated one")
	}
}

// The cache key is the image's content, not its path or mtime: a wallpaper that
// is copied or re-saved is the same seed and must cost nothing.
func TestSeedFollowsContentNotPath(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	original := sampleImage(t, dir, "wall.png")

	first, err := Generate(original, false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(original)
	if err != nil {
		t.Fatal(err)
	}
	copied := filepath.Join(dir, "copy-with-another-name.png")
	if err := os.WriteFile(copied, raw, 0o644); err != nil {
		t.Fatal(err)
	}

	again, err := Generate(copied, false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	if !again.Cached {
		t.Fatal("a copy of the same image regenerated the palette")
	}
	if again.Seed != first.Seed {
		t.Fatalf("seed %s != %s", again.Seed, first.Seed)
	}
}

func TestDifferentImageAndModeAreDifferentSeeds(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	first := sampleImage(t, dir, "a.png")
	writeImage(t, filepath.Join(dir, "b.png"), []color.RGBA{
		{R: 240, G: 240, B: 240, A: 255},
		{R: 20, G: 60, B: 200, A: 255},
		{R: 10, G: 10, B: 10, A: 255},
		{R: 120, G: 200, B: 90, A: 255},
	})

	a, err := Generate(first, false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	b, err := Generate(filepath.Join(dir, "b.png"), false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	if b.Cached || a.Seed == b.Seed {
		t.Fatal("a different image must be a different seed")
	}
	if a.Palette == b.Palette {
		t.Fatal("two different images produced the same palette")
	}

	// The mode and light/dark are part of the key, not just the image.
	light, err := Generate(first, true, "normal")
	if err != nil {
		t.Fatal(err)
	}
	if light.Cached {
		t.Fatal("light mode reused the dark cache entry")
	}
	other, err := Generate(first, false, "monochromatic")
	if err != nil {
		t.Fatal(err)
	}
	if other.Cached {
		t.Fatal("another extraction mode reused the cache entry")
	}
}

func TestUnknownModeAndMissingImage(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	if _, err := Generate(sampleImage(t, dir, "wall.png"), false, "nonsense"); err == nil {
		t.Fatal("an unknown mode must be refused")
	}
	if _, err := Generate(filepath.Join(dir, "missing.png"), false, "normal"); err == nil {
		t.Fatal("a missing image must be an error")
	}
}

// A file that is not an image, and one whose header claims absurd dimensions,
// must both fail before any pixels are allocated.
func TestRefusesNonImages(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	path := filepath.Join(dir, "not-an-image.png")
	if err := os.WriteFile(path, []byte("certainly not a png"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Generate(path, false, "normal"); err == nil {
		t.Fatal("a non-image must be refused")
	}
}

// colors.toml is haseen's theme format: the 16 ANSI slots plus the named keys
// the templates read. theme-lib.sh derives everything else from these.
func TestColorsTOML(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HASEEN_PALETTE_CACHE", filepath.Join(dir, "cache"))
	result, err := Generate(sampleImage(t, dir, "wall.png"), false, "normal")
	if err != nil {
		t.Fatal(err)
	}
	out := result.ColorsTOML()
	for _, key := range []string{"mode = \"dark\"", "accent = ", "cursor = ", "selection = ",
		"background = ", "foreground = ", "color0 = ", "color15 = "} {
		if !strings.Contains(out, key) {
			t.Errorf("colors.toml is missing %q", key)
		}
	}
	if strings.Count(out, "\ncolor") != 16 {
		t.Errorf("want 16 colorN keys, got %d", strings.Count(out, "\ncolor"))
	}
	if !strings.Contains(result.ColorsTOML(), result.Palette[0]) {
		t.Error("the background colour is not in the output")
	}
}
