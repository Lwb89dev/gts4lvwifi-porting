#!/usr/bin/env python3
"""Summarise an evtest log of the touchscreen (reads only).

    ssh root@172.16.42.1 'timeout 45 evtest /dev/input/event3' > touch.log
    scripts/touch-summary.py touch.log

Prints the number of events, contacts opened and closed, the slots used, the most
fingers down at once, the coordinate ranges against the declared ones
(x 0..1599, y 0..2559) and how close to each edge the contacts got.
"""
import re
import sys

EVENT = re.compile(r"type \d+ \((\w+)\), code \d+ \((\w+)\), value (-?\d+)")
XMAX, YMAX = 1599, 2559
NEAR = 130


def pct(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, len(values) * p // 100)]


def read(path):
    s = {"events": 0, "opened": 0, "closed": 0, "down": 0, "up": 0, "slots": set(),
         "xs": [], "ys": [], "pressure": [], "major": [], "most": 0}
    active = {}
    slot = 0
    with open(path, errors="replace") as log:
        for line in log:
            m = EVENT.search(line)
            if not m:
                continue
            s["events"] += 1
            name, value = m[2], int(m[3])
            if name == "ABS_MT_SLOT":
                slot = value
                s["slots"].add(value)
            elif name == "ABS_MT_TRACKING_ID":
                active[slot] = value >= 0
                s["opened" if value >= 0 else "closed"] += 1
                s["most"] = max(s["most"], sum(active.values()))
            elif name == "BTN_TOUCH":
                s["down" if value else "up"] += 1
            elif name in ("ABS_MT_POSITION_X", "ABS_MT_POSITION_Y", "ABS_MT_PRESSURE", "ABS_MT_TOUCH_MAJOR"):
                key = {"ABS_MT_POSITION_X": "xs", "ABS_MT_POSITION_Y": "ys",
                       "ABS_MT_PRESSURE": "pressure", "ABS_MT_TOUCH_MAJOR": "major"}[name]
                s[key].append(value)
    return s


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    s = read(sys.argv[1])
    print(f"events {s['events']}, contacts opened {s['opened']} closed {s['closed']}, "
          f"BTN_TOUCH down {s['down']} up {s['up']}, slots {sorted(s['slots'])}, "
          f"most fingers at once {s['most']}")
    if not s["xs"]:
        print("no coordinates")
        return
    xs, ys = s["xs"], s["ys"]
    print(f"x {min(xs)}..{max(xs)} of 0..{XMAX}, median {pct(xs, 50)}; "
          f"y {min(ys)}..{max(ys)} of 0..{YMAX}, median {pct(ys, 50)}")
    print(f"within {NEAR} of: left {sum(x <= NEAR for x in xs)}, right {sum(x >= XMAX - NEAR for x in xs)}, "
          f"top {sum(y <= NEAR for y in ys)}, bottom {sum(y >= YMAX - NEAR for y in ys)} samples")
    if s["pressure"]:
        print(f"pressure {min(s['pressure'])}..{max(s['pressure'])}, contact size {min(s['major'])}..{max(s['major'])}")


if __name__ == "__main__":
    main()
