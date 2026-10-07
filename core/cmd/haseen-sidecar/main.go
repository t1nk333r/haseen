// Command haseen-sidecar is haseen's sampling daemon: the shell connects to a
// unix socket and subscribes to a stream instead of running timers and reading
// /proc from QML. It also turns the active border for a theme that asks for a
// wipe Hyprland cannot draw itself (stream `borderwipe`, plan 069).
//
// Started on demand by the shell, and it exits again once the last client has
// been gone for --idle-timeout, so a machine that never shows the widget never
// runs it.
package main

import (
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/t1nk333r/haseen/core/internal/borderwipe"
	"github.com/t1nk333r/haseen/core/internal/server"
)

var version = "dev"

func runtimeDir() string {
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return dir
	}
	return os.TempDir()
}

func defaultSocket() string { return filepath.Join(runtimeDir(), "haseen", "sidecar.sock") }

// defaultState is $HASEEN_USER_STATE, as share/haseen/lib/common.sh sets it.
func defaultState() string {
	if dir := os.Getenv("HASEEN_USER_STATE"); dir != "" {
		return dir
	}
	if dir := os.Getenv("XDG_STATE_HOME"); dir != "" {
		return filepath.Join(dir, "haseen")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "haseen")
}

func main() {
	socket := flag.String("socket", defaultSocket(), "unix socket to listen on")
	idle := flag.Duration("idle-timeout", 5*time.Minute, "exit this long after the last client leaves (0 = never)")
	root := flag.String("root", "", "filesystem root to sample (tests only)")
	state := flag.String("state", defaultState(), "haseen user state: the current theme and the context flag (border wipe)")
	showCaps := flag.Bool("capabilities", false, "print the capabilities this build has and exit")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}
	if *showCaps {
		fmt.Println(strings.Join(server.Capabilities(), " "))
		return
	}

	log.SetFlags(0)
	log.SetPrefix("haseen-sidecar: ")

	srv, err := server.Listen(server.Options{
		Socket:      *socket,
		Version:     version,
		IdleTimeout: *idle,
		Root:        *root,
		BorderWipe: borderwipe.Options{
			StateDir:   *state,
			RuntimeDir: runtimeDir(),
			Signature:  os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"),
		},
	})
	if err != nil {
		// Started on demand by a shell that wants a live socket, not this
		// process: if one is already there, say it is ready and step aside.
		if errors.Is(err, server.ErrAlreadyRunning) {
			fmt.Printf("ready %s\n", *socket)
			return
		}
		fmt.Printf("failed %s\n", err)
		log.Fatal(err)
	}

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-signals
		srv.Close()
	}()

	// One line on stdout, before any sample: whoever started this process waits
	// for it instead of polling for the socket to appear.
	fmt.Printf("ready %s\n", srv.Addr())
	os.Stdout.Sync()
	log.Printf("listening on %s (capabilities: %s)", srv.Addr(), strings.Join(server.Capabilities(), " "))
	if err := srv.Serve(); err != nil {
		log.Fatal(err)
	}
}
