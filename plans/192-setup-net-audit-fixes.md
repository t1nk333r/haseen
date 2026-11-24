# Plan 192: seven setup, network and drive defects from the 2026-11-24 audit

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. Each fix is local to one command or helper: the env file
  writer, the KDE Connect firewall check, the Wi-Fi QR query, the drive
  passphrase options, the favicon fallback's URL and Cairn's install
  decision. No default, layer or owner file changes.
- **Depends on**: 073 (Helium and Cairn), 093 (Omarchy's commands), 166 (the
  Wi-Fi QR card), the mobile layer's firewall step
- **Category**: setup, network, drive
- **Planned at**: 2026-11-24, from the owner ("fix them", after the
  35-auditor audit)
- **State**: DONE 2026-11-24 (`tests/test-menu.sh` 313/313,
  `tests/test-mobile.sh` 195/195, `tests/test-network-panel.sh` 95/95,
  `tests/test-drive.sh` 17/17, `tests/test-webapp.sh` 58/58,
  `tests/test-helium-cairn.sh` 69/69; every new check fails with the old
  code)

## Problem

The 2026-11-24 audit (35 auditors, each finding re-traced by a skeptic) gave
this group seven confirmed findings. Each was re-checked on main at
`9a9e82ab` before it was fixed; all seven still applied. None of them is a
duplicate of another, so there is one section per finding, in the audit's
order.

## 1. `haseen setup default` wiped the env file when it re-set its only variable

**Evidence.** `write_env` (`bin/haseen-setup-default:244-250` before this
plan) built the new file as
`{ echo header; [[ -r $ENV_FILE ]] && grep -v ... "$ENV_FILE"; printf export ...; } | write_user_file`.
The script runs under `set -Eeuo pipefail` (line 5). When the variable was
the file's only line, `grep -v` printed nothing and exited 1. It was the last
command of its `&&` list, so errexit ended the brace group before the
`printf`. `write_user_file` had already truncated the file and written the
header, and pipefail made the script exit 1 before
`systemctl --user set-environment` and the terminals list. Every later run
then failed the same way, since a header-only file gives grep no output.
With the old code, the new test below gives:

```
FAIL re-set the only variable
     exit: expected 0, got 1
FAIL re-set: the new value, once
     expected: export TERMINAL=foot
     actual:
```

**Fix.** grep's no-match status no longer ends the group:
`if [[ -r $ENV_FILE ]]; then grep -v ... || true; fi`
(`bin/haseen-setup-default:249-251`).

**Test.** `tests/test-menu.sh` sets `terminal kitty` while it is the file's
only variable, then `terminal foot` (exit 0, exactly
`export TERMINAL=foot`), then `kitty` again.

**Rejected.** Writing the file with `sed -i` in place: haseen writes user
files only through `write_user_file`, which a dry run turns into a plan.

## 2. The KDE Connect ufw rules were never detected

**Evidence.** `mobile_ufw_rule_present` grepped
`-p PROTO .*--dport 1714:1764 -j ACCEPT`. ufw writes a port range as
multiport: `/usr/lib/python3.14/site-packages/ufw/common.py` (ufw 0.36.2)
sets `self.multi = True` for a range (line 211), emits `-m multiport` and
`--dports` (lines 130-136) and writes `--dport` only when not multi
(line 142). So on a real host `haseen layer status mobile` warned "ufw
blocks 1714:1764/tcp", `layer apply mobile` ran `ufw allow` again
(`share/haseen/layers/mobile/layer.sh:86-90`) and `layer remove mobile`
skipped both `ufw delete allow` calls (`layer.sh:204`), leaving 51 TCP and
UDP ports open. The fixture `tests/fixtures/mobile-applied/etc/ufw/user.rules`
had the single-port form, which ufw never writes for a range, so the tests
passed.

**Fix.** The pattern accepts `--dports?`
(`share/haseen/layers/mobile/mobile.sh:204`), so ufw's multiport line and a
hand-written `--dport` line both count. The fixture now holds the lines ufw
writes: `-A ufw-user-input -p tcp -m multiport --dports 1714:1764 -j ACCEPT`.

**Test.** With the real-format fixture, the old pattern fails seven checks in
`tests/test-mobile.sh` (re-apply re-opens nothing, status healthy, both
rules, both removes). A new case rewrites the fixture to `--dport` and still
gets "ok: ufw allows 1714:1764/udp".

**Rejected.** Matching the `### tuple ### allow tcp 1714:1764` comment: it
is ufw's bookkeeping and says nothing about the generated rule; the rule line
is what the firewall loads.

## 3. The Wi-Fi QR card failed on open networks

**Evidence.** `bin/haseen-network-qr:69-76` read five positional lines from
one `nmcli --get-values` call mixing `802-11-wireless` and
`802-11-wireless-security` fields. An open profile has no
`802-11-wireless-security` setting, and nmcli (1.58.1 here) prints nothing
for the fields of a setting the profile lacks (`nmc_connection_profile_details`
calls `setting_details` only when the setting exists; terse mode prints no
separator). The `hidden` value ("no") landed in `key_management`, and the
script failed with "Could not read the Wi-Fi password" instead of drawing a
nopass code. The test stub always printed five lines.

**Fix.** One query per setting (`bin/haseen-network-qr:69-82`): ssid and
hidden from `802-11-wireless`, then key-mgmt, psk and wep-key0 from
`802-11-wireless-security`. A missing security setting now reads as empty
fields, which is an open network.

**Test.** `tests/test-network-panel.sh`'s nmcli stub answers the two queries,
and `OPEN=1` prints nothing for the security one, as nmcli does. An open
profile shares `WIFI:T:nopass;S:...;;`, a hidden one keeps `H:true;`, and
`--password` says "This network has no password".

**Rejected.** `-t -f` with `name:value` parsing: correct too, but it changes
how every value is read for a case the per-setting split already covers, and
leaves the stub further from the code's real calls.

## 4. OWE (Enhanced Open) networks were treated as password-protected

**Evidence.** `bin/haseen-network-qr:82` treated every key-mgmt other than
empty or `none` as WPA and required a PSK. `man nm-settings-nmcli` lists
`owe` (Opportunistic Wireless Encryption) as a key-mgmt with no password, so
an OWE network failed with "Could not read the Wi-Fi password", and
`--password` never reached "This network has no password". Omarchy's
password command (`share/haseen/omarchy/bin/omarchy-network-password:39`)
had the same gap.

**Fix.** `owe` joins as open: `bin/haseen-network-qr:89` and
`omarchy-network-password:39` treat it like `none`, so the code is
`T:nopass` and the password commands say the network has none.

**Test.** `tests/test-network-panel.sh`: `KM=owe` draws a nopass code and
`--password` says there is no password; `omarchy-network-password` gives the
same answer for OWE and an open profile, and still prints a WPA password
(this test now covers that file).

**Rejected.** Refusing OWE with its own message: phones join an OWE network
from a nopass code, so refusing would hide a code that works.

## 5. `haseen drive password` passed argon2id to LUKS1 containers

**Evidence.** `bin/haseen-drive-password:61` always ran
`cryptsetup luksChangeKey --pbkdf argon2id`. LUKS1 supports only PBKDF2
(`man cryptsetup-luksChangeKey`: "For LUKS1, the PBKDF type and hash
algorithm are always the same for all keyslots"), so on a LUKS1 container
the user typed three passphrases and cryptsetup refused. The sibling
`bin/haseen-password:107-108` already adds argon2id only for LUKS2, and
`omarchy-drive-password` is shimmed to this command
(`share/haseen/omarchy/commands.tsv:109`).

**Fix.** The type check reads `lsblk -prno NAME,FSTYPE,FSVER` once
(`bin/haseen-drive-password:40-48`); `--pbkdf argon2id` is added only when
FSVER is 2. LUKS1, or an unknown version, gets cryptsetup's own default for
the container. The options reach `cryptsetup` as arguments of the `bash -c`
(line 67), never inside the command string, and the dry run prints the same
options.

**Test.** `tests/test-drive.sh`: the lsblk stub answers FSVER
(`LUKS_VERSION`, 2 by default); a LUKS1 dry run plans
`cryptsetup luksChangeKey --iter-time 2000 /dev/nvme0n1p2` with no argon2id.

**Rejected.** `cryptsetup luksDump` for the version: it needs root on most
devices, and the type check already asks lsblk.

## 6. The favicon fallback sent the full app URL to Google

**Evidence.** `bin/haseen-webapp-install:91` requested
`https://www.google.com/s2/favicons?domain=${site_url}&sz=256` with the whole
app URL, so the path, the query (tokens included), any user info and the
port went to a third party unencoded, and a `&` split the parameter. The same
line is in `share/haseen/omarchy/bin/omarchy-webapp-install:124`. With the
old code the new test shows
`domain=https://me:pw@intranet.example.com:8443/board?team=x&token=abc&sz=256`.

**Fix.** `favicon_host` (`bin/haseen-webapp-install:77-92`, and the same
function in `omarchy-webapp-install:112-127`) keeps only the host: no scheme,
path, query, fragment, user info or port; a bracketed IPv6 literal stays
whole, its brackets and colons percent-encoded. A host with a non-ASCII
(IDN) character makes it fail, and the Google fallback is skipped: Google
looks hosts up in punycode, so percent-encoded UTF-8 would only miss, and
haseen has no punycode encoder it can count on (see Review).

**Test.** `tests/test-webapp.sh` stubs curl to log each URL and answer only
Google, as for a site behind a login: both installers send
`domain=intranet.example.com&sz=256` and never `token`. For
`https://münchen.example/rathaus` neither installer asks Google, and
`haseen webapp install` fails with "could not fetch an icon".

**Rejected.** Dropping the Google fallback and asking for an icon: the
fallback is what makes `haseen webapp install NAME URL` work for most sites
without one, and with the host alone it sends what a DNS lookup would.
Sharing the helper through `lib/common.sh`: that file is global, and two
copies of a 15-line function cost less than a whole-suite selection.

## 7. `haseen setup cairn` could not repair a later version whose .crx was gone

**Evidence.** `cairn_install` (`share/haseen/lib/cairn.sh:208-216` before
this plan) returned early whenever the external-extensions JSON named a
version newer than the pin, without checking that its `.crx` still existed.
`cairn_status` reports that very state as
"missing: .../cairn-X.crx is gone before Helium installed it (haseen setup
cairn)", and `haseen setup cairn` then printed "Cairn X stays" and did
nothing; the shell layer's `cairn_install || warn` never repaired it either.

**Fix.** A later version stays only while its `.crx` is on disk or Helium has
installed it (`$HELIUM_USER_DATA/*/Extensions/<id>/<version>_*`;
`cairn.sh:206-223`). Otherwise `cairn_install` says why and deploys the pin,
which Helium never had a newer copy of; `haseen setup cairn update` still
fetches the latest. `bin/haseen-setup-cairn --help` says so.

**Test.** `tests/test-helium-cairn.sh`: with 9.9.0 deployed past the 9.8.7
pin, Helium holding `9.9.0_0` keeps it; with the `.crx` and Helium's copy
gone, status names the missing file, `haseen setup cairn` repairs it (Helium
pointed at 9.8.7 again) and status reads "handed to Helium".

**Rejected.** Refetching the newer version: its SHA-256 came from the GitHub
API at update time and is not stored, and an unchecked download is what
`cairn_update` refuses. Changing the status hint to `haseen setup cairn
update`: it would leave the default command, which the shell layer runs, a
no-op in a broken state.

## Review

The independent Sonnet review of the first head approved it with two nits.

- `favicon_host` percent-encoded a non-ASCII host as raw UTF-8 bytes
  (`m%C3%BCnchen.de`), which Google's favicon service, keyed by punycode,
  would likely miss. Taken: an IDN host now skips the Google fallback in both
  installers, and `tests/test-webapp.sh` checks that no Google request goes
  out for `münchen.example`. Converting to punycode was rejected: `idn2` is
  not a dependency of any layer, and a hand-written encoder for one
  last-resort icon lookup is more code than the case deserves. Such a site
  still installs from its own `apple-touch-icon` or with an icon passed on
  the command line.
- One check in `tests/test-agent-accounts.sh` ("and says where a plain CLI
  follows it") fails in the affected selection. It fails the same way on the
  base commit, outside this plan's files, so it is left to a separate fix.
