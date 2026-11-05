#!/usr/bin/env python3
"""Offline checks of the root image's contents, read from the container export
(out/rootfs/rootfs.tar) the image is made from. Reads only.

    scripts/verify-rootfs.py [rootfs.tar]

It looks for mistakes that were once made: files owned by the build user
(uid 1000, "alarm"), system directories writable by group or world, a
published default password that survived, private SSH host keys baked into
the image, a stale boot marker, a missing authorized_keys.
"""
import sys
import tarfile

SYSTEM = ("etc", "usr", "boot", "root", "opt")
HOME_OK = ("home/alarm",)


def check(path):
    problems = []
    seen = {"root_ssh": False, "authorized": False}
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
            if name == "root/.ssh" and member.mode & 0o077 == 0:
                seen["root_ssh"] = True
            if name == "root/.ssh/authorized_keys" and member.mode & 0o077 == 0:
                seen["authorized"] = True
            if name == "etc/shadow":
                for line in tar.extractfile(member).read().decode().splitlines():
                    user, _, hashed = line.partition(":")[0], None, line.split(":")[1]
                    if user in ("root", "alarm") and not hashed.startswith(("!", "*")):
                        problems.append(f"{user} has a password hash: the published default is not locked")
    if not seen["root_ssh"]:
        problems.append("/root/.ssh missing or not private (700)")
    if not seen["authorized"]:
        problems.append("/root/.ssh/authorized_keys missing or not private (600)")
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
