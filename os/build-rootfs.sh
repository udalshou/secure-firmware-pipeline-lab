#!/usr/bin/env bash
# Builds the appliance root filesystem without root on the host:
#   1. docker build os/Dockerfile.rootfs  (Debian + systemd + API + UI)
#   2. docker export of that image        -> out/rootfs-export.tar
#   3. pack-rootfs in the tools container -> out/rootfs.tar, out/rootfs.ext4
#
# Expects ui/dist and the tools image (os/Dockerfile.tools, tag in
# TOOLS_IMAGE) to be built already; Makefile target `rootfs` does both.
# SOURCE_DATE_EPOCH defaults to the last commit time; ROOTFS_SIZE to 256M.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/out"
size=${ROOTFS_SIZE:-256M}
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$repo" log -1 --format=%ct)}
export SOURCE_DATE_EPOCH

readonly ROOTFS_TAG=lab-rootfs:build
: "${TOOLS_IMAGE:?TOOLS_IMAGE must name the tools image; run 'make rootfs'}"

if [[ ! -f "$repo/ui/dist/index.html" ]]; then
    echo "ui/dist is missing; run 'make ui-build' first" >&2
    exit 1
fi
mkdir -p "$out"

docker build --file "$repo/os/Dockerfile.rootfs" --tag "$ROOTFS_TAG" \
    --build-arg SOURCE_DATE_EPOCH "$repo"

container=$(docker create "$ROOTFS_TAG" /bin/true)
trap 'docker rm --force "$container" >/dev/null' EXIT
docker export --output "$out/rootfs-export.tar" "$container"

docker run --rm --network none \
    --env SOURCE_DATE_EPOCH --env OUT_UID="$(id -u)" --env OUT_GID="$(id -g)" \
    --volume "$out:/out" "$TOOLS_IMAGE" \
    pack-rootfs /out/rootfs-export.tar /out "$size"
rm -f "$out/rootfs-export.tar"

sha256sum "$out/rootfs.tar" "$out/rootfs.ext4"
