#!/usr/bin/env python3
"""Offline checks of the root image's contents, read from the container export
(out/rootfs/rootfs.tar) the image is made from. Reads only.

    scripts/verify-rootfs.py [rootfs.tar]

It looks for mistakes that were once made: files owned by the build user
(uid 1000, "alarm"), system directories writable by group or world, a
published default password that survived, private SSH host keys baked into
the image, a stale boot marker, a missing authorized_keys, linux-firmware's
generic ath10k board data (it resets the tablet), the Wi-Fi unit not enabled.
"""
import sys
import tarfile

SYSTEM = ("etc", "usr", "boot", "root", "opt")
HOME_OK = ("home/alarm",)
# With this file on the disk ath10k matches the chip's board id (ff) with a
# generic entry, and the WLAN firmware then resets the whole SoC.
FORBIDDEN = ("usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin",)
WANTS = "etc/systemd/system/multi-user.target.wants/"
# the units the bring-up needs at boot, and the one that must stay off
ENABLED = ("gts4lv-firmware.service", "gts4lv-modem.service", "gts4lv-boot-ok.service",
           "gts4lv-bluetooth.service", "gts4lv-sensors.service",
           "gts4lv-cpu-stability.service")
NOT_ENABLED = ("qrtr-ns.service", "gts4lv-debug-console.service")
SSH_CONFIG = "etc/ssh/sshd_config.d/10-gts4lv.conf"
REQUIRED = (
    "usr/bin/hexagonrpcd",
    "usr/local/sbin/gts4lv-cpu-stability",
    "usr/local/sbin/gts4lv-display",
    "usr/local/sbin/gts4lv-sensors",
    "usr/lib/gts4lv/sensors/sns_reg.conf",
    "usr/lib/gts4lv/hypr/tablet.lua",
    "usr/lib/gts4lv/autorotate.py",
    "usr/lib/gts4lv/finalize-mobile-user",
    "usr/lib/systemd/user/omamobile-autorotate.service",
    "etc/systemd/system/gts4lv-sensors-prepare.service",
    "etc/systemd/system/gts4lv-sensors-root.service",
    "etc/systemd/system/gts4lv-sensors.service",
    "etc/systemd/system/gts4lv-cpu-stability.service",
    "etc/systemd/system/gts4lv-display.service",
    "etc/systemd/system/sddm.service.d/10-gts4lv-display.conf",
    "etc/systemd/sleep.conf.d/90-gts4lv-disable-suspend.conf",
    "etc/systemd/user/omamobile-setup-user.service.d/10-gts4lv.conf",
    SSH_CONFIG,
    "etc/udev/rules.d/81-gts4lv-sensors.rules",
)
EXECUTABLES = (
    "usr/local/sbin/gts4lv-cpu-stability",
    "usr/local/sbin/gts4lv-display",
    "usr/local/sbin/gts4lv-sensors",
    "usr/lib/gts4lv/finalize-mobile-user",
)


def check(path):
    problems = []
    seen = {"root_ssh": False, "authorized": False}
    ssh_config = ""
    required = set()
    wants = set()
    with tarfile.open(path, "r|*") as tar:
        for member in tar:
            name = member.name.lstrip("./")
            if member.uid == 1000 or member.gid == 1000:
                if not name.startswith(HOME_OK):
                    problems.append(f"owned by uid/gid 1000: /{name}")
            top = name.split("/", 1)[0]
            if top in SYSTEM and member.isdir() and member.mode & 0o022:
                problems.append(f"directory writable by group or world: /{name} ({member.mode:o})")
            if name.startswith("etc/ssh/ssh_host_") and name.endswith("_key"):
                problems.append(f"private SSH host key in the image: /{name}")
            if name == "boot-attempt":
                problems.append("stale /boot-attempt marker")
            if name in FORBIDDEN:
                problems.append(f"file that resets the tablet: /{name}")
            if name in REQUIRED:
                required.add(name)
            if name == SSH_CONFIG:
                ssh_config = tar.extractfile(member).read().decode()
            if name in EXECUTABLES and member.mode & 0o111 == 0:
                problems.append(f"required program is not executable: /{name} ({member.mode:o})")
            if name.startswith(WANTS):
                wants.add(name[len(WANTS):])
            if name == "root/.ssh" and member.mode & 0o077 == 0:
                seen["root_ssh"] = True
            if name == "root/.ssh/authorized_keys" and member.mode & 0o077 == 0:
                seen["authorized"] = True
            if name == "etc/shadow":
                for line in tar.extractfile(member).read().decode().splitlines():
                    user, _, hashed = line.partition(":")[0], None, line.split(":")[1]
                    if user in ("root", "alarm") and not hashed.startswith(("!", "*")):
                        problems.append(f"{user} has a password hash: the published default is not locked")
    for unit in ENABLED:
        if unit not in wants:
            problems.append(f"unit not enabled: {unit}")
    for unit in NOT_ENABLED:
        if unit in wants:
            problems.append(f"unit enabled that should not be: {unit}")
    for name in REQUIRED:
        if name not in required:
            problems.append(f"required rootfs file missing: /{name}")
    if not seen["root_ssh"]:
        problems.append("/root/.ssh missing or not private (700)")
    if not seen["authorized"]:
        problems.append("/root/.ssh/authorized_keys missing or not private (600)")
    for setting in (
        "PermitRootLogin prohibit-password",
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
    ):
        if setting not in ssh_config.splitlines():
            problems.append(f"SSH key-only setting missing: {setting}")
    return problems


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "out/rootfs/rootfs.tar"
    problems = check(path)
    if problems:
        for line in problems[:40]:
            print("FAIL", line)
        print(f"{len(problems)} problem(s) in {path}")
        sys.exit(1)
    print(f"ok  {path}")


if __name__ == "__main__":
    main()
