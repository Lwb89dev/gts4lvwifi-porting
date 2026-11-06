#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Rotate the Tab S5e display while preserving its touch calibration.

Adapted from omamobile-sensors' autorotate.py, copyright (c) 2026 Derek
Ross.  The Tab S5e uses the stock iio-sensor-proxy service and its FTS touch
controller is mounted one quarter-turn from the DSI panel.  Consequently the
touch transform is always (monitor transform + 3) modulo 4.

The Omarchy Mobile rotation-lock tile is supported through
$XDG_STATE_HOME/omamobile/rotation-lock.  While the shell is locked, the
display is held at its native transform and the touch offset is retained.
"""
import argparse
import json
import os
import signal
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

NAME = "net.hadess.SensorProxy"
PATH = "/net/hadess/SensorProxy"
# The native-landscape DSI panel's transform direction is opposite to the
# phone-oriented mapping used by Omarchy Mobile. Normal and bottom-up are
# unchanged; the two quarter turns are swapped.
TRANSFORMS = {"normal": 0, "left-up": 3, "bottom-up": 2, "right-up": 1}
TOUCH_OFFSET = 3


def log(message):
    print(f"gts4lv-autorotate: {message}", file=sys.stderr, flush=True)


def touch_transform(monitor_transform):
    return (monitor_transform + TOUCH_OFFSET) % 4


def lock_path():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "omamobile", "rotation-lock")


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True)


def shell_locked(dry_run=False):
    if dry_run:
        return os.environ.get("OMAMOBILE_TEST_LOCKED") == "1"
    try:
        result = subprocess.run(
            ["omarchy-shell", "lock", "isLocked"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.stdout.strip() == "true"


def monitor(name=None):
    """Return (name, scale) for the requested monitor, or the first one."""
    try:
        monitors = json.loads(hyprctl("-j", "monitors").stdout or "[]")
    except json.JSONDecodeError:
        monitors = []
    for item in monitors:
        if name is None or item.get("name") == name:
            return item.get("name"), item.get("scale", 1.0)
    return None, None


def apply(transform, name=None, dry_run=False):
    mon, scale = (name or "DSI-1", 1.0) if dry_run else monitor(name)
    if mon is None:
        log("no monitor")
        return

    touch = touch_transform(transform)
    lua = (
        f'hl.monitor({{ output = "{mon}", mode = "preferred", position = "auto", '
        f"scale = {scale:g}, transform = {transform} }}); "
        f'hl.config({{ input = {{ touchdevice = {{ transform = {touch}, output = "{mon}" }} }} }})'
    )
    if dry_run:
        log(f"would run: hyprctl eval {lua!r}")
        return

    result = hyprctl("eval", lua)
    if result.returncode != 0 or "error" in (result.stdout + result.stderr).lower():
        # Compatibility fallback for Hyprland versions without `hyprctl eval`.
        hyprctl("keyword", "monitor", f"{mon},preferred,auto,{scale:g},transform,{transform}")
        hyprctl("keyword", "input:touchdevice:transform", str(touch))
        hyprctl("keyword", "input:touchdevice:output", mon)
    log(f"{mon}: monitor transform {transform}, touch transform {touch}")


class Rotator:
    def __init__(self, args):
        self.args = args
        bus_type = Gio.BusType.SESSION if args.session else Gio.BusType.SYSTEM
        self.bus = Gio.bus_get_sync(bus_type, None)
        self.claimed = False
        self.current = None
        self.wanted = None
        self.lock_poll = 0
        self.bus.signal_subscribe(
            NAME,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            PATH,
            None,
            Gio.DBusSignalFlags.NONE,
            self._changed,
        )
        Gio.bus_watch_name_on_connection(
            self.bus,
            NAME,
            Gio.BusNameWatcherFlags.NONE,
            self._appeared,
            self._vanished,
        )
        lock = Gio.File.new_for_path(lock_path())
        self.lock_monitor = lock.monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.lock_monitor.connect("changed", lambda *_args: self._update_claim())

    def _call(self, method):
        try:
            self.bus.call_sync(
                NAME,
                PATH,
                NAME,
                method,
                None,
                None,
                Gio.DBusCallFlags.NONE,
                5000,
                None,
            )
            return True
        except GLib.Error as error:
            log(f"{method}: {error.message}")
            return False

    def _prop(self, prop):
        try:
            value = self.bus.call_sync(
                NAME,
                PATH,
                "org.freedesktop.DBus.Properties",
                "Get",
                GLib.Variant("(ss)", (NAME, prop)),
                GLib.VariantType.new("(v)"),
                Gio.DBusCallFlags.NONE,
                5000,
                None,
            )
            return value.unpack()[0]
        except GLib.Error:
            return None

    def _appeared(self, _connection, _name, _owner):
        if not self._prop("HasAccelerometer"):
            log("the sensor proxy has no accelerometer")
            return
        self._update_claim()

    def _vanished(self, _connection, _name):
        self.claimed = False

    def _update_claim(self):
        locked = os.path.exists(lock_path())
        if locked and self.claimed:
            self.claimed = not self._call("ReleaseAccelerometer")
            log("rotation locked")
        elif not locked and not self.claimed:
            self.claimed = self._call("ClaimAccelerometer")
            if self.claimed:
                self._rotate(self._prop("AccelerometerOrientation"))

    def _changed(self, _connection, _sender, _path, _interface, _signal_name, params):
        _interface_name, changed, _invalidated = params.unpack()
        if "AccelerometerOrientation" in changed and self.claimed:
            self._rotate(changed["AccelerometerOrientation"])

    def _rotate(self, orientation):
        transform = TRANSFORMS.get(orientation)
        if transform is None:
            return
        self.wanted = transform
        if shell_locked(self.args.dry_run):
            if self.current != 0:
                log("native orientation while locked")
                self._apply(0)
            self._poll_lock()
            return
        self._apply(transform)
        if transform != 0:
            self._poll_lock()

    def _apply(self, transform):
        if transform == self.current:
            return
        self.current = transform
        apply(transform, self.args.monitor, self.args.dry_run)

    def _poll_lock(self):
        if not self.lock_poll:
            self.lock_poll = GLib.timeout_add_seconds(1, self._lock_tick)

    def _lock_tick(self):
        locked = shell_locked(self.args.dry_run)
        if locked and self.current != 0:
            log("native orientation while locked")
            self._apply(0)
        elif not locked and self.wanted is not None and self.wanted != self.current:
            self._apply(self.wanted)
        if locked or (self.wanted or 0) != 0:
            return True
        self.lock_poll = 0
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--monitor", default="DSI-1", help="output to rotate")
    parser.add_argument("--dry-run", action="store_true", help="log without changing Hyprland")
    parser.add_argument("--session", action="store_true", help="use the session bus for tests")
    args = parser.parse_args(argv)
    Rotator(args)
    loop = GLib.MainLoop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
