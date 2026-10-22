# shellcheck shell=bash
# Capture: the uploader's credentials file.
# Sourced by bin/haseen-seed-user, which defines DEFAULTS, CONFIG and COMPOSE
# and calls seed_main once.
#
# haseen:seed $CONFIG/haseen/upload.toml|upload backends and their credentials
#
# The screenshot tool is Omasnap since plan 107 (owner, 2026-10-21), and it
# runs with no config file. Tensaku's config.toml and the overrides.css link to
# the theme render were seeded here until then; a machine that has them keeps
# them (they are the user's), and the link dangles once the theme render has
# no tensaku.css, which Tensaku 0.29.0 treats as "no overrides".
seed_main() {
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
