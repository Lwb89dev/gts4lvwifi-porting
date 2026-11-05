# M7.2 plan: display

Written 2026-11-04 night. Facts come from pulpoff's README (read, not copied),
the board device tree and the build. Nothing here has been tried on the tablet,
and the panel driver is not in the build that is in the tablet.

## Hardware

AMOLED 2560x1600 as two 1280x1600 halves on two DSI links in command mode:
Samsung AMSA05RB01 behind an Anapass ANA38401 (driver `panel-samsung-ana38401`,
now `CONFIG_DRM_PANEL_SAMSUNG_ANA38401=m`), on the MSM display engine
(`msm.ko` is built, `CONFIG_DRM_MSM=m`). The DT enables `mdss`, both DSI hosts
and both 10 nm DSI PHYs.

## What pulpoff's notes say matters

| Note | Consequence here |
| --- | --- |
| The driver takes over the panel the bootloader left running (`handover`, on by default). A cold start from reset stays black with this DSI host | The panel has to be lit by the bootloader when `msm` loads. A recovery boot lights it: the console photos show it. A reset in between would break it |
| `dispcc-sdm845` uses the no-init-park clock ops so the running display survives probe | Already in the tree we build |
| Continuous HS clock; `qcom,sync-dual-dsi` must stay off because Samsung addresses DSI0 only | Already in the DTS; do not change |
| The panel is off from probe until the first `enable()`. A brightness restore before the DSI link was up flashed the panel bright with lines over half of it | No brightness write before the link is up. Do not run a backlight restore service at boot |
| From `disable()` to `enable()` a brightness change is only stored. A DCS write while the link was going down failed with -110 and every later commit then waited out a timeout, about 5 fps | Avoid display off and on while testing; do it in a separate attempt |
| `msm` is a module, and the panel must survive until it loads: pulpoff adds `regulator_ignore_unused` | Our cmdline has `clk_ignore_unused pd_ignore_unused` and not that one. Adding it is a power-management change |
| Samsung's gamma per brightness level (83h rewritten before every latch) | Brightness is a later step; the first picture is at the bootloader's level |

## Rules from the assignment

- Do not change power-management parameters and the panel's initialisation
  sequence in the same attempt.
- Preserve `fw_devlink.sync_state=timeout`.
- Start from simpledrm, then the real driver.

## Attempts, one at a time

1. **Cmdline only. Done 2026-11-05.** The first version of this plan said the
   panel's supply was probably not among the regulators the late cleanup
   switches off. That was wrong, and it was wrong for a reason worth keeping:
   every photo of the console had been taken before 31 s, so none could show
   what happens after. The owner then saw the screen go black after the login
   prompt, and the tablet showed why. `octa-vdd` is the panel's VDD, a fixed
   regulator on TLMM GPIO 21 with `regulator-boot-on` and no consumer until the
   panel driver loads; the kernel logged `octa-vdd: disabling` at 31.226 s and
   the regulator read `state=disabled`, `num_users=0`. The screen was dark from
   31 s on, in every boot.

   `regulator_ignore_unused` was added to the cmdline, nothing else (kernel,
   DTB and the 23 files of the ramdisk are byte-identical to the image before,
   checked). Measured: the cmdline reaches the kernel, `octa-vdd` reads
   `enabled` at 10 s and at 48 s, and `dmesg` has no `: disabling` line at all.
   Whether the panel stays lit is for the person at the screen to confirm; the
   regulator state is the measurement.

   `/sys/class/graphics/fb0/blank` reads 4 both with the panel off and with it
   powered, so it says nothing about the panel.
2. **Panel module alone.** With a person at the screen and the module blacklist
   in place: `modprobe panel_samsung_ana38401`. Pass: it registers, the screen
   does not change. No `msm` yet.
3. **`msm`.** `modprobe msm`, with a log to the PC and a person at the screen.
   Expected: `msm` takes the framebuffer over from simpledrm. Look for a
   connector and a 2560x1600 mode with `modetest`, and for the DSI errors
   (-110, "ctl start" timeouts) that pulpoff describes. If the screen goes
   dark, `rmmod` is not safe; a reset and the watchdog note in
   `PORTING-ROADMAP.md` apply.
4. **A picture.** `modetest` pattern on the connector, both halves checked by
   the person: no tearing, no band, no seam at the 1280 boundary.
5. **Brightness**, display off and on, refresh and tearing, each as its own
   step, per the assignment's list.

## What would be a test over ssh

`ls /sys/class/drm`, `modetest -M msm`, `dmesg | grep -i -E "dsi|panel|msm"`,
the connector's `status` and `modes`, the backlight class device. None of them
says the panel looks right: that needs a person.
