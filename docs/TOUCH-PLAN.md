# M7.4 plan: touchscreen

Written 2026-11-04 night. Facts below were read from Samsung's 4.9 kernel
(`android_kernel_samsung_sdm670`, objects in git, the sparse checkout has no
`drivers/`), from the device tree of both kernels and from the mainline
`stmfts` driver in our tree. Nothing was run on the tablet.

## Hardware

| Fact | Value | Source |
| --- | --- | --- |
| Controller | STMicroelectronics FTS1BA90A | Samsung `drivers/input/touchscreen/stm/fts1ba90a/` |
| Bus and address | I2C `0x49` on QUP SE9 (`i2c9` in our device tree, 400 kHz, enabled) | Samsung `sdm670-sec-gts4lv-input-common.dtsi`, our DTS |
| Interrupt | TLMM GPIO 123, active low (Samsung `0x2008`) | same |
| Supplies | DVDD `pm660_l11` (1.8 V), AVDD `pm660l_l6` (3.0 to 3.3 V). Both are `regulator-always-on` in our DTS, so the chip is powered from boot | Samsung DT, our DTS lines 337 and 410 |
| Reported range | x 0..1599, y 0..2559: the panel's native portrait orientation | Samsung DT `stm,max_coords` |
| Firmware | `tsp_stm/fts1ba90a_gts4lv.fw`, loaded by Samsung's driver from the vendor image when the version differs; whether the chip keeps a working one in its flash is not known here | Samsung DT, `fts_fwu.c` |

## Protocol, from Samsung's driver (GPL-2.0)

- An event is 8 bytes. For a touch: `eid:2, tid:4, action:2`, `x[11:4]`,
  `y[11:4]`, `y[3:0]` and `x[3:0]` in one byte, `major`, `minor`, `z:6` with
  two bits of touch type, `left_event:6` (events still queued) with the other
  two. The 12-bit coordinates are `x = x[11:4] << 4 | x[3:0]`, same for `y`.
- Actions: 1 press, 2 move, 3 release. The touch type separates finger from
  hover and other kinds.
- The FIFO holds up to 32 events: command `0x60` reads one, `0x61` reads all,
  `0x62` clears. Sense on and off are `0x10` and `0x11`, a software reset `0x12`.
- A status event (id `0x43`) and an error event (`0xF3`) share the FIFO.

This is not the protocol of the mainline `stmfts` driver, which handles the
FTS5CU56A: there the commands are `0x85`, `0x86`, `0x87`, sense on is `0x93`
and the event ids differ. The mainline driver would not work here unchanged.

## What exists and why it is not used

pulpoff drives the chip from a userspace daemon over i2c-dev that creates its
device through uinput. The file has no licence (`LICENSES.md`), so it is not
copied. It also needs `CONFIG_INPUT_UINPUT`, which this build did not have and
now has as a module.

## Options

| | A. Kernel driver | B. Userspace daemon |
| --- | --- | --- |
| What | a small `input_mt` driver for the FTS1BA90A, written from the facts above | an i2c-dev reader of the same events that feeds uinput |
| For | a real evdev device for libinput and the compositor from the first boot, no extra process, no uinput, the kind of change that can go upstream | testable without a kernel build, quick to try |
| Against | needs a kernel build and a flash per iteration | the interrupt is not available through i2c-dev: the daemon has to poll or use the GPIO character device, with latency and wakeups; one more thing to keep alive |
| Licence | GPL-2.0, derived from Samsung's GPL source and the mainline pattern | any, but the facts come from the same GPL source |

Recommendation: A. The event format is small and fully known, and the cost of a
flash is now low (`scripts/flash-recovery-shell.sh`). The daemon is the
fallback if the chip needs a firmware sequence that is easier to explore from
userspace.

## Steps

**Steps 1 and 2 done 2026-11-05** (read from the running tablet, nothing written but the read commands): bus `i2c-6` is `i2c9`; `i2ctransfer -y 6 w1@0x49 0x22 r8` answers `53 54 39 36 03 03 03 03`, `0x24` answers `00 11 00 06 07 06 06 06`, and `0x60` returns 8-byte events (first `49 00 10 00 00 00 00 00`, then zeros). The chip answers and its event FIFO reads as described. What the bytes mean in the chip's own terms is not confirmed.

1. Read-only: with the kernel's i2c-dev (`CONFIG_I2C_CHARDEV=y`, present),
   `i2cdetect -y -r` on the bus of `i2c9` and a read at `0x49`, one register at a
   time, as the upstream rules ask. Expect an answer: the supplies are on.
2. Read `FTS_READ_DEVICE_ID` (`0x22`) and `FTS_READ_FW_VERSION` (`0x24`) to see
   whether the chip answers as an FTS1BA90A and with what firmware.
3. Only then write the driver, with `stmfts.c` as the skeleton: probe, sense
   on, an interrupt handler that reads with `0x61`, `input_mt_slot` and
   `input_mt_report_slot_state` per touch id, `x`, `y`, `major`, `minor`, `z`.
4. Test with `evtest`: slots, positions and the corners of the 1600x2560 area,
   with a person touching the glass.
5. Orientation and calibration are the compositor's business (libinput); the
   driver reports the native portrait axes.

## Status 2026-11-05 (after the first driver)

- Steps 1 to 3 are done: the chip answers, and `device/gts4lvwifi/kernel/fts1ba90a/fts1ba90a.c`
  exists, with the device tree node and Kconfig/Makefile entries as patches in
  `device/gts4lvwifi/kernel/patches/`, applied by `scripts/apply-kernel-patches.sh`.
- The event layout in the driver is Samsung's `struct fts_event_coordinate`:
  byte 0 `eid:2 tid:4 action:2`, bytes 1 and 2 the high bits of x and y, byte 3 the low
  nibbles (x high, y low), bytes 4 and 5 major and minor, byte 6 `z:6 ttype:2`, byte 7
  `left_event:6 ttype:2`. A status event has `eid` 1, `stype` in bits 2 to 5 of byte 0
  and the id in byte 1.
- **Do not poll the FIFO.** With scanning on, reading the FIFO on a timer reset the
  tablet in 3 of 4 runs (no log, no panic); the same driver reading only after the
  interrupt, scanning on, was stable for 5 minutes. The `poll_ms` fallback stays for
  bring-up but is not safe to leave running.
- Step 4, first result (the owner, 2026-11-05 ~14:45): the driver's debug log has 628
  events, all coordinate events, 22 presses, 584 moves, 22 releases, up to 3 fingers
  (`tid` 0 to 2), x 739..1295 and y 820..1896, pressure 3 to 26, touch type 0, no error
  event. Press and release counts match. Not tried: the corners of the 1600x2560 area,
  the events as evdev reports them (`evtest`), libinput and a compositor, scrolling and
  gestures, rotation, resume after the display is off.
- The module is on the blacklist in the image (`gts4lv-blacklist.conf`) until it has
  been tried in a full session.

## Status 2026-11-05 20:10: seen through evdev

Recorded with `evtest /dev/input/event3` for 45 seconds while the owner touched the corners,
two fingers and a drag (cue: colour bars on the screen; a first recording and a second one
with no touch at all were wasted because the instructions in the terminal were not seen).
`scripts/touch-summary.py` gives: 19,153 events, 173 contacts opened and closed, `BTN_TOUCH`
98/98, slots 0 to 3, at most 4 fingers down at once (instants with 0, 1, 2, 3, 4 fingers: 100,
158, 66, 15, 7), x 122..1530 and y 148..2551, pressure 2..30, contact size 1..17.

Open: whether x and y really reach 0 and the maximum (the left and top edges only got to 122
and 148, with one and zero samples within 130 of the edge; a deliberate edge swipe from the
owner settles it), libinput and a compositor (calibration and rotation are theirs), resume
after the display is turned off, and the module still being blacklisted in the image.
