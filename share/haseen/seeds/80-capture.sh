# shellcheck shell=bash
# Capture: the Tensaku annotation editor and the uploader's credentials file.
# Sourced by bin/haseen-seed-user, which defines DEFAULTS, CONFIG and COMPOSE
# and calls seed_main once.
#
# haseen:seed $CONFIG/tensaku/config.toml|annotation editor settings
# haseen:seed $CONFIG/tensaku/overrides.css|link to the theme pipeline's editor colours
# haseen:seed $CONFIG/haseen/upload.toml|upload backends and their credentials
#
# Tensaku's config.toml is TOML and cannot include another file, so the
# colours cannot live there: Tensaku reads $XDG_CONFIG_HOME/tensaku/overrides.css
# as plain CSS instead (Tensaku 0.29.0 src/main.rs read_css_overrides). The link
# to the theme render is the same shape 10-btop.sh uses for btop's theme, and it
# makes `haseen theme set` restyle the editor with everything else. A render
# that is not there yet leaves a dangling link, which Tensaku treats exactly as
# "no overrides" (it checks Path::exists) and falls back to its built-in CSS.
seed_main() {
    seed_user_file "$DEFAULTS/tensaku/config.toml" "$CONFIG/tensaku/config.toml"

    local link="$CONFIG/tensaku/overrides.css"
    local target="$HASEEN_USER_STATE/current/theme/tensaku.css"
    # -L too: a dangling link is still the user's (no theme applied yet).
    if [[ ! -e $link && ! -L $link ]]; then
        run mkdir -p "$CONFIG/tensaku"
        run ln -snf "$target" "$link"
    fi

    # The uploader's credentials file. It is created empty of secrets and,
    # under umask 077, with mode 0600 from the start, so a token is never
    # written into a file that was world-readable first. Its directory is
    # made first, outside that umask, so it keeps the ordinary mode. A
    # dangling link is the user's: never written through or chmod'ed.
    local upload="$CONFIG/haseen/upload.toml"
    if [[ ! -e $upload && ! -L $upload ]]; then
        run mkdir -p "$CONFIG/haseen"
        (umask 077 && write_user_file "$upload") <<'EOF'
# haseen upload — backends and credentials. Keep this file mode 0600.
# `haseen upload --list` shows every backend; `haseen upload --help` explains
# the keys. Nothing here is set by default: with no configuration the uploader
# uses catbox.moe, which is anonymous and needs no account.

# default = "xbackbone"

# Your own XBackBone instance. Releases up to 3.8.2 take the token as a form
# field on /upload; the untagged next-gen takes it as an Authorization: Bearer
# header on /api/v1/upload. "auto" detects which one answers.
# [xbackbone]
# url = "https://share.example.com"
# token = ""
# api = "auto"

# An rclone remote (S3, Cloudflare R2, …). The credentials stay in rclone's
# own config; only the destination is named here.
# [rclone]
# remote = "r2:bucket/screenshots"
# link_expire = "1d"

# imgur closed new client registration and answers 429 to uploads from many
# networks. It works only with a client id you already have.
# [imgur]
# client_id = ""
EOF
        run chmod 600 "$upload"
    fi
}
