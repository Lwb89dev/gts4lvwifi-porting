#!/usr/bin/env python3
"""Pack a header-v1 recovery image for gts4lvwifi.

The layout matches the Lineage recovery already on the tablet: page 4096,
Image.gz with the DTB appended, ramdisk, then Lineage's own recovery_dtbo.
This script only writes the output file. It does not flash the tablet.
"""

import argparse
import hashlib
import struct
import sys
from pathlib import Path

HEADER_SIZE = 1648


def repo_root():
    return Path(__file__).resolve().parent.parent


def load_conf(path):
    conf = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        conf[key.strip()] = value
    return conf


def need(conf, key):
    if key not in conf:
        sys.exit(f"device.conf missing {key}")
    return conf[key]


def parse_int(text):
    return int(text, 0)


def sha256_of(blob):
    return hashlib.sha256(blob).hexdigest()


def pad(blob, page):
    extra = (-len(blob)) % page
    if not extra:
        return blob
    return blob + bytes(extra)


def image_id(parts):
    sha = hashlib.sha1()
    for blob in parts:
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    return sha.digest()


def pack(kernel, ramdisk, dtbo, conf):
    page = parse_int(need(conf, "PAGESIZE"))
    if page != 4096 or parse_int(need(conf, "HEADER_VERSION")) != 1:
        sys.exit("this packer only writes the v1 header this tablet uses")
    name = need(conf, "BOOT_NAME").encode()
    cmdline = need(conf, "CMDLINE").encode()
    if len(name) > 16 or len(cmdline) >= 512 + 1024:
        sys.exit("boot name or cmdline does not fit the v1 header")

    ident = image_id((kernel, ramdisk, b"", dtbo))
    hdr = struct.pack(
        "<8s10I16s512s32s1024sIQI",
        b"ANDROID!",
        len(kernel),
        parse_int(need(conf, "KERNEL_OFFSET")),
        len(ramdisk),
        parse_int(need(conf, "RAMDISK_OFFSET")),
        0,
        parse_int(need(conf, "SECOND_ADDR")),
        parse_int(need(conf, "TAGS_OFFSET")),
        page,
        1,
        parse_int(need(conf, "OS_VERSION")),
        name,
        cmdline[:512],
        ident,
        cmdline[512:],
        len(dtbo),
        page + len(pad(kernel, page)) + len(pad(ramdisk, page)),
        HEADER_SIZE,
    )
    if len(hdr) != HEADER_SIZE:
        sys.exit(f"header is {len(hdr)} bytes, expected {HEADER_SIZE}")
    return pad(hdr, page) + pad(kernel, page) + pad(ramdisk, page) + pad(dtbo, page)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--ramdisk", required=True, type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    args = parser.parse_args()

    root = repo_root()
    conf = load_conf(root / "device/gts4lvwifi/device.conf")
    limit = parse_int(need(conf, "RECOVERY_PARTITION_SIZE"))
    dtbo_path = root / need(conf, "RECOVERY_DTBO")
    dtbo = dtbo_path.read_bytes()
    digest = sha256_of(dtbo)
    if digest != need(conf, "RECOVERY_DTBO_SHA256"):
        sys.exit(f"recovery dtbo sha256 is {digest}")

    kernel = args.kernel.read_bytes()
    ramdisk = args.ramdisk.read_bytes()
    image = pack(kernel, ramdisk, dtbo, conf)
    if len(image) > limit:
        sys.exit(f"image is {len(image)} bytes, recovery partition is {limit}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".tmp")
    tmp.write_bytes(image)
    tmp.replace(args.output)
    print(f"recovery image  {len(image)} bytes  limit {limit}")
    print(f"wrote           {args.output}")


if __name__ == "__main__":
    main()
