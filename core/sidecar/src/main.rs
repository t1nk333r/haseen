//! haseen-sidecar is haseen's sampling daemon: the shell connects to a unix
//! socket and subscribes to a stream instead of running timers and reading
//! /proc from QML. It also turns the active border for a theme that asks for a
//! wipe Hyprland cannot draw itself (stream `borderwipe`, plan 069).
//!
//! Started on demand by the shell, and it exits again once the last client has
//! been gone for -idle-timeout, so a machine that never shows the widget never
//! runs it. A port of the Go daemon that was core/cmd/haseen-sidecar (plan 167):
//! the flags, the lines on stdout and the wire format are the same.

use haseen_sidecar::borderwipe;
use haseen_sidecar::gocompat::{clean, format_duration, parse_duration};
use haseen_sidecar::proto::CAPABILITIES;
use haseen_sidecar::server::{self, log, ListenError};
use std::ffi::CString;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicPtr, Ordering};

const VERSION: &str = match option_env!("HASEEN_VERSION") {
    Some(v) => v,
    None => "dev",
};

fn runtime_dir() -> PathBuf {
    match std::env::var_os("XDG_RUNTIME_DIR") {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => std::env::temp_dir(),
    }
}

/// Go's filepath.Join of these parts: cleaned, empty parts skipped.
fn go_join(parts: &[&str]) -> String {
    let joined = parts
        .iter()
        .filter(|p| !p.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join("/");
    if joined.is_empty() {
        return String::new();
    }
    String::from_utf8_lossy(&clean(joined.as_bytes())).into_owned()
}

fn default_socket() -> String {
    go_join(&[
        &runtime_dir().display().to_string(),
        "haseen",
        "sidecar.sock",
    ])
}

/// $HASEEN_USER_STATE, as share/haseen/lib/common.sh sets it.
fn default_state() -> String {
    let var = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());
    if let Some(dir) = var("HASEEN_USER_STATE") {
        return dir;
    }
    if let Some(dir) = var("XDG_STATE_HOME") {
        return go_join(&[&dir, "haseen"]);
    }
    // Without HOME, Go's os.UserHomeDir is "" and the path is relative.
    go_join(&[
        &var("HOME").unwrap_or_default(),
        ".local",
        "state",
        "haseen",
    ])
}

struct Flags {
    socket: String,
    idle_ns: i64,
    root: String,
    state: String,
    capabilities: bool,
    version: bool,
}

/// One flag: name, value kind ("" for a bool) and help, in Go's
/// PrintDefaults order (sorted by name).
const FLAGS: [(&str, &str, &str); 6] = [
    (
        "capabilities",
        "",
        "print the capabilities this build has and exit",
    ),
    (
        "idle-timeout",
        "duration",
        "exit this long after the last client leaves (0 = never)",
    ),
    ("root", "string", "filesystem root to sample (tests only)"),
    ("socket", "string", "unix socket to listen on"),
    (
        "state",
        "string",
        "haseen user state: the current theme and the context flag (border wipe)",
    ),
    ("version", "", "print the version and exit"),
];

fn usage(argv0: &str, defaults: &Flags) {
    let mut text = format!("Usage of {argv0}:\n");
    for (name, kind, help) in FLAGS {
        text.push_str(&format!("  -{name}"));
        if !kind.is_empty() {
            text.push(' ');
            text.push_str(kind);
        }
        text.push_str("\n    \t");
        text.push_str(help);
        let default = match name {
            "idle-timeout" => Some(format_duration(defaults.idle_ns)),
            "socket" => Some(format!("{:?}", defaults.socket)),
            "state" => Some(format!("{:?}", defaults.state)),
            _ => None,
        };
        if let Some(d) = default.filter(|d| d != "\"\"") {
            text.push_str(&format!(" (default {d})"));
        }
        text.push('\n');
    }
    eprint!("{text}");
}

/// Go's bool flag values.
fn parse_bool(v: &str) -> Option<bool> {
    match v {
        "1" | "t" | "T" | "TRUE" | "true" | "True" => Some(true),
        "0" | "f" | "F" | "FALSE" | "false" | "False" => Some(false),
        _ => None,
    }
}

/// Parses the arguments as Go's flag package does: `-name` or `--name`, with
/// `=value` or the next argument; stops at the first argument that is not a
/// flag, or after `--`. Errors exit 2 with Go's message and the usage; -h and
/// -help exit 0.
fn parse_flags(args: &[String]) -> Flags {
    let argv0 = args.first().map(String::as_str).unwrap_or("haseen-sidecar");
    let mut f = Flags {
        socket: default_socket(),
        idle_ns: 300_000_000_000,
        root: String::new(),
        state: default_state(),
        capabilities: false,
        version: false,
    };
    let defaults = Flags {
        socket: f.socket.clone(),
        idle_ns: f.idle_ns,
        root: String::new(),
        state: f.state.clone(),
        capabilities: false,
        version: false,
    };
    let fail = |msg: String| -> ! {
        eprintln!("{msg}");
        usage(argv0, &defaults);
        std::process::exit(2);
    };
    let mut i = 1;
    while i < args.len() {
        let arg = &args[i];
        if arg.len() < 2 || !arg.starts_with('-') {
            break;
        }
        let mut name = &arg[1..];
        if let Some(rest) = name.strip_prefix('-') {
            if rest.is_empty() {
                break; // "--" ends the flags
            }
            name = rest;
        }
        if name.is_empty() || name.starts_with('-') || name.starts_with('=') {
            fail(format!("bad flag syntax: {arg}"));
        }
        i += 1;
        let (name, inline) = match name.split_once('=') {
            Some((n, v)) => (n, Some(v.to_string())),
            None => (name, None),
        };
        let Some((_, kind, _)) = FLAGS.iter().find(|(n, _, _)| *n == name) else {
            if name == "help" || name == "h" {
                usage(argv0, &defaults);
                std::process::exit(0);
            }
            fail(format!("flag provided but not defined: -{name}"));
        };
        if kind.is_empty() {
            let value = match &inline {
                None => true,
                Some(v) => parse_bool(v).unwrap_or_else(|| {
                    fail(format!(
                        "invalid boolean value {v:?} for -{name}: parse error"
                    ))
                }),
            };
            match name {
                "capabilities" => f.capabilities = value,
                _ => f.version = value,
            }
            continue;
        }
        let value = match inline {
            Some(v) => v,
            None => {
                let Some(v) = args.get(i) else {
                    fail(format!("flag needs an argument: -{name}"));
                };
                i += 1;
                v.clone()
            }
        };
        match name {
            "idle-timeout" => {
                f.idle_ns = parse_duration(&value).unwrap_or_else(|| {
                    fail(format!(
                        "invalid value {value:?} for flag -{name}: parse error"
                    ))
                });
            }
            "root" => f.root = value,
            "socket" => f.socket = value,
            _ => f.state = value,
        }
    }
    f
}

/// The socket the signal handler removes; set once, before the handler.
static SOCKET: AtomicPtr<libc::c_char> = AtomicPtr::new(std::ptr::null_mut());

extern "C" fn on_signal(_: libc::c_int) {
    let p = SOCKET.load(Ordering::Relaxed);
    // SAFETY: unlink and _exit are async-signal-safe, and p is a leaked,
    // NUL-terminated string that is never freed.
    unsafe {
        if !p.is_null() {
            libc::unlink(p);
        }
        libc::_exit(0);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let flags = parse_flags(&args);
    if flags.version {
        println!("{VERSION}");
        return;
    }
    if flags.capabilities {
        println!("{}", CAPABILITIES.join(" "));
        return;
    }

    let socket = flags.socket.clone();
    let listened = server::listen(server::Options {
        socket: socket.clone(),
        version: VERSION.to_string(),
        idle_timeout_ns: flags.idle_ns,
        root: flags.root.into_bytes(),
        border_wipe: borderwipe::Options {
            state_dir: PathBuf::from(flags.state),
            runtime_dir: runtime_dir(),
            signature: std::env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default(),
            ..Default::default()
        },
    });
    let srv = match listened {
        Ok(srv) => srv,
        // Started on demand by a shell that wants a live socket, not this
        // process: if one is already there, say it is ready and step aside.
        Err(ListenError::AlreadyRunning) => {
            println!("ready {socket}");
            return;
        }
        Err(ListenError::Failed(e)) => {
            println!("failed {e}");
            let _ = std::io::stdout().flush();
            log(&e);
            std::process::exit(1);
        }
    };

    if let Ok(c) = CString::new(socket.clone()) {
        SOCKET.store(c.into_raw(), Ordering::Relaxed);
    }
    // SAFETY: the handler only calls async-signal-safe functions.
    unsafe {
        libc::signal(libc::SIGINT, on_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGTERM, on_signal as *const () as libc::sighandler_t);
    }

    // One line on stdout, before any sample: whoever started this process
    // waits for it instead of polling for the socket to appear.
    println!("ready {socket}");
    let _ = std::io::stdout().flush();
    log(&format!(
        "listening on {socket} (capabilities: {})",
        CAPABILITIES.join(" ")
    ));
    let err = srv.serve();
    log(&err.to_string());
    std::process::exit(1);
}
