#!/usr/bin/env python3
"""Offline checks for the gts4lvwifi recovery packer. Does not flash."""

import gzip
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKER = ROOT / "scripts/pack-recovery.py"
VERIFY = ROOT / "scripts/verify-recovery.py"


def load_pack():
    spec = importlib.util.spec_from_file_location("pack_recovery", PACKER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def kernel_bytes():
    payload = gzip.compress(b"not a real kernel")
    return payload + b"samsung,gts4lvwifi"


def run_packer(kernel, ramdisk, output):
    return subprocess.run(
        [sys.executable, str(PACKER), "--kernel", str(kernel),
         "--ramdisk", str(ramdisk), "-o", str(output)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def main():
    pack = load_pack()
    conf = pack.load_conf(ROOT / "device/gts4lvwifi/device.conf")
    text = PACKER.read_text()
    if text.count("device/gts4lvwifi/device.conf") != 1:
        sys.exit("packer must read only the gts4lvwifi descriptor")
    overlay = (ROOT / conf["RECOVERY_DTBO"]).read_bytes()
    if pack.sha256_of(overlay) != conf["RECOVERY_DTBO_SHA256"]:
        sys.exit("pinned dtbo sha256 does not match the blob")
    if pack.sha256_of(b"corrupt") == conf["RECOVERY_DTBO_SHA256"]:
        sys.exit("sha check would accept corrupt input")

    ramdisk = gzip.compress(b"init")
    image = pack.pack(kernel_bytes(), ramdisk, overlay, conf)
    again = pack.pack(kernel_bytes(), ramdisk, overlay, conf)
    if image != again:
        sys.exit("packing is not repeatable")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        kern = work / "Image.gz-dtb"
        initrd = work / "ramdisk.gz"
        out = work / "recovery.img"
        kern.write_bytes(kernel_bytes())
        initrd.write_bytes(ramdisk)
        built = run_packer(kern, initrd, out)
        if built.returncode != 0:
            sys.exit(built.stderr)
        checked = subprocess.run(
            [sys.executable, str(VERIFY), str(out)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if checked.returncode != 0:
            sys.exit(checked.stderr)
        broken = out.read_bytes()[:-1]
        (work / "short.img").write_bytes(broken)
        rejected = subprocess.run(
            [sys.executable, str(VERIFY), str(work / "short.img")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if rejected.returncode == 0:
            sys.exit("truncated image was accepted")
        missing = run_packer(work / "absent", initrd, work / "no.img")
        if missing.returncode == 0 or (work / "no.img").exists():
            sys.exit("missing kernel was accepted")
        limit = pack.parse_int(conf["RECOVERY_PARTITION_SIZE"])
        page = pack.parse_int(conf["PAGESIZE"])
        fixed = page + len(pack.pad(kern.read_bytes(), page))
        fixed += len(pack.pad(overlay, page))
        huge = work / "huge"
        huge.write_bytes(b"\0" * (limit - fixed + 1))
        refused = run_packer(kern, huge, work / "too-big.img")
        if refused.returncode == 0 or (work / "too-big.img").exists():
            sys.exit("oversize image was written")
    print("pack-recovery tests ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
