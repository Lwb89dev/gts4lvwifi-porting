#!/usr/bin/env python3
"""List the devices the board DTB enables and what the kernel build has for them.

For every enabled node of out/kernel's gts4lvwifi DTB it finds the driver
source that matches one of its compatibles, the Kconfig symbol that builds
that source, the symbol's value in out/kernel/.config and, for a module,
whether the .ko was built. It reads files only: no tablet, no network.

    scripts/hw-matrix.py > out/hw-matrix.md

"Built" here means "compiled into this kernel build". It says nothing about
whether the hardware works: that needs a measurement on the tablet, which
docs/HARDWARE-MATRIX.md records separately.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KERNEL = ROOT / "src/linux-gts4lv"
OUT = ROOT / "out/kernel"
DTB = OUT / "arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dtb"
DTC = OUT / "scripts/dtc/dtc"
SEARCH_DIRS = ("drivers", "sound")
COMPAT_RE = re.compile(r'\.compatible\s*=\s*"([^"]+)"')
OBJ_RE = re.compile(r"^obj-\$\(CONFIG_(\w+)\)\s*[:+]?=\s*(.*)$")
COMPOSITE_RE = re.compile(r"^([\w-]+?)-(?:y|objs|\$\(CONFIG_\w+\))\s*[:+]?=\s*(.*)$")


def decompile():
    result = subprocess.run([str(DTC), "-I", "dtb", "-O", "dts", str(DTB)],
                            capture_output=True, text=True, check=False)
    return result.stdout


BOARD_DTS = KERNEL / "arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dts"
SKIP_COMPAT = {"gpio-keys", "i2c-gpio", "simple-framebuffer", "regulator-fixed",
               "fixed-clock", "ramoops", "samsung,gts4lvwifi", "qcom,sdm670"}


def board_compats():
    """Compatibles the board DTS itself names: devices only this board has."""
    text = BOARD_DTS.read_text(errors="replace")
    found = set(re.findall(r'compatible\s*=\s*"([^"]+)"', text))
    return found - SKIP_COMPAT


def enabled_nodes(dts):
    """Nodes that are on: an explicit status "okay", or no status at all but a
    compatible the board DTS names (children of an enabled bus). Returns
    (path, compatible list)."""
    own = board_compats()
    stack, nodes = [], []
    info = {}
    for raw in dts.splitlines():
        line = raw.strip()
        if line.endswith("{"):
            stack.append(line[:-1].strip())
            info[len(stack)] = {"compat": [], "status": None}
        elif line == "};" and stack:
            entry = info.pop(len(stack))
            on = entry["status"] == "okay" or (
                entry["status"] is None and own.intersection(entry["compat"]))
            if on and entry["compat"]:
                nodes.append(("/".join(stack[1:]) or "/", entry["compat"]))
            stack.pop()
        elif stack and line.startswith("compatible"):
            info[len(stack)]["compat"] = re.findall(r'"([^"]+)"', line)
        elif stack and line.startswith("status"):
            info[len(stack)]["status"] = re.findall(r'"([^"]+)"', line)[0]
    return nodes


def compat_index():
    """One pass over the driver sources: compatible string -> source files."""
    cmd = ["grep", "-rIn", "--include=*.c", "-E", r'\.compatible\s*=\s*"'] + list(SEARCH_DIRS)
    text = subprocess.run(cmd, cwd=KERNEL, capture_output=True, text=True, check=False).stdout
    index = {}
    for line in text.splitlines():
        path = line.split(":", 2)[0]
        for compat in COMPAT_RE.findall(line):
            index.setdefault(compat, set()).add(path)
    return index


def parse_makefile(makefile):
    """Return (direct, composites): object -> symbol, and composite -> members."""
    direct, composites = {}, {}
    text = makefile.read_text(errors="replace").replace("\\\n", " ")
    for line in text.splitlines():
        line = line.strip()
        match = OBJ_RE.match(line)
        if match:
            for token in match.group(2).split():
                direct.setdefault(token, match.group(1))
            continue
        match = COMPOSITE_RE.match(line)
        if match:
            composites.setdefault(match.group(1) + ".o", []).extend(match.group(2).split())
    return direct, composites


def makefile_symbol(source):
    """Kconfig symbol and module stem that build <source>, or (None, None).

    Looks in the source's own Makefile, then in each parent directory's, for
    the object either listed directly or as a member of a composite (msm.o is
    built from msm-y += dsi/dsi.o ...).
    """
    path = KERNEL / source
    here = path.parent
    while here != KERNEL and here.parent != here:
        makefile = here / "Makefile"
        if makefile.exists():
            direct, composites = parse_makefile(makefile)
            obj = str(path.relative_to(here).with_suffix(".o"))
            if obj in direct:
                return direct[obj], path.stem
            for parent, members in composites.items():
                if obj in members and parent in direct:
                    return direct[parent], parent[:-2]
            guess = by_directory(direct, composites)
            if guess:
                return guess[0] + "*", guess[1]
        here = here.parent
    return None, None


def by_directory(direct, composites):
    """Fallback: the one composite module this Makefile builds, if it is the
    only one. Used when objects reach it through intermediate variables
    (msm-display-y), which are not resolved here. The caller marks it with *."""
    modules = [name for name in direct if name in composites]
    if len(modules) != 1:
        return None
    return direct[modules[0]], modules[0][:-2]


def config_value(symbol):
    if symbol is None:
        return "?"
    text = (OUT / ".config").read_text()
    match = re.search(rf"^CONFIG_{symbol.rstrip('*')}=(.*)$", text, re.M)
    return match.group(1) if match else "not set"


def module_built(stem):
    if stem is None:
        return "?"
    names = {stem, stem.replace("_", "-"), stem.replace("-", "_")}
    for name in names:
        if list((OUT / "modules").rglob(f"{name}.ko")):
            return "yes"
    return "no"


def row(node, compats, index):
    for compat in compats:
        for source in sorted(index.get(compat, ())):
            symbol, stem = makefile_symbol(source)
            value = config_value(symbol)
            built = module_built(stem) if value == "m" else ("built-in" if value == "y" else "no")
            return (node, compat, source, symbol or "?", value, built)
    return (node, compats[0], "none found", "-", "-", "-")


def main():
    for needed in (DTB, DTC, OUT / ".config", KERNEL / "Makefile"):
        if not needed.exists():
            sys.exit(f"hw-matrix: missing {needed}: run scripts/build-kernel.sh first")
    index = compat_index()
    rows = [row(n, c, index) for n, c in enabled_nodes(decompile())]
    print("`*` after a Kconfig symbol: found from the directory's only module, "
          "not from the object list.\n")
    print("| Node | Compatible | Driver source | Kconfig | Value | Built |")
    print("| --- | --- | --- | --- | --- | --- |")
    for r in sorted(set(rows)):
        print("| " + " | ".join(f"`{c}`" if c not in ("-", "?") else c for c in r) + " |")


if __name__ == "__main__":
    main()
