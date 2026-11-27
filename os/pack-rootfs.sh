#!/usr/bin/env bash
# Turns a `docker export` tarball into the two release images:
#   rootfs.tar   deterministic tarball (sorted, numeric owners, clamped mtimes)
#   rootfs.ext4  ext4 image with fixed UUID, hash seed and timestamps
#
# Runs as root inside the tools container (see Dockerfile.tools), called by
# build-rootfs.sh. Usage: pack-rootfs <export.tar> <out-dir> <size>
# Needs SOURCE_DATE_EPOCH; OUT_UID/OUT_GID set the owner of the output files.
set -euo pipefail

export_tar=$1
out_dir=$2
size=$3
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH must be set}"

# Fixed identifiers, so two builds of the same inputs give the same image.
readonly FS_UUID=6f1b2a3c-4d5e-4f60-8a7b-9c0d1e2f3a4b
readonly FS_HASH_SEED=0b7e1c2d-3a4f-4e5d-9c6b-7a8f9e0d1c2b

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

tar --extract --preserve-permissions --numeric-owner \
    --file "$export_tar" --directory "$staging"
# Docker artefacts that do not belong on a device.
rm -f "$staging/.dockerenv"

# Clamp every timestamp to SOURCE_DATE_EPOCH: mke2fs copies mtimes from the
# staging tree, tar is told to clamp as well.
find "$staging" -newermt "@$SOURCE_DATE_EPOCH" -print0 |
    xargs -0r touch --no-dereference --date="@$SOURCE_DATE_EPOCH"

tar --create --file "$out_dir/rootfs.tar" --directory "$staging" \
    --sort=name --numeric-owner --format=posix \
    --mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    .

rm -f "$out_dir/rootfs.ext4"
E2FSPROGS_FAKE_TIME=$SOURCE_DATE_EPOCH mkfs.ext4 -q \
    -d "$staging" -L rootfs -U "$FS_UUID" \
    -E "hash_seed=$FS_HASH_SEED,root_owner=0:0" \
    "$out_dir/rootfs.ext4" "$size"

chown "${OUT_UID:-0}:${OUT_GID:-0}" "$out_dir/rootfs.tar" "$out_dir/rootfs.ext4"
