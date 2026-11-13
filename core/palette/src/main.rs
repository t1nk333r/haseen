//! haseen-palette turns a wallpaper into a haseen theme palette: the
//! 16-colour ANSI set that `colors.toml` and every template under
//! share/haseen/themed/ are written in.
//!
//! It is a pure function of the image plus the mode, cached on the image's
//! content hash, so re-running it for an unchanged wallpaper costs a hash
//! and nothing else. `haseen theme wallpaper` is the user-facing side. A
//! port of the Go command that was core/cmd/haseen-palette (plan 167): the
//! flags, the output and the exit codes are the same.

use haseen_palette::generate::generate;
use haseen_palette::modes::MODES;

const VERSION: &str = match option_env!("HASEEN_VERSION") {
    Some(v) => v,
    None => "dev",
};

/// name, value kind ("" for a bool), help; in Go's PrintDefaults order.
const FLAGS: [(&str, &str, &str); 4] = [
    (
        "json",
        "",
        "print the palette as JSON instead of colors.toml",
    ),
    ("light", "", "generate a light palette"),
    ("mode", "string", "extraction mode: "),
    ("version", "", "print the version and exit"),
];

fn usage() {
    let mut text =
        String::from("Usage: haseen-palette [--light] [--mode MODE] [--json] <image>\n\n");
    for (name, kind, help) in FLAGS {
        text.push_str(&format!("  -{name}"));
        if !kind.is_empty() {
            text.push(' ');
            text.push_str(kind);
        }
        text.push_str("\n    \t");
        text.push_str(help);
        if name == "mode" {
            text.push_str(&MODES.join(", "));
            text.push_str(" (default \"normal\")");
        }
        text.push('\n');
    }
    say(&text);
}

/// Go's bool flag values.
fn parse_bool(v: &str) -> Option<bool> {
    match v {
        "1" | "t" | "T" | "TRUE" | "true" | "True" => Some(true),
        "0" | "f" | "F" | "FALSE" | "false" | "False" => Some(false),
        _ => None,
    }
}

struct Flags {
    json: bool,
    light: bool,
    mode: String,
    version: bool,
    args: Vec<String>,
    /// Where `args` starts in the command line.
    first_arg: usize,
}

/// Go's flag package: `-name` or `--name`, `=value` or the next argument
/// for a string; stops at the first argument that is not a flag, or after
/// `--`. Errors exit 2 with Go's message and the usage; -h and -help exit 0.
fn parse_flags(args: &[String]) -> Flags {
    let mut f = Flags {
        json: false,
        light: false,
        mode: "normal".into(),
        version: false,
        args: Vec::new(),
        first_arg: 0,
    };
    let fail = |msg: String| -> ! {
        say(&format!("{msg}\n"));
        usage();
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
                i += 1;
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
                usage();
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
                "json" => f.json = value,
                "light" => f.light = value,
                _ => f.version = value,
            }
        } else {
            let value = match inline {
                Some(v) => v,
                None if i < args.len() => {
                    i += 1;
                    args[i - 1].clone()
                }
                None => fail(format!("flag needs an argument: -{name}")),
            };
            f.mode = value;
        }
    }
    f.first_arg = i.min(args.len());
    f.args = args[f.first_arg..].to_vec();
    f
}

/// BSD-3-Clause asks a binary to carry the notice of the Go code ported
/// into it: it is kept in the executable, and the release uploads it beside.
#[used]
static LICENSE_GO: &str = include_str!("../LICENSE-GO");

fn main() {
    // args_os: an image path need not be UTF-8, and std::env::args panics on
    // one that is not. Flags are read from a lossy copy; the image path is
    // passed on as it came (plan 167's review).
    let os_args: Vec<std::ffi::OsString> = std::env::args_os().collect();
    let args: Vec<String> = os_args
        .iter()
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let f = parse_flags(&args);
    if f.version {
        emit(&format!("{VERSION}\n"));
        return;
    }
    if f.args.len() != 1 {
        usage();
        std::process::exit(2);
    }
    let (result, err) = generate(&os_args[f.first_arg], f.light, &f.mode);
    if let Some(e) = err {
        say(&format!("haseen-palette: {e}\n"));
        std::process::exit(1);
    }
    let result = result.expect("a palette when there is no error");
    if f.json {
        emit(&format!("{}\n", result.json_line()));
        return;
    }
    emit(&result.colors_toml());
}

/// Standard error as Go wrote it: a failed write is ignored. eprintln!
/// would panic, and panic aborts with a core dump (plan 167's review).
fn say(text: &str) {
    use std::io::Write;
    let _ = std::io::stderr().lock().write_all(text.as_bytes());
}

/// Standard output as Go's fmt wrote it: an error is ignored (a full disk
/// exits 0), except a closed pipe, which killed the Go command with SIGPIPE
/// (141 to the shell). println! would panic, and panic aborts with a core
/// dump (plan 167's review).
fn emit(text: &str) {
    use std::io::Write;
    let mut out = std::io::stdout().lock();
    if let Err(e) = out.write_all(text.as_bytes()).and_then(|()| out.flush()) {
        if e.kind() == std::io::ErrorKind::BrokenPipe {
            std::process::exit(141);
        }
    }
}
