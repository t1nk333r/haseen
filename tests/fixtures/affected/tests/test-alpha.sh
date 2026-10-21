# shellcheck shell=bash
# haseen:covers src/alpha/** docs/alpha.md
assert_eq "alpha runs" yes yes
# haseen:covers not/declared/**
