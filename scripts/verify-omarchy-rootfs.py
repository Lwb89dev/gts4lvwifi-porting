#!/usr/bin/env python3
"""Check the M8 rootfs without mounting it or touching the tablet."""
import json
import sys
import tarfile

REQUIRED_PACKAGES = ("omarchy", "omamobile-omarchy", "omamobile-shell", "hyprland",
                     "mesa", "vulkan-freedreno", "libglvnd")
FORBIDDEN_PACKAGES = ("vulkan-panfrost",)
REQUIRED_FILES = ("usr/lib/dri/msm_dri.so", "usr/lib/libvulkan_freedreno.so",
                  "usr/share/vulkan/icd.d/freedreno_icd.json", "usr/bin/Hyprland",
                  "usr/share/wayland-sessions/hyprland-uwsm.desktop",
                  "usr/lib/gts4lv/hypr/tablet.lua", "usr/lib/gts4lv/autorotate.py",
                  "usr/lib/gts4lv/finalize-mobile-user",
                  "usr/lib/gts4lv/set-initial-speaker-volume",
                  "usr/lib/gts4lv/mark-poweroff-request",
                  "usr/lib/systemd/user/omamobile-autorotate.service",
                  "usr/lib/systemd/user/gts4lv-initial-speaker-volume.service",
                  "usr/lib/systemd/system/gts4lv-mark-poweroff.service",
                  "etc/systemd/user/graphical-session.target.wants/omamobile-autorotate.service",
                  "etc/systemd/user/graphical-session.target.wants/gts4lv-initial-speaker-volume.service",
                  "etc/systemd/system/multi-user.target.wants/gts4lv-audio.service",
                  "etc/systemd/system/poweroff.target.wants/gts4lv-mark-poweroff.service")
CONFIG_FILES = ("home/alarm/.config/hypr/hyprland.lua",
                "home/alarm/.config/omarchy/shell.json",
                "usr/lib/gts4lv/set-initial-speaker-volume",
                "usr/lib/gts4lv/mark-poweroff-request",
                "usr/lib/systemd/user/gts4lv-initial-speaker-volume.service",
                "usr/lib/systemd/system/gts4lv-mark-poweroff.service",
                "etc/sddm.conf.d/90-gts4lv-autologin.conf",
                "etc/systemd/system/sddm.service.d/10-gts4lv-display.conf",
                "etc/systemd/sleep.conf.d/90-gts4lv-disable-suspend.conf",
                "etc/systemd/user/omamobile-setup-user.service.d/10-gts4lv.conf",
                "var/lib/omamobile/omarchy-patches/state.json")


def fail(problems):
    for problem in problems:
        print("FAIL", problem)
    raise SystemExit(1)


def main():
    tar_path = sys.argv[1] if len(sys.argv) > 1 else "out/rootfs-omarchy/rootfs.tar"
    package_path = sys.argv[2] if len(sys.argv) > 2 else "out/rootfs-omarchy/packages.txt"
    problems = []
    with open(package_path, encoding="utf-8") as stream:
        package_versions = dict(line.split() for line in stream if line.strip())
    packages = set(package_versions)
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
    display_manager = members.get("etc/systemd/system/display-manager.service")
    if display_manager is None:
        problems.append("SDDM is not enabled through display-manager.service")
    elif not display_manager.issym() or not display_manager.linkname.endswith("sddm.service"):
        problems.append("display-manager.service does not select SDDM")
    autologin = members.get("etc/sddm.conf.d/90-gts4lv-autologin.conf", "")
    for setting in ("User=alarm", "Session=hyprland-uwsm.desktop", "Relogin=true"):
        if setting not in autologin.splitlines():
            problems.append(f"SDDM autologin setting missing: {setting}")
    sddm_order = members.get("etc/systemd/system/sddm.service.d/10-gts4lv-display.conf", "")
    for setting in ("Requires=gts4lv-display.service gts4lv-audio.service",
                    "After=gts4lv-display.service gts4lv-audio.service"):
        if setting not in sddm_order.splitlines():
            problems.append(f"SDDM speaker ordering missing: {setting}")
    hyprland = members.get("home/alarm/.config/hypr/hyprland.lua", "")
    if 'dofile("/usr/lib/gts4lv/hypr/tablet.lua")' not in hyprland:
        problems.append("Hyprland does not load the Tab S5e touchscreen calibration")
    shell = members.get("home/alarm/.config/omarchy/shell.json", "")
    try:
        shell_config = json.loads(shell)
    except (TypeError, json.JSONDecodeError):
        shell_config = {}
    if shell_config.get("idle", {}).get("lock") != 600:
        problems.append("Omarchy tablet lock timeout is not 600 seconds")
    mobile_setup = members.get(
        "etc/systemd/user/omamobile-setup-user.service.d/10-gts4lv.conf", ""
    )
    if "ConditionPathExists=" not in mobile_setup.splitlines():
        problems.append("Omamobile user setup still requires a firstboot marker")
    if "ExecStartPost=/usr/lib/gts4lv/finalize-mobile-user" not in mobile_setup.splitlines():
        problems.append("Omamobile setup does not restore the tablet policy")
    sleep_policy = members.get(
        "etc/systemd/sleep.conf.d/90-gts4lv-disable-suspend.conf", ""
    )
    for setting in ("AllowSuspend=no", "AllowHibernation=no",
                    "AllowSuspendThenHibernate=no", "AllowHybridSleep=no"):
        if setting not in sleep_policy.splitlines():
            problems.append(f"unsupported sleep mode is not disabled: {setting}")
    volume_helper = members.get("usr/lib/gts4lv/set-initial-speaker-volume", "")
    for setting in ("speaker-volume-initialized", "set-volume", "0.25"):
        if setting not in volume_helper:
            problems.append(f"initial speaker volume helper is missing: {setting}")
    volume_unit = members.get(
        "usr/lib/systemd/user/gts4lv-initial-speaker-volume.service", ""
    )
    for setting in ("ConditionPathExists=!%h/.local/state/gts4lv/speaker-volume-initialized",
                    "ExecStart=/usr/lib/gts4lv/set-initial-speaker-volume"):
        if setting not in volume_unit.splitlines():
            problems.append(f"initial speaker volume unit is missing: {setting}")
    power_helper = members.get("usr/lib/gts4lv/mark-poweroff-request", "")
    for setting in ("/var/lib/gts4lv/poweroff-requested", "sync"):
        if setting not in power_helper:
            problems.append(f"poweroff marker helper is missing: {setting}")
    power_unit = members.get("usr/lib/systemd/system/gts4lv-mark-poweroff.service", "")
    for setting in ("Before=poweroff.target umount.target",
                    "ExecStart=/usr/lib/gts4lv/mark-poweroff-request",
                    "WantedBy=poweroff.target"):
        if setting not in power_unit.splitlines():
            problems.append(f"poweroff marker unit is missing: {setting}")
    patch_state = members.get("var/lib/omamobile/omarchy-patches/state.json", "")
    try:
        patch_state = json.loads(patch_state)
    except (TypeError, json.JSONDecodeError):
        patch_state = {}
    if not patch_state.get("files") or not patch_state.get("applied"):
        problems.append("Omarchy Mobile patch series has no successful recorded state")
    for name, version in (("omarchy", "4.0.6-1"), ("omarchy-settings", "4.0.6-1")):
        if package_versions.get(name) != version:
            problems.append(
                f"{name} is {package_versions.get(name, 'missing')}, expected pinned {version}"
            )
    if "IgnorePkg = omarchy omarchy-settings" not in pacman_conf:
        problems.append("pinned Omarchy packages are not protected from upgrades")
    sections = [pacman_conf.find(f"[{name}]") for name in ("omamobile", "omarchy", "core")]
    if -1 in sections or sections != sorted(sections):
        problems.append("pacman repository order is not omamobile, omarchy, core")
    ignored = {
        package
        for line in pacman_conf.splitlines()
        if line.startswith("IgnorePkg =")
        for package in line.removeprefix("IgnorePkg =").split()
    }
    protected = {"mesa", "vulkan-mesa-implicit-layers", "vulkan-panfrost",
                 "aquamarine", "hyprtoolkit", "hyprland-guiutils",
                 "xdg-desktop-portal-hyprland"}
    missing = protected - ignored
    if missing:
        problems.append(f"pacman does not protect the Arch graphics stack: {sorted(missing)}")
    if problems:
        fail(problems)
    print(f"ok  {tar_path} (Omarchy Mobile installed, Freedreno protected, SDDM autologin enabled)")


if __name__ == "__main__":
    main()
