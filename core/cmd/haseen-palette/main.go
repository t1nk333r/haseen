// Command haseen-palette turns a wallpaper into a haseen theme palette: the
// 16-colour ANSI set that `colors.toml` and every template under
// share/haseen/themed/ are written in.
//
// It is a pure function of the image plus the mode, cached on the image's
// content hash, so re-running it for an unchanged wallpaper costs a hash and
// nothing else. `haseen theme wallpaper` is the user-facing side.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/t1nk333r/haseen/core/internal/palette"
)

var version = "dev"

func main() {
	light := flag.Bool("light", false, "generate a light palette")
	mode := flag.String("mode", "normal", "extraction mode: "+strings.Join(palette.Modes, ", "))
	asJSON := flag.Bool("json", false, "print the palette as JSON instead of colors.toml")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: haseen-palette [--light] [--mode MODE] [--json] <image>\n\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}
	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(2)
	}
	image := flag.Arg(0)

	result, err := palette.Generate(image, *light, *mode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "haseen-palette: %v\n", err)
		os.Exit(1)
	}

	if *asJSON {
		// `cached` is the answer to "did this wallpaper cost any work?", which
		// is what the caller (and the test) checks.
		fmt.Printf("{\"seed\":%q,\"mode\":%q,\"light\":%t,\"cached\":%t,\"palette\":[",
			result.Seed, result.Mode, result.Light, result.Cached)
		for i, c := range result.Palette {
			if i > 0 {
				fmt.Print(",")
			}
			fmt.Printf("%q", c)
		}
		fmt.Println("]}")
		return
	}
	fmt.Print(result.ColorsTOML())
}
