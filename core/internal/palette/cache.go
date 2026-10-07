package palette

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// The cache answers one question: has this exact seed already been turned into
// this exact palette? The key is the image's **content** hash, not its path and
// mtime (aether `internal/extraction/cache.go` uses path+mtime), because a
// wallpaper that is copied, re-downloaded or touched is still the same seed and
// must not cost a regeneration.
//
// Entries are per user, under $XDG_CACHE_HOME/haseen/palette/<key>.json, and are
// written atomically: a half-written entry would be read back as a palette.

// cacheVersion changes whenever the generator would give a seed another
// palette; 2 is the corrected OKLab matrix.
const cacheVersion = 2

type cacheEntry struct {
	Version int        `json:"version"`
	Seed    string     `json:"seed"`
	Mode    string     `json:"mode"`
	Light   bool       `json:"light"`
	Palette [16]string `json:"palette"`
}

func cacheDir() string {
	if dir := os.Getenv("HASEEN_PALETTE_CACHE"); dir != "" {
		return dir
	}
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".cache")
	}
	return filepath.Join(base, "haseen", "palette")
}

// SeedHash is the content hash of the image: the same picture under a different
// name, or re-saved with a new mtime, is the same seed.
func SeedHash(imagePath string) (string, error) {
	f, err := os.Open(imagePath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(sum.Sum(nil)), nil
}

func cacheKey(seed, mode string, light bool) string {
	variant := "dark"
	if light {
		variant = "light"
	}
	return fmt.Sprintf("%s-%s-%s-v%d", seed[:min(len(seed), 32)], mode, variant, cacheVersion)
}

func cachePath(key string) string {
	dir := cacheDir()
	if dir == "" || key == "" {
		return ""
	}
	return filepath.Join(dir, key+".json")
}

func loadCached(key string) ([16]string, bool) {
	path := cachePath(key)
	if path == "" {
		return [16]string{}, false
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return [16]string{}, false
	}
	var entry cacheEntry
	if err := json.Unmarshal(raw, &entry); err != nil || entry.Version != cacheVersion {
		return [16]string{}, false
	}
	for _, c := range entry.Palette {
		if c == "" {
			return [16]string{}, false
		}
	}
	return entry.Palette, true
}

func saveCached(key string, entry cacheEntry) error {
	path := cachePath(key)
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	raw, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	tmp := path + ".new"
	if err := os.WriteFile(tmp, append(raw, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
