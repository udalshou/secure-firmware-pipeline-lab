# OS image hardening review

Repeatable review of the appliance root filesystem against secure-by-default
expectations: NIST SSDF PW.9 (configure software to have secure settings by
default) and EU CRA Annex I part 1 (secure by default configuration, limited
attack surface). `make hardening-audit` reproduces every number below.

## How the audit runs

`os/hardening-audit.sh` takes `out/rootfs.tar`, imports it as a container
image and writes evidence to `out/hardening/`:

| Step | Tool | Output |
|---|---|---|
| Static audit | Lynis 3.1.4 (`audit system --quick`), copied in from the tools image for the run only; it never ships | `lynis.txt`, `lynis.log`, `lynis-report.dat` |
| Unit sandbox score | `systemd-analyze security --offline=true` for every unit file in `/etc/systemd/system` | `units-security.txt` |
| Boot check | systemd as PID 1 in an unprivileged container: system state, `lab-api` state and restarts, HTTP probe, failed and enabled units, listening sockets | `boot.txt` |

The script fails if the system does not reach `running`, if `lab-api` is not
active with zero restarts and answering HTTP 200, or if any of our units
scores above 2.0. Lynis findings never fail it: they are input for this
review. CI runs the target in the `image` job as a non-blocking step and
uploads `out/hardening/` as the `hardening-audit` artifact.

The boot check must never use `docker run --privileged`. A privileged
container shares the host `/dev`, and systemd inside it takes over the
host's input devices and TTYs: on a desktop this ends the user's graphical
session. The script instead gives the container `CAP_SYS_ADMIN` and remounts
only its own cgroup namespace read-write.

### Limits of a container audit

- Kernel, sysctl, module and firewall tests in Lynis read `/proc` and
  `/sys` of the build host, not the device. Their results are ignored here,
  and the sysctl and modprobe settings below are verified by file presence
  only. A booted device (QEMU or hardware) is needed to confirm them.
- The container cannot create user namespaces, so `PrivateUsers=` is not
  used in `lab-api.service`: a unit with it could not be boot-tested.
- OpenSCAP (optional in the plan) was not run in this iteration.

## Results

| Measure | Before | After |
|---|---|---|
| Lynis hardening index (233 tests) | 58 | 62 |
| `lab-api.service` exposure (`systemd-analyze security`) | 8.1 EXPOSED | 1.2 OK |
| Enabled units | lab-api, getty@tty1, systemd-pstore, remote-fs.target, apt-daily, apt-daily-upgrade, dpkg-db-backup, fstrim | lab-api, systemd-timesyncd, systemd-pstore, fstrim |
| setuid/setgid files | 11 | 0 |
| Listening sockets | TCP 0.0.0.0:8080 | TCP 0.0.0.0:8080 |
| Boot to `running`, lab-api HTTP 200 | yes | yes |

The Lynis index moves little because most fixes act on things a container
run cannot see (unit sandboxing, kernel settings). The unit exposure score
and the boot check are the stronger evidence.

## Checklist

| Item | Status | Evidence |
|---|---|---|
| No default or shared passwords; root login disabled | Pass | every account in `/etc/shadow` is locked (`*` or `!`); root has no password |
| sshd: no password auth, no root, limited algorithms | N/A | sshd is not installed; the API on 8080 is the only listener |
| Only required packages and services | Pass (fixed) | 97 packages (Debian minbase + systemd, timesyncd, python3); apt timers, cron scripts, `remote-fs.target` and all gettys removed; enabled units in `boot.txt` |
| API runs unprivileged and sandboxed | Pass (fixed) | `DynamicUser=yes`, empty capability set, `ProtectSystem=strict`, `PrivateDevices`, `ProtectKernel*`, `RestrictAddressFamilies`, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute` and more; exposure 1.2 |
| sysctl: `kptr_restrict`, `fs.protected_*`, redirects off | Fixed, unverified at runtime | `/etc/sysctl.d/90-lab-hardening.conf` (KSPP values) |
| Unused kernel modules blocked | Fixed, unverified at runtime | `/etc/modprobe.d/lab-hardening.conf`: dccp, sctp, rds, tipc, usb-storage, firewire-core, thunderbolt |
| No setuid/setgid programs | Pass (fixed) | all bits stripped in `os/Dockerfile.rootfs`; nobody logs in, so nothing needs to elevate |
| File permissions on secrets; no keys in the image except the Mender public key | Pass | `PRIVATE KEY` search finds only strings inside libcrypto and sqv binaries; `/etc/mender` holds the public key and config |
| Default umask | Fixed | `UMASK 027` in `/etc/login.defs`; `UMask=0077` for lab-api |
| Logging | Pass (fixed) | journald, persistent, capped at 32 MiB (`/etc/systemd/journald.conf.d/lab.conf`) |
| Time sync | Pass (fixed) | `systemd-timesyncd` installed and enabled |
| Legal banner | Fixed | `/etc/issue`, `/etc/issue.net` |
| Secure boot / verified rootfs | Out of scope | see below |

## Lynis findings not fixed

| Finding | Decision |
|---|---|
| LOGG-2138 klogd not running, LOGG-2130 no syslog daemon | Accepted: journald reads the kernel log (`/dev/kmsg`) itself; a syslog daemon would add a process and duplicate storage |
| AUTH-9230, AUTH-9262, AUTH-9286 password hashing rounds, strength, ageing | N/A: no account has a password and no login path exists |
| DEB-0280, DEB-0810, DEB-0811, DEB-0831, PKGS-7370, PKGS-7394, PKGS-7420 apt helpers and auto-upgrades | N/A: packages never change on the device; the whole image is replaced by a signed Mender update, and `DEBIAN_SNAPSHOT` bumps bring the security fixes |
| DEB-0880 fail2ban | N/A: no authentication service is exposed |
| ACCT-9622, ACCT-9626, ACCT-9628 process accounting, sysstat, auditd | Deferred: auditd is worth it on a real device with a log shipping target; the lab has none |
| FINT-4350 file integrity tool, HRDN-7230 malware scanner | Superseded on a real device by a read-only, verified rootfs (dm-verity); not added to the lab image |
| FILE-6310 separate /home, /tmp, /var | Partly N/A: no /home users; on a device /tmp is a tmpfs and /var a data partition next to the Mender A/B rootfs |
| KRNL-5788 no /vmlinuz, BOOT-5180 runlevel | N/A: the rootfs ships without a kernel; the board support layer provides it |
| NAME-4028, NAME-4404 DNS domain, FQDN in /etc/hosts | N/A for the lab; set by provisioning on a real device |
| BOOT-5264 harden services | Done for lab-api; the other enabled units are systemd's own |
| TOOL-5002 automation tools, LYNIS release age | Informational |

## Out of scope: what a real device needs

- Verified boot chain: ROM -> signed U-Boot (FIT image signatures) -> signed
  kernel and device tree, keys in OTP or a TPM.
- Read-only rootfs with dm-verity; the root hash is signed and checked by
  the kernel command line in the signed FIT image. Mender A/B partitions keep
  updates atomic.
- Kernel built with the KSPP options and lockdown mode, so the sysctl and
  module settings above cannot be undone by root.
- A debug console only in development builds, and a firewall (nftables)
  that allows 8080 only from the management network.
