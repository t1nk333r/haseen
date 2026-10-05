package palette

import (
	"fmt"
	"image"
	"io"

	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"

	_ "golang.org/x/image/webp"
)

// A wallpaper is read into memory and scaled before sampling, so a hostile or
// simply enormous image must not be decoded first.
const (
	maxImageDimension = 20000
	maxImagePixels    = 200_000_000
)

// decodeImage reads an image after checking its header, the way aether's
// wallpaper.DecodeImage does: the header tells us the dimensions before any
// pixels are allocated.
func decodeImage(r io.ReadSeeker) (image.Image, error) {
	config, _, err := image.DecodeConfig(r)
	if err != nil {
		return nil, fmt.Errorf("decode image header: %w", err)
	}
	if config.Width <= 0 || config.Height <= 0 ||
		config.Width > maxImageDimension || config.Height > maxImageDimension ||
		int64(config.Width)*int64(config.Height) > maxImagePixels {
		return nil, fmt.Errorf("unsafe image dimensions %dx%d", config.Width, config.Height)
	}
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("rewind image: %w", err)
	}
	img, _, err := image.Decode(r)
	return img, err
}
