#!/usr/bin/env bash
# Hardening audit of the built root filesystem. Writes to <out-dir>:
#   lynis.txt, lynis.log, lynis-report.dat  Lynis 3.x run inside the rootfs
#   units-security.txt                      systemd-analyze security, offline
#   boot.txt                                boot check under systemd
#   summary.txt                             the numbers docs/hardening-review.md cites
#
# Usage: hardening-audit.sh <rootfs.tar> <out-dir>   (TOOLS_IMAGE must be set)
#
# Fails if the image does not boot to "running" with lab-api answering, or if
# a service of ours scores above MAX_EXPOSURE. Lynis findings never fail it:
# they are input for the review, not a gate.
#
# Lynis runs in a container, so tests that read /proc or the kernel see the
# build host, not the device: kernel, sysctl and firewall results are
# ignored (docs/hardening-review.md lists them).
#
# The boot check runs systemd as PID 1 in a container WITHOUT --privileged.
# A privileged container shares the host /dev; its systemd then takes over
# host input devices and TTYs and ends the desktop session. Only the
# container's own cgroup namespace is remounted read-write.
set -euo pipefail

readonly AUDIT_TAG=lab-rootfs:audit
readonly MAX_EXPOSURE=${MAX_EXPOSURE:-2.0}
readonly BOOT_TIMEOUT=60

rootfs=${1:?usage: hardening-audit.sh <rootfs.tar> <out-dir>}
out=${2:?usage: hardening-audit.sh <rootfs.tar> <out-dir>}
: "${TOOLS_IMAGE:?TOOLS_IMAGE must name the tools image; run 'make hardening-audit'}"
mkdir -p "$out"
out=$(cd "$out" && pwd)

docker import "$rootfs" "$AUDIT_TAG" >/dev/null

# Lynis is not part of the image: its files are copied in from the tools
# image for this run only.
run_lynis() {
    docker run --rm --network none "$TOOLS_IMAGE" \
        tar -C / -cf - usr/sbin/lynis usr/share/lynis etc/lynis \
    | docker run -i --rm --network none --volume "$out:/out" "$AUDIT_TAG" \
        bash -c 'tar -C / -xf - \
            && lynis audit system --quick --no-colors --logfile /out/lynis.log \
                --report-file /out/lynis-report.dat > /out/lynis.txt 2>&1; \
            rc=$?; chown -R "$1" /out; exit $rc' _ "$(id -u):$(id -g)"
}

# Scores every service unit the image adds under /etc/systemd/system
# (regular files only: masked units are symlinks to /dev/null).
score_units() {
    docker run --rm --network none "$AUDIT_TAG" bash -c '
        for unit in $(find /etc/systemd/system -maxdepth 1 -type f -name "*.service"); do
            echo "== ${unit##*/}"
            systemd-analyze security --offline=true --no-pager "$unit"
        done' > "$out/units-security.txt"
}

check_boot() {
    local container status
    container=$(docker run --detach --tty --env container=docker --network none \
        --cgroupns=private --cap-add SYS_ADMIN \
        --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
        --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
        --entrypoint /bin/bash "$AUDIT_TAG" \
        -c 'mount -o remount,rw /sys/fs/cgroup && exec /lib/systemd/systemd')
    # shellcheck disable=SC2064  # expand $container now
    trap "docker kill $container >/dev/null 2>&1; docker rm $container >/dev/null" RETURN
    # systemctl --wait needs the manager's bus, which appears a moment after
    # PID 1 starts.
    status=$(docker exec "$container" timeout "$BOOT_TIMEOUT" bash -c '
        until [[ -S /run/systemd/private ]]; do sleep 0.5; done
        systemctl is-system-running --wait' 2>&1 || true)
    {
        echo "system: $status"
        # Probe first: a crash-looping unit can look "active" between restarts,
        # so the state is read after the probe and must show no restarts.
        echo "http: $(docker exec "$container" python3 -c '
import time, urllib.request
for _ in range(30):
    try:
        print(urllib.request.urlopen("http://127.0.0.1:8080/").status)
        break
    except OSError as e:
        error = e
        time.sleep(0.5)
else:
    print(error)' 2>&1 | tail -1)"
        echo "lab-api: $(docker exec "$container" systemctl show lab-api \
            --property=ActiveState --value) restarts=$(docker exec "$container" \
            systemctl show lab-api --property=NRestarts --value)"
        echo "failed units:"
        docker exec "$container" systemctl --failed --no-legend --plain
        echo "enabled units:"
        docker exec "$container" systemctl list-unit-files --state=enabled --no-legend --plain
        echo "listening sockets:"
        docker exec "$container" bash -c 'cat /proc/net/tcp /proc/net/tcp6 | awk "\$4 == \"0A\""'
        echo "lab-api runtime score:"
        docker exec "$container" systemd-analyze security --no-pager lab-api.service | tail -1
    } > "$out/boot.txt"
}

run_lynis
score_units
check_boot

index=$(sed -n 's/^hardening_index=//p' "$out/lynis-report.dat")
# "→ Overall exposure level for x.service: 8.1 EXPOSED :-(" -> "x.service 8.1"
exposures=$(awk '/^== /{unit=$2}
    /Overall exposure level/ { match($0, /: [0-9.]+ /); print unit, substr($0, RSTART + 2, RLENGTH - 3) }' \
    "$out/units-security.txt")
{
    echo "lynis hardening index: $index"
    echo "unit exposure (offline, max $MAX_EXPOSURE):"
    awk '{ print "  " $0 }' <<< "$exposures"
    sed -n '1,3p' "$out/boot.txt"
} | tee "$out/summary.txt"

fail=0
grep -qx 'system: running' "$out/boot.txt" || { echo "boot: not running" >&2; fail=1; }
grep -qx 'lab-api: active restarts=0' "$out/boot.txt" || { echo "lab-api: not active or restarted" >&2; fail=1; }
grep -qx 'http: 200' "$out/boot.txt" || { echo "lab-api: no HTTP 200" >&2; fail=1; }
while read -r unit score; do
    if awk -v s="$score" -v m="$MAX_EXPOSURE" 'BEGIN { exit !(s > m) }'; then
        echo "$unit: exposure $score above $MAX_EXPOSURE" >&2
        fail=1
    fi
done <<< "$exposures"
exit "$fail"
