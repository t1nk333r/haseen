//! haseen-palette turns a wallpaper into a haseen theme palette: the
//! 16-colour ANSI set that colors.toml and every template under
//! share/haseen/themed/ are written in. A port of the Go generator
//! (core/internal/palette, itself adapted from omacom/aether, MIT) that
//! gives the same palette for the same image, bit for bit (plan 167).

// The ports keep Go's index loops, so each function reads line by line
// against the Go it came from.
#![allow(clippy::needless_range_loop)]

pub mod analysis;
pub mod anchors;
pub mod color;
pub mod generate;
pub mod gif;
pub mod gomath;
pub mod gosort;
pub mod image;
pub mod inflate;
pub mod jpeg;
pub mod json;
pub mod median_cut;
pub mod modes;
pub mod png;
pub mod sample;
pub mod sha256;
#[cfg(test)]
mod testutil;
pub mod vp8;
pub mod vp8l;
pub mod webp;
