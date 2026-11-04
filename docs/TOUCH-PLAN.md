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
