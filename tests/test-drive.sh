# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Drive helpers: what a drive is called, which drives are offered, and the
# checks before a LUKS passphrase is changed.
sandbox drive

# One lsblk stub answering the handful of queries the helpers make.
stub lsblk 'case "$*" in
    "-no PKNAME /dev/nvme0n1p2") echo nvme0n1 ;;
    "-no PKNAME /dev/nvme0n1") ;;
    "-dno SIZE /dev/nvme0n1p2") echo "476.4G" ;;
    "-dno SIZE /dev/nvme0n1") echo "476.9G" ;;
    "-dno VENDOR /dev/nvme0n1") echo "SK hynix  " ;;
    "-dno MODEL /dev/nvme0n1") echo "PC711 NVMe SK hynix 512GB" ;;
    "-nro TYPE,NAME,FSTYPE,MOUNTPOINT /dev/nvme0n1")
        printf "disk nvme0n1\npart nvme0n1p1 vfat /boot\npart nvme0n1p2 crypto_LUKS\n" ;;
    "-prno NAME,FSTYPE")
        printf "/dev/nvme0n1\n/dev/nvme0n1p1 vfat\n/dev/nvme0n1p2 crypto_LUKS\n" ;;
    "-prno NAME,FSTYPE /dev/nvme0n1p1") printf "/dev/nvme0n1p1 vfat\n" ;;
    "-prno NAME,FSTYPE /dev/nvme0n1p2") printf "/dev/nvme0n1p2 crypto_LUKS\n" ;;
    "-dpno NAME,TYPE") printf "/dev/zram0 disk\n/dev/nvme0n1 disk\n" ;;
    *) ;;
esac'

capture haseen drive info /dev/nvme0n1
assert_status "a drive can be described" 0 "$STATUS"
assert_contains "the size is shown" "$OUTPUT" "/dev/nvme0n1 (476.9G)"
assert_contains "vendor and model are not repeated" "$OUTPUT" "- PC711 NVMe SK hynix 512GB"
assert_contains "the partitions are summarised" "$OUTPUT" "[vfat(/boot), crypto_LUKS]"

capture haseen drive info /dev/nvme0n1p2
assert_contains "a partition is described by its own size" "$OUTPUT" "/dev/nvme0n1p2 (476.4G)"
assert_contains "but names the disk it sits on" "$OUTPUT" "PC711 NVMe"

capture haseen drive select
assert_status "one real disk needs no picker" 0 "$STATUS"
assert_eq "zram is not a drive" /dev/nvme0n1 "$OUTPUT"

capture haseen drive select --luks
assert_eq "--luks lists the encrypted container" /dev/nvme0n1p2 "$OUTPUT"

capture haseen drive password /dev/nvme0n1p1 --yes
assert_status "a plain partition is refused" 1 "$STATUS"
assert_contains "the refusal says why" "$OUTPUT" "is not a LUKS container"

capture haseen drive password --dry-run
assert_dry_pure "drive password dry run" "$OUTPUT"
assert_contains "the dry run plans the key change on the only container" "$OUTPUT" "cryptsetup luksChangeKey --pbkdf argon2id --iter-time 2000 /dev/nvme0n1p2"
assert_not_contains "no passphrase is read in a dry run" "$OUTPUT" "New passphrase"
