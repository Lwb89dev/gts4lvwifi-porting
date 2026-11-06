#!/usr/bin/env python3
"""Check the M8 rootfs without mounting it or touching the tablet."""
import sys
import tarfile

REQUIRED_PACKAGES = ("omarchy", "omamobile-omarchy", "omamobile-shell", "hyprland",
                     "mesa", "vulkan-freedreno", "libglvnd")
FORBIDDEN_PACKAGES = ("vulkan-panfrost",)
REQUIRED_FILES = ("usr/lib/dri/msm_dri.so", "usr/lib/libvulkan_freedreno.so",
                  "usr/share/vulkan/icd.d/freedreno_icd.json", "usr/bin/Hyprland",
                  "usr/lib/gts4lv/hypr/tablet.lua", "usr/lib/gts4lv/autorotate.py",
                  "usr/lib/systemd/user/omamobile-autorotate.service",
                  "etc/systemd/user/graphical-session.target.wants/omamobile-autorotate.service")
CONFIG_FILES = ("home/alarm/.config/hypr/hyprland.lua",
                "home/alarm/.config/omarchy/shell.json")


def fail(problems):
    for problem in problems:
        print("FAIL", problem)
    raise SystemExit(1)


def main():
    tar_path = sys.argv[1] if len(sys.argv) > 1 else "out/rootfs-omarchy/rootfs.tar"
    package_path = sys.argv[2] if len(sys.argv) > 2 else "out/rootfs-omarchy/packages.txt"
    problems = []
    with open(package_path, encoding="utf-8") as stream:
        packages = {line.split()[0] for line in stream if line.strip()}
    for package in REQUIRED_PACKAGES:
        if package not in packages:
            problems.append(f"required package missing: {package}")
    for package in FORBIDDEN_PACKAGES:
        if package in packages:
            problems.append(f"Mali-only package installed: {package}")

    with tarfile.open(tar_path, "r|*") as archive:
        members = {}
        pacman_conf = ""
        for member in archive:
            name = member.name.lstrip("./")
            if name in REQUIRED_FILES or name in CONFIG_FILES or name == "etc/systemd/system/display-manager.service":
                members[name] = member
                if name in CONFIG_FILES:
                    members[name] = archive.extractfile(member).read().decode()
            if name == "etc/pacman.conf":
                pacman_conf = archive.extractfile(member).read().decode()
    for path in REQUIRED_FILES:
        if path not in members:
            problems.append(f"required Freedreno/Hyprland file missing: /{path}")
    if "etc/systemd/system/display-manager.service" in members:
        problems.append("graphical session enabled before the first M8 boot test")
    hyprland = members.get("home/alarm/.config/hypr/hyprland.lua", "")
    if 'dofile("/usr/lib/gts4lv/hypr/tablet.lua")' not in hyprland:
        problems.append("Hyprland does not load the Tab S5e touchscreen calibration")
    shell = members.get("home/alarm/.config/omarchy/shell.json", "")
    if '"lock": 600' not in shell:
        problems.append("Omarchy tablet lock timeout is not 600 seconds")
    sections = [pacman_conf.find(f"[{name}]") for name in ("omamobile", "omarchy", "core")]
    if -1 in sections or sections != sorted(sections):
        problems.append("pacman repository order is not omamobile, omarchy, core")
    ignore_line = next((line for line in pacman_conf.splitlines()
                        if line.startswith("IgnorePkg =")), "")
    ignored = set(ignore_line.removeprefix("IgnorePkg =").split())
    protected = {"mesa", "vulkan-mesa-implicit-layers", "vulkan-panfrost",
                 "aquamarine", "hyprtoolkit", "hyprland-guiutils",
                 "xdg-desktop-portal-hyprland"}
    missing = protected - ignored
    if missing:
        problems.append(f"pacman does not protect the Arch graphics stack: {sorted(missing)}")
    if problems:
        fail(problems)
    print(f"ok  {tar_path} (Omarchy Mobile installed, Freedreno protected, session disabled)")


if __name__ == "__main__":
    main()
