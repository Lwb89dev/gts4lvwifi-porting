#!/usr/bin/env python3
"""Check a packed gts4lvwifi recovery image. Does not flash."""

import hashlib
import importlib.util
import struct
import sys
from pathlib import Path


def load_pack():
    path = Path(__file__).resolve().parent / "pack-recovery.py"
    spec = importlib.util.spec_from_file_location("pack_recovery", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fail(message):
    print(message, file=sys.stderr)
    return 1


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} IMAGE", file=sys.stderr)
        return 2
    pack = load_pack()
    root = pack.repo_root()
    conf = pack.load_conf(root / "device/gts4lvwifi/device.conf")
    image = Path(sys.argv[1]).read_bytes()
    page = pack.parse_int(pack.need(conf, "PAGESIZE"))
    limit = pack.parse_int(pack.need(conf, "RECOVERY_PARTITION_SIZE"))
    if image[:8] != b"ANDROID!" or len(image) > limit or len(image) % page:
        return fail("bad magic, size, or padding")
    vals = struct.unpack_from("<10I", image, 8)
    kernel_size, kernel_addr, ramdisk_size, ramdisk_addr = vals[:4]
    second_size, second_addr, tags_addr, page_hdr, version, os_version = vals[4:]
    if page_hdr != page or version != 1 or second_size != 0:
        return fail("header is not the v1 layout this tablet uses")
    expected = {
        "KERNEL_OFFSET": kernel_addr,
        "RAMDISK_OFFSET": ramdisk_addr,
        "TAGS_OFFSET": tags_addr,
        "SECOND_ADDR": second_addr,
        "OS_VERSION": os_version,
    }
    for key, got in expected.items():
        if got != pack.parse_int(pack.need(conf, key)):
            return fail(f"{key} mismatch")
    name = image[48:64].split(b"\0", 1)[0]
    if name != pack.need(conf, "BOOT_NAME").encode():
        return fail("boot name mismatch")
    cmdline = image[64:576].split(b"\0", 1)[0]
    if b"fw_devlink.sync_state=timeout" not in cmdline:
        return fail("cmdline lost fw_devlink.sync_state=timeout")
    dtbo_size, dtbo_off, header_size = struct.unpack_from("<IQI", image, 1632)
    if header_size != pack.HEADER_SIZE:
        return fail("header size mismatch")
    kernel = image[page:page + kernel_size]
    ramdisk_off = page + len(pack.pad(kernel, page))
    ramdisk = image[ramdisk_off:ramdisk_off + ramdisk_size]
    if ramdisk_off + len(pack.pad(ramdisk, page)) != dtbo_off:
        return fail("recovery dtbo offset mismatch")
    dtbo = image[dtbo_off:dtbo_off + dtbo_size]
    if len(kernel) != kernel_size or len(ramdisk) != ramdisk_size or len(dtbo) != dtbo_size:
        return fail("image truncated")
    if not kernel.startswith(b"\x1f\x8b") or b"samsung,gts4lvwifi" not in kernel:
        return fail("kernel payload is not Image.gz with the gts4lvwifi DTB")
    overlay = (root / pack.need(conf, "RECOVERY_DTBO")).read_bytes()
    if dtbo != overlay:
        return fail("recovery dtbo bytes differ from the Lineage overlay")
    digest = hashlib.sha256(dtbo).hexdigest()
    if digest != pack.need(conf, "RECOVERY_DTBO_SHA256"):
        return fail(f"recovery dtbo sha256 is {digest}")
    print(f"ok  {len(image)} bytes  kernel {kernel_size}  ramdisk {ramdisk_size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
