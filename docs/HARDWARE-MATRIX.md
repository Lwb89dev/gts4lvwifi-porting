# Hardware matrix

Written 2026-11-04 (evening of the first Arch boot). Kernel
`7.2.13-gts4lvwifi-g36f309c07087`, DTB `sdm670-samsung-gts4lvwifi.dtb`
(sha256 `e496d213…`), config as built that day (`out/kernel/.config`).

A driver in the sources is not working hardware. Every row has one of these
states, and "measured" says what was done on the tablet:

| State | Meaning here |
| --- | --- |
| Not verified | nothing known beyond the device tree |
| In the sources | a driver exists in the pinned tree, but this build does not compile it |
| Compiled | built into this kernel (`=y`) or as a module (`=m`) that exists |
| Detected by the kernel | something probed or registered, seen in `dmesg` or sysfs |
| Partly working | some function measured, others not |
| Working and tested | the function was used and the result checked |
| Regression | worked before, does not now |
| Blocked | cannot proceed until something else is done |

## 1. Measured on the tablet

| Subsystem | State | What was measured |
| --- | --- | --- |
| CPU and RAM | Working and tested | 8 cores (6 with `CPU part 0x803`, 2 with `0x802`), `MemTotal` 3635968 kB, Arch running with 286 MB used |
| eMMC | Working and tested | `sdhci-msm`, HS400, CQE, 58.2 GiB, 57 partitions seen from Linux with names and sizes equal to Android's. The root image lives in a file in userdata and is mounted read-write through dm-linear; readbacks of `recovery` matched their sha256 |
| USB gadget | Working and tested | dwc3 in device mode at high speed with the QUSB2 PHY; configfs NCM + RNDIS + ACM. ssh, ping, a 17 MB transfer by `nc`, `pacman` through a proxy. `usb_role` reads `device`. Host mode not tried |
| USB data path (SM5705 MUIC) | Working and tested | the bit-banged `i2c-charger` bus (needs `CONFIG_I2C_GPIO`), `MANSW1 = 0x24` written by init; without it the host never saw the gadget |
| Restart reasons (`qcom-pon`) | Working and tested | `reboot android` and `reboot recovery` reach Lineage and the recovery partition; a key reset does not |
| Power and volume-down keys | Detected by the kernel | `pm8941_pwrkey` and `pm8941_resin` input devices exist; no key event read |
| Thermal sensors | Detected by the kernel | 21 zones readable, 30.2 to 31.4 C at idle on 2026-11-04 21:20; no load test |
| Boot framebuffer | Partly working | `simpledrm` on the bootloader's framebuffer shows the text console (photos in `CONSOLE-LOG.txt`); no panel driver, no backlight control, nothing from the GPU. Until 2026-11-05 the screen went black at 31 s in every boot: the panel's supply `octa-vdd` (GPIO 21, no consumer) was switched off by the regulator late cleanup. With `regulator_ignore_unused` it stays `enabled` at 48 s; the lit panel is for the owner to confirm |
| Battery and charger status (SM5705) | Working and tested | `sm5705_battery` loaded by hand: `sm5705-battery` and `sm5705-charger` appear; `Charging`, 96%, 4.27 to 4.29 V, +336 to +468 mA, 28.5 C, `charge_full_design` 7040000 uAh. The tablet charges while running Linux (2026-11-05 07:19) |
| Firmware access | Working and tested | `modem` and `apnhlos` (vfat) and `vendor` (ext4) mounted read-only, 459 files linked under `/run`, all five names the device tree asks for exist. Nothing copied |
| Modem DSP (`4080000.remoteproc`) | Working and tested | boots: `mba.mbn` then `modem.mdt`, "remote processor is now up" in about 1.4 s. Stable alone for 2.5 minutes with `ath10k` unloaded, and with Wi-Fi up for 3 minutes. `gts4lv-modem.service` starts it at boot (`rmtfs -r -P -s` and `tqftpserv`); stopping `rmtfs` stops it cleanly ("stopped remote processor", `port failed halt` is only a warning). Reboot with the modem running is clean |
| Wi-Fi (WCN3990, `ath10k_snoc`) | Working and tested | `wlan0` appears 5 to 7 s after the modem starts, `iw dev wlan0 scan` lists networks on 2.4 and 5 GHz (4 networks, -42 to -88 dBm, 2026-11-05 08:15 and after a reboot). Association was not tried: it needs the owner's credentials. The MAC is random at each boot. **Board data matters**: with linux-firmware's `board-2.bin` (generic entry `bus=snoc,qmi-board-id=ff`) the whole SoC resets 10 to 17 s after the QMI handshake; with Samsung's `bdwlan.bin` as `board.bin` it is stable. The image keeps `board-2.bin` off the disk (pacman `NoExtract`) |
| Bluetooth (WCN3990 on `uart6`) | Working and tested | `modprobe hci_uart` after the firmware path is set: `hci0` appears, "QCA Downloading qca/crbtfw21.tlv" and `crnv21.bin`, "QCA setup on UART is completed" in 1.4 s. With `bluez`, `btmgmt info` shows the controller powered with the address from the device tree (`xx:xx:xx:xx:xx:xx`); a 12 s scan found 6 devices nearby (2026-11-05 08:34). Pairing and audio were not tried: they need the owner and a peer. `gts4lv-bluetooth.service` loads the driver at boot |
| Video codec (Venus, `aa00000.video-codec`) | Detected by the kernel | `modprobe venus_core` loads `venus_dec` and `venus_enc` without errors and `/dev/video12` and `/dev/video13` appear. No stream was decoded |
| Touch controller (STM FTS1BA90A, I2C `0x49` on `i2c-6` = `i2c9`) | Working and tested | our driver `fts1ba90a` (`device/gts4lvwifi/kernel`) binds at boot with the interrupt from the device tree (GPIO 123, level low). The owner's test on 2026-11-05 20:09, read through `evtest` on the evdev device: 19,153 events, 173 contacts opened and 173 closed (none stuck), `BTN_TOUCH` 98 down and 98 up, slots 0 to 3, **up to 4 fingers at once**, x 122..1530 of 0..1599 and y 148..2551 of 0..2559, pressure 2..30. The bottom edge was reached (2551 of 2559) and the right (1530 of 1599); the left and top only to 122 and 148 with very few samples near them, which may be how the corners were touched or a margin of the sensor: not known. Not tried: libinput and a compositor, rotation, resume after the display is off. Polling instead of the interrupt reset the tablet in 3 of 4 runs, see `PROGRESS.md`. `scripts/touch-summary.py` summarises an `evtest` log |
| Display (MSM DPU, two DSI links, Samsung AMSA05RB01 / ANA38401) | Working and tested | the owner's photo (2026-11-05 20:45) shows the full SMPTE colour bars from `modetest`, rotated 90 degrees (2560x1600 landscape mode, tablet held upright), without a visible seam where the two DSI halves meet. Needs `panel_samsung_ana38401 handover=1` (off by default: otherwise the driver resets the panel and it stays black) and one display power-save off/on cycle after `msm` loads. Brightness: 160, 100, 40, 255 and 160 written to `/sys/class/backlight/ae94000.dsi.0/brightness` and read back, the owner saw every step with no artifact (2026-11-05 20:57). Refresh: 63.3 page flips per second with `modetest -v` (the panel's TE runs at about 63 Hz while frames arrive and about 29 Hz at rest). Open: the text console does not draw on the msm framebuffer (`sys_imageblit: framebuffer is not in virtual address space`), off/on from a compositor, tearing; see `DISPLAY-PLAN.md` |
| GPU (Adreno 615) | Detected by the kernel | `renderD128` appears with `msm`; `a630_sqe.fw` and `a630_gmu.bin` load; the GPU node reports dummy `vdd`/`vddcx` supplies. No Vulkan or GL test |
| ADSP (`62400000.remoteproc`) | Working and tested | `echo start > /sys/class/remoteproc/remoteproc0/state` (firmware `adsp.mdt` from the vendor partition): up in 0.4 s with APR services and a FastRPC channel; `gts4lv-dsp stop adsp` stops it cleanly ("stopped remote processor adsp", sound card gone, tablet up, one `clk_unregister: unregistering prepared clock: LPASS_CLK_ID_INT_MCLK_0` warning). Never left running across a restart |
| LPASS LPI pins | Working and tested | `modprobe pinctrl_sdm670_lpass_lpi` after the ADSP runs; the sound card appears at once. Stays loaded after the ADSP stops: touching it then hangs the bus, so nothing may |
| Audio card (`sdm660-sndcard`) | Partly working | `card 0: S5e`, three MultiMedia PCMs, `Speaker Playback`, `Headphone Playback`, `Mic Capture` backends. After the LPI fix (below) a 1000 Hz tone through the speaker path was heard on 2 of 3 runs at -24, -18 and -12 dB with the protection DSP in the path; the per-speaker check (each amplifier alone) was played at 19:33 and is not reported yet. Microphones, UCM and PipeWire not done. The LPI pin driver must be unloaded each time the ADSP stops (`gts4lv-dsp stop adsp` does it): its registers reset with the ADSP, and without that only the first playback after a boot powered up |
| Speaker amplifiers (4x CS35L41) | Partly working | probe at `5-0040..0043`, revision A0, dummy `VA`/`VP` supplies. The protection DSP loads on all four with Samsung's `cs35l41-dsp1-spk-prot.wmfw` and tuning (`TAB_LV_S5e_PV2`) once the files are visible under `cirrus/` and `DSP1 Preload Switch` is on; `PCM Source` DSP puts it in the audio path (default ASP bypasses it). **A tone was played once at 0 dB with no protection loaded** (a failed volume command, see `AUDIO-PLAN.md`). The first power-up after the firmware is loaded afresh logs `Enable(1) failed: -110` (the DSP starts with the first stream); one second of silence first avoids it. Speaker calibration not done |
| Internal digital codec (`62ec0000`, PM660L analog) | Not working | any port that uses it (capture, or playback to `hw:0,1`) makes the ADSP report `AHB Bus hang … addr0 = 0x62…` and remoteproc restarts it (6 crashes, the tablet never reset). Giving the codec the real `INTERNAL_DIGITAL_CODEC_CORE` clock makes the firmware refuse it and the card disappears; reverted. Microphones and headphones are behind this |
| Package manager and clock | Working and tested | `pacman -Sy` and an install with signature check through the host proxy. No RTC: the clock starts in 1977 and is set from the host |

## 2. Everything else: what the build has

The next table is generated by `scripts/hw-matrix.py` from the compiled DTB,
the pinned driver sources and `out/kernel/.config`. "Built" is `built-in` for
`=y`, `yes` when the `.ko` exists, `no` otherwise. It says nothing about
whether the hardware works.

`*` after a Kconfig symbol: found from the directory's only module, not from the object list.

| Node | Compatible | Driver source | Kconfig | Value | Built |
| --- | --- | --- | --- | --- | --- |
| `i2c-charger/charger@49` | `siliconmitus,sm5705-charger` | `drivers/power/supply/sm5705_battery.c` | `BATTERY_SM5705` | `not set` | `no` |
| `i2c-fuelgauge/fuel-gauge@71` | `siliconmitus,sm5705-fuel-gauge` | `drivers/power/supply/sm5705_battery.c` | `BATTERY_SM5705` | `not set` | `no` |
| `reserved-memory/rmtfs-mem@fe301000` | `qcom,rmtfs-mem` | `drivers/of/platform.c` | `OF_OVERLAY_KUNIT_TEST*` | `not set` | `no` |
| `soc@0/audio-codec@62ec0000` | `qcom,msm8916-wcd-digital-codec` | `sound/soc/codecs/msm8916-wcd-digital.c` | `SND_SOC_MSM8916_WCD_DIGITAL` | `m` | `yes` |
| `soc@0/cci@ac4a000` | `qcom,msm8996-cci` | `drivers/i2c/busses/i2c-qcom-cci.c` | `I2C_QCOM_CCI` | `m` | `yes` |
| `soc@0/cci@ac4a000/i2c-bus@0/camera@2d` | `samsung,s5k4ha` | `drivers/media/i2c/s5k4ha.c` | `VIDEO_S5K4HA` | `not set` | `no` |
| `soc@0/cci@ac4a000/i2c-bus@1/camera@2d` | `samsung,s5k3m5-gts4lv` | `drivers/media/i2c/s5k3m5.c` | `VIDEO_S5K3M5` | `not set` | `no` |
| `soc@0/clock-controller@af00000` | `qcom,sdm845-dispcc` | `drivers/clk/qcom/dispcc-sdm845.c` | `SDM_DISPCC_845` | `y` | `built-in` |
| `soc@0/display-subsystem@ae00000` | `qcom,sdm670-mdss` | `drivers/gpu/drm/msm/msm_mdss.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/display-subsystem@ae00000/dsi@ae94000` | `qcom,mdss-dsi-ctrl` | `drivers/gpu/drm/msm/dsi/dsi.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0` | `samsung,ana38401-amsa05rb01` | `drivers/gpu/drm/panel/panel-samsung-ana38401.c` | `DRM_PANEL_SAMSUNG_ANA38401` | `not set` | `no` |
| `soc@0/display-subsystem@ae00000/dsi@ae96000` | `qcom,mdss-dsi-ctrl` | `drivers/gpu/drm/msm/dsi/dsi.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/display-subsystem@ae00000/phy@ae94400` | `qcom,dsi-phy-10nm` | `drivers/gpu/drm/msm/dsi/phy/dsi_phy.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/display-subsystem@ae00000/phy@ae96400` | `qcom,dsi-phy-10nm` | `drivers/gpu/drm/msm/dsi/phy/dsi_phy.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/dma-controller@800000` | `qcom,sdm845-gpi-dma` | `drivers/dma/qcom/gpi.c` | `QCOM_GPI_DMA` | `m` | `yes` |
| `soc@0/dma-controller@a00000` | `qcom,sdm845-gpi-dma` | `drivers/dma/qcom/gpi.c` | `QCOM_GPI_DMA` | `m` | `yes` |
| `soc@0/geniqup@8c0000` | `qcom,geni-se-qup` | `drivers/soc/qcom/qcom-geni-se.c` | `QCOM_GENI_SE` | `y` | `built-in` |
| `soc@0/geniqup@8c0000/i2c@89c000` | `qcom,geni-i2c` | `drivers/i2c/busses/i2c-qcom-geni.c` | `I2C_QCOM_GENI` | `m` | `yes` |
| `soc@0/geniqup@8c0000/i2c@89c000/audio-codec@40` | `cirrus,cs35l41` | `sound/soc/codecs/cs35l41-i2c.c` | `SND_SOC_CS35L41_I2C` | `not set` | `no` |
| `soc@0/geniqup@8c0000/i2c@89c000/audio-codec@41` | `cirrus,cs35l41` | `sound/soc/codecs/cs35l41-i2c.c` | `SND_SOC_CS35L41_I2C` | `not set` | `no` |
| `soc@0/geniqup@8c0000/i2c@89c000/audio-codec@42` | `cirrus,cs35l41` | `sound/soc/codecs/cs35l41-i2c.c` | `SND_SOC_CS35L41_I2C` | `not set` | `no` |
| `soc@0/geniqup@8c0000/i2c@89c000/audio-codec@43` | `cirrus,cs35l41` | `sound/soc/codecs/cs35l41-i2c.c` | `SND_SOC_CS35L41_I2C` | `not set` | `no` |
| `soc@0/geniqup@8c0000/serial@898000` | `qcom,geni-uart` | `drivers/tty/serial/qcom_geni_serial.c` | `SERIAL_QCOM_GENI` | `y` | `built-in` |
| `soc@0/geniqup@8c0000/serial@898000/bluetooth` | `qcom,wcn3990-bt` | `drivers/bluetooth/hci_qca.c` | `BT_HCIUART` | `m` | `yes` |
| `soc@0/geniqup@ac0000` | `qcom,geni-se-qup` | `drivers/soc/qcom/qcom-geni-se.c` | `QCOM_GENI_SE` | `y` | `built-in` |
| `soc@0/geniqup@ac0000/i2c@a84000` | `qcom,geni-i2c` | `drivers/i2c/busses/i2c-qcom-geni.c` | `I2C_QCOM_GENI` | `m` | `yes` |
| `soc@0/gpu@5000000` | `qcom,adreno` | `drivers/gpu/drm/msm/adreno/adreno_device.c` | `DRM_MSM*` | `m` | `yes` |
| `soc@0/isp@acb3000` | `qcom,sdm670-camss` | `drivers/media/platform/qcom/camss/camss.c` | `VIDEO_QCOM_CAMSS` | `m` | `yes` |
| `soc@0/mmc@7c4000` | `qcom,sdm670-sdhci` | `drivers/mmc/host/sdhci-msm.c` | `MMC_SDHCI_MSM` | `y` | `built-in` |
| `soc@0/phy@88e2000` | `qcom,qusb2-v2-phy` | `drivers/phy/qualcomm/phy-qcom-qusb2.c` | `PHY_QCOM_QUSB2` | `m` | `yes` |
| `soc@0/pinctrl@62b40000` | `qcom,sdm670-lpass-lpi-pinctrl` | `drivers/pinctrl/qcom/pinctrl-sdm670-lpass-lpi.c` | `PINCTRL_SDM670_LPASS_LPI` | `m` | `yes` |
| `soc@0/remoteproc@4080000` | `qcom,sdm670-mss-pil` | `drivers/remoteproc/qcom_q6v5_mss.c` | `QCOM_Q6V5_MSS` | `m` | `yes` |
| `soc@0/remoteproc@62400000` | `qcom,sdm670-adsp-pas` | `drivers/remoteproc/qcom_q6v5_pas.c` | `QCOM_Q6V5_PAS` | `m` | `yes` |
| `soc@0/remoteproc@62400000/glink-edge/fastrpc` | `qcom,fastrpc` | `drivers/misc/fastrpc.c` | `QCOM_FASTRPC` | `m` | `yes` |
| `soc@0/remoteproc@62400000/glink-edge/fastrpc/compute-cb@3` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@62400000/glink-edge/fastrpc/compute-cb@4` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@62400000/glink-edge/fastrpc/compute-cb@5` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@62400000/glink-edge/fastrpc/compute-cb@6` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc` | `qcom,fastrpc` | `drivers/misc/fastrpc.c` | `QCOM_FASTRPC` | `m` | `yes` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@1` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@2` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@3` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@4` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@5` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/remoteproc@8300000/glink-edge/fastrpc/compute-cb@6` | `qcom,fastrpc-compute-cb` | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c` | `ARM_SMMU` | `y` | `built-in` |
| `soc@0/rsc@179c0000/regulators-0` | `qcom,pm660-rpmh-regulators` | `drivers/regulator/qcom-rpmh-regulator.c` | `REGULATOR_QCOM_RPMH` | `y` | `built-in` |
| `soc@0/rsc@179c0000/regulators-1` | `qcom,pm660l-rpmh-regulators` | `drivers/regulator/qcom-rpmh-regulator.c` | `REGULATOR_QCOM_RPMH` | `y` | `built-in` |
| `soc@0/spmi@c440000/pmic@0/pon@800` | `qcom,pm8998-pon` | `drivers/power/reset/qcom-pon.c` | `POWER_RESET_QCOM_PON` | `m` | `yes` |
| `soc@0/spmi@c440000/pmic@0/pon@800/pwrkey` | `qcom,pm8941-pwrkey` | `drivers/input/misc/pm8941-pwrkey.c` | `INPUT_PM8941_PWRKEY` | `y` | `built-in` |
| `soc@0/spmi@c440000/pmic@0/pon@800/resin` | `qcom,pm8941-resin` | `drivers/input/misc/pm8941-pwrkey.c` | `INPUT_PM8941_PWRKEY` | `y` | `built-in` |
| `soc@0/spmi@c440000/pmic@2/pon@800` | `qcom,pm8998-pon` | `drivers/power/reset/qcom-pon.c` | `POWER_RESET_QCOM_PON` | `m` | `yes` |
| `soc@0/spmi@c440000/pmic@3/audio-codec@f000` | `qcom,pm8953-wcd-analog-codec` | `sound/soc/codecs/msm8916-wcd-analog.c` | `SND_SOC_MSM8916_WCD_ANALOG` | `m` | `yes` |
| `soc@0/usb@a6f8800` | `qcom,dwc3` | `drivers/usb/dwc3/dwc3-qcom-legacy.c` | `USB_DWC3_QCOM` | `y` | `built-in` |
| `soc@0/video-codec@aa00000` | `qcom,sdm845-venus-v2` | `drivers/media/platform/qcom/venus/core.c` | `VIDEO_QCOM_VENUS` | `m` | `yes` |
| `soc@0/watchdog@17980000` | `qcom,kpss-wdt` | `drivers/watchdog/qcom-wdt.c` | `QCOM_WDT` | `m` | `yes` |
| `soc@0/wifi@18800000` | `qcom,wcn3990-wifi` | `drivers/net/wireless/ath/ath10k/snoc.c` | `ATH10K_SNOC` | `m` | `yes` |
| `sound` | `qcom,sdm660-sndcard` | `sound/soc/qcom/sm8250.c` | `SND_SOC_SM8250` | `m` | `yes` |

### Gaps the table shows

Present in the sources and not compiled, although the device tree uses them:

| Device | Driver | Kconfig | Effect today |
| --- | --- | --- | --- |
| AMOLED panel (Samsung AMSA05RB01 behind an Anapass ANA38401, 2 DSI) | `panel-samsung-ana38401.c` | `DRM_PANEL_SAMSUNG_ANA38401` | `msm` has no panel, so no display beyond the boot framebuffer |
| Four speaker amplifiers | `cs35l41-i2c.c` | `SND_SOC_CS35L41_I2C` | no speakers |
| SM5705 fuel gauge and charger status | `sm5705_battery.c` | `BATTERY_SM5705` | no battery level. Its Kconfig help says the chips charge on their own and the driver only reports; not measured here |
| Rear and front cameras | `s5k3m5.c`, `s5k4ha.c` | `VIDEO_S5K3M5`, `VIDEO_S5K4HA` | no cameras |

Needed by userspace and missing from the config: `CONFIG_INPUT_UINPUT`. The
touchscreen has no kernel driver in this tree; pulpoff drives the STM
FTS1BA90A from a daemon over i2c-dev that creates its multitouch device
through uinput.

## 3. Not measured

Display, GPU, touch, Wi-Fi, Bluetooth, audio, sensors, battery, suspend,
cameras and the video codec are all "Not verified" or "Compiled" and nothing
more. Wi-Fi, Bluetooth, the video codec and the sensors need the modem or
audio DSP started first, with firmware from Samsung's own partitions, and
userspace services that Arch Linux ARM does not package (`rmtfs`, `tqftpserv`,
`qrtr`, `hexagonrpcd`; the kernel has its own `pd-mapper`). The order and the risks are in
`PORTING-ROADMAP.md`.
