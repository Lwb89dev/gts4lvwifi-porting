# M7.6: audio

Written 2026-11-05 evening, from what was measured the same afternoon. The speaker
amplifiers are the one place where a mistake can break hardware, so the order and the
checks below matter more than the rest.

## What exists

| Part | State on the tablet |
| --- | --- |
| ADSP (`adsp`; its remoteproc number is 0 or 1, it changed between two boots, so scripts ask by name through `gts4lv-dsp`) | `echo start > .../state`: up in 0.4 s, "remote processor adsp is now up", APR services (`q6core`, `q6afe`, `q6asm`, `q6adm`, `q6routing`) and a FastRPC channel appear |
| LPASS LPI pins | `modprobe pinctrl_sdm670_lpass_lpi` after the ADSP runs. The sound card appears at once |
| Card | `card 0: S5e [Galaxy Tab S5e]`, driver `sdm660-sndcard`: three PCMs (MultiMedia1 to 3, playback and capture) and three backend links from the device tree: `Speaker Playback` (secondary TDM to the four amplifiers), `Headphone Playback` and `Mic Capture` (PM660L analog codec) |
| Amplifiers | four CS35L41 at `5-0040` to `5-0043` (prefixes FR, FL, RR, RL), revision A0, `Subsystem ID not found`, dummy `VA`/`VP` supplies. Controls per amplifier: `Digital PCM Volume`, `Analog PCM Volume`, `DSP1 Firmware`, `DSP1 Preload Switch`, `PCM Soft Ramp`, `Amp Gain ZC Switch` |
| Protection DSP | loads, on all four, once `DSP1 Preload Switch` is on and the files are visible as `cirrus/cs35l41-dsp1-spk-prot.wmfw`, `.bin` (and `-calib.bin`): "Firmware: 400a4 vendor: 0x2 v0.0.1, 1 algorithms", tuning "Protection: ...TAB_LV_S5e_PV2_..." (Samsung's own, for this tablet) |

## How the volume scale works

`FL Digital PCM Volume` is 1 to 913, `dBminmax` -102 dB to +12 dB, 0.125 dB per step:
817 is 0.00 dB (the value at boot), 497 is -40 dB, 337 is -60 dB. `amixer sset "FL Digital
PCM" -60dB` does **not** work: `amixer` reads `-60dB` as an option (`-B`). Use `cset
name="FL Digital PCM Volume" 337`, or `sset ... -- -60dB`.

## What went wrong, and the rule that follows

At 18:24 a tone was played with the four amplifiers at **0.00 dB and no protection DSP**
loaded. The command that was meant to lower them failed (the `-60dB` problem above), its
error was thrown away, the printed summary showed `817 [0.00dB]` and the same script went
on to play. About five seconds of a 440 Hz sine from `speaker-test`, whose level is below
full scale but not low. The owner heard it. The kernel log has no line at all for that
interval (read afterwards, from 15850 s to 15990 s of uptime); whether the speakers were
stressed is not known.

Rule: every playback command first sets the volume, reads it back, and **stops** if the
readback is above the limit, in the same command. Nothing that can print its error into
`/dev/null` stands between the setting and the check. Start at -60 dB, with the protection
DSP loaded (`DSP1 Preload Switch` on for all four), and go up in steps that a person is
listening to.

## Order

1. Firmware path set (`gts4lv-firmware`, which also links the amplifier firmware under
   `cirrus/`).
2. `gts4lv-dsp start adsp`: starts the ADSP, then loads the LPI pin controller.
3. Amplifier volumes to -60 dB, read back; `DSP1 Preload Switch` on for FL, FR, RL, RR.
4. Route: `SEC_TDM_RX_0 Audio Mixer MultiMedia1` on.
5. Play (`speaker-test -D hw:0,0 -c 2 -t sine -f 440 -l 1`, killed by `timeout`), only
   after the readback of step 3.
6. `gts4lv-dsp stop adsp` before any restart (the bootloader loops on the next boot with the
   ADSP left running; `gts4lv-adsp-stop.service` does it at shutdown).

## `Enable(1) failed: -110`: the cause was stale LPI pins, not the DSP

Symptom: from the second playback of a boot on, every playback logged, for each amplifier,
`cs35l41 5-004x: Enable(1) failed: -110` and `ASoC: PRE_PMU: <FL|FR|RL|RR> Main AMP event
failed: -110`, 0.1 s apart, and nothing was heard. `cs35l41_global_enable()` sets
`GLOBAL_EN` and polls `CS35L41_IRQ1_STATUS1` (0x10010) for `PUP_DONE` for 100 ms.
Measured over I2C during one of those tones: `PWR_CTRL1` reads 1 (enabled), `IRQ1_STATUS1`
reads `0x00400000`, never `PUP_DONE`, the firmware mailbox reads 0.

It was first read as a protection-DSP problem. It is not: it also happened with the
DSP unloaded, and re-probing the four amplifiers did not clear it. What did:

- The speakers' TDM pins belong to the **LPASS LPI pin controller**
  (`pinctrl@62b40000`, state `sec-tdm-default-state`), whose registers live in the ADSP's
  power domain and return to their defaults when the ADSP restarts.
- The LPI driver stayed loaded across the restart and kept believing the pins were
  configured, so the next card's `pinctrl-0` selection did nothing. No clock on the TDM
  lines, no power-up. Only the first playback after the first card creation of a boot
  worked, which is why the very first tone (0 dB, no DSP) was the only one ever heard.
- Check: with the ADSP off, `modprobe -r pinctrl_sdm670_lpass_lpi` (it unloads without a hang),
  then a tone: no new error. After the fix in `gts4lv-dsp stop adsp` (it unloads the LPI
  driver once the ADSP is down), three tones in a row in `dsp` mode at -24, -18 and -12 dB
  gave 4 errors in the first and none in the next two. That first-run timeout is the
  amplifier's power-up taking longer than 100 ms while its protection firmware boots after
  being loaded afresh; not confirmed.

This also settles an earlier guess: the "false negative because the firmware clears the
flag" hypothesis was not needed.

## Tone ladder (`gts4lv-tone`)

| Run | What | Heard by the owner |
| --- | --- | --- |
| 18:24 | 440 Hz, **0 dB, no DSP**, 5 s (the mistake above) | a tone |
| 18:27 | 440 Hz, -40 dB, DSP loaded (second playback: failed to power up) | nothing |
| 18:35 to 18:37 | 440 Hz, -30, -24, -18 dB, DSP loaded (all failed to power up) | nothing |
| 19:23 | the same three, replayed (all failed to power up) | nothing |
| 19:25 to 19:27 | 440 Hz, -30 dB, no DSP; first playback of the boot: **no error** | nothing |
| 19:28 | 1000 Hz, -24 dB, no DSP (second playback: failed to power up) | nothing reported |
| 19:31 | 1000 Hz, -24, -18, -12 dB, DSP loaded **and in the path** (after the fix) | **2 of 3** (which two is to be confirmed; the first run is the one that logged the power-up error) |
| 19:33 | 1000 Hz, -12 dB, DSP in the path, one amplifier at a time: FL 19:33:06, FR 19:33:23, RL 19:33:39, RR 19:33:55 (no power-up error) | not reported yet |

The only run before the fix that powered up and was quiet enough to be a fair test is 19:25
(-30 dB, 440 Hz); nothing was heard, 30 dB below the tone that was heard and at a frequency
where a tablet speaker is weak. The other runs before 19:31 did not reach the speakers.
After the fix the sound comes out with the protection firmware loaded and in the audio path.

`gts4lv-tone <dB> [seconds] [hz] [mode] [amps]` (in the image, `/usr/local/sbin`) does the setup,
the checks and the cleanup of the order above. Modes: `asp` (default, protection loaded,
audio not through the DSP), `dsp` (protection loaded and in the audio path, `PCM Source`
DSP), `nodsp` (never louder than -24 dB). Nothing louder than -12 dB in any mode.

## Why the volume is not set to maximum

The digital volume reaches +12 dB and the analog gain +20 dB. On a full-scale sine that is
a clipped wave at full power. With `PCM Source` on `ASP`, which is the default, the
protection DSP is loaded but not in the audio path, so it protects nothing. Levels for
hearing the tablet go up in steps, with the DSP in the path (`dsp` mode), by decision of a
person who is listening.

## Microphones: the ADSP crashes when a capture stream opens

Tried 2026-11-05 evening, five times in four variants, each time with the same result:
`arecord` on `MultiMedia1` (`MultiMedia1 Mixer LPI_MI2S_TX_3`, `Digital DEC1 MUX` ADC1,
`Analog ADC2 MUX` INP2, `DEC2` ADC2), then on `MultiMedia3` with the routing the reference
tree's use-case file uses (ADC2 on INP3, ADC gain 6), then with the headphone route
(`LPI_MI2S_RX_0 Audio Mixer MultiMedia2`) also on, then mono at 16 kHz with only ADC1. The
recording ends at once and the **ADSP crashes**; remoteproc recovers it every time (the
tablet never reset). What the kernel logs:

- `AFE enable for port 0x1035 failed -110` and `fail to start AFE port` /
  `ASoC error (-110): at snd_soc_dai_prepare() on LPI_MI2S_TX_3` (port 0x1035 is the internal
  MI2S TX that carries the analog microphones), and in one run `q6asm-dai: Memory_map_regions
  failed`, `Audio Start: Buffer Allocation failed rc = -5`;
- the reason, when remoteproc prints it: `qcom_q6v5_pas 62400000.remoteproc: fatal error
  received: ABT_dal.c:269:ABTimeout: AHB Bus hang is detected, Number of bus hang detected := 1
  , addr0 = 0x62...` (the message is cut there). An AHB timeout at an address in 0x62xxxxxx:
  the LPASS block that holds the digital codec (`62ec0000.audio-codec`) did not answer when the
  AFE started the port.

Playback through the speakers is not affected: it uses the secondary TDM port, which does not
touch that block.

**It is not specific to capture.** Playing two seconds of silence to the internal codec
(`hw:0,1`, `LPI_MI2S_RX_0 Audio Mixer MultiMedia2`, port 0x102e) crashes the ADSP with the same
`AHB Bus hang` message. Every use of the internal digital codec does. `clk_summary` shows all
`LPASS_CLK_ID_INT_*` clocks at zero before the attempt.

**Tried and rejected, 2026-11-05 19:05:** in the device tree the codec's `ahbix-clk` is the fixed
clock `int_cdc_bclk`, which switches nothing on (the Pixel 3a and Xiaomi pyxis trees do the same
and their internal codec works). Giving it the real clock
`<&q6afecc LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE ...>` made the ADSP refuse the command
(`qcom-q6afe: cmd = 0x100f3 returned error = 0x2`, `AFE set params failed -22`), the codec's
probe failed (`failed to enable ahbclk -22`) and **the sound card no longer appeared**, speakers
included. The patch was reverted and the recovery rewritten with the earlier kernel; the card
is back. So this firmware manages that clock itself and the host must not ask for it.

Not yet tried, as ideas rather than leads: the order in which the codec's DAPM supplies power up;
whether the ADSP firmware (ADSP.VT.5.0-00513-SDM710, Samsung's) supports the internal MI2S ports at
all on this board (the tablet has no headphone jack, and its microphones may not be the
PM660L analog ones: Samsung's own tree is the place to look, `sound/soc/codecs` and the
`sdm670-sec-gts4lv-audio*` device tree files in `android_kernel_samsung_sdm670`); the full address
in the fatal message, which remoteproc cuts at `0x62`. With `coredump` set to `enabled` on the
ADSP (`echo enabled > /sys/class/remoteproc/remoteprocN/coredump`, N by name) the kernel keeps a
44 MB ELF in `/sys/class/devcoredump/devcd*/data` for five minutes; its strings are the firmware's
and did not name the cause.

After a crash remoteproc restarts the ADSP by itself, passing through `crashed` and `offline`
before `running`. A script that stops it must wait for that to finish (about 8 seconds), or it
leaves the ADSP running.

## Done and not done (2026-11-05)

- Done over ssh: ADSP start, LPI pins, card, controls, protection firmware on four amps, a
  tone at -40 dB (3 s, kernel log clean). Whether the second tone was audible and clean is
  for the owner.
- Not done: microphones (see the section above: the ADSP crashes when capture opens), headphones (the tablet has no jack; USB audio is a separate
  path), routing beyond MultiMedia1, UCM and PipeWire, per-channel check that each of the
  four speakers plays its own channel (the slots are `<0 1>` and `<1 2>` in the device
  tree), speaker calibration (Samsung keeps measured resistances in `/efs`; the firmware
  runs with the tuning's defaults).

## The four speakers (2026-11-05 21:00 to 21:10): what is established and what is not

Done with `gts4lv-tone -12 1 1000 dsp <amps> <beeps> <channel>` (1000 Hz, -12 dB, protection DSP
loaded and in the path), the owner listening, tablet upright with the camera at the top. The amps
sit at I2C addresses 0x40 to 0x43 and their bus number changes between boots (5, then 4).

| Run | What played | The owner heard |
| --- | --- | --- |
| 21:00, one amp per series, order FL FR RL RR | 1, 2, 3, 4 beeps | the first from the top, the other three from the bottom |
| 21:03, order RR FL RL FR | 1, 2, 3, 4 beeps | the first two from the top left, the others from the bottom left |
| 21:06, all four amps | 1 beep left channel only, 2 beeps right channel only | both from the top, from both top speakers |
| 21:08, RL and RR only (FL and FR at -60 dB) | 3 beeps | from the bottom: yes |

- **Established:** the top pair and the bottom pair both produce sound (the bottom pair alone
  was heard from the bottom). All four amplifiers are enabled alike while playing (over I2C:
  `PWR_CTRL1` 1, `PWR_CTRL2` `0x3721`, the same interrupt flags on all four, no new power-up
  error), so a difference between top and bottom is not in the amplifier's state.
- **Not established:** which address is which speaker, and whether left is left. The one-amp
  answers contradict each other (RR bottom in the first run, top left in the second), and with
  all four amps on the top pair covers the bottom pair to the ear. Samsung's suffix names suggest
  `FL` (0x41) and `FR` (0x40) are the top speakers and `RL` (0x43) and `RR` (0x42) the bottom ones,
  which fits the 21:06 and 21:08 runs; the `<0 1>` and `<1 2>` slots in the device tree send the left
  channel to FL and RL and the right channel to FR and RR.
- **To settle it** once something draws stereo, with the tablet landscape the way it is used:
  a left-only and a right-only tone, one person, listening for the side. An ear cannot separate
  four speakers a few centimetres apart; a measurement could (a microphone, which waits on the
  internal codec crash above).

## PipeWire, Bluetooth audio and the working level (2026-11-05 evening)

**The audio server.** `pipewire`, `pipewire-audio`, `pipewire-alsa`, `pipewire-pulse` and
`wireplumber` are installed (in `packages.txt`). PipeWire refuses to run as root
(`ConditionUser=!root`), so it runs for the `alarm` user, whose user session stays up without a
login (`/var/lib/systemd/linger/alarm`) and who is in the `audio`, `lp` and `video` groups
(`customize.sh`). Start the speakers with `gts4lv-audio start` (or `systemctl start
gts4lv-audio`, not enabled at boot: see the ADSP warning in the script).

**The speakers as a sink.** The card has no ACP profile, so WirePlumber offers only "Pro Audio":
eight unnamed AUX channels at 24 bits, and a normal stereo stream found no channel to land on
(silence, twice). `etc/wireplumber/wireplumber.conf.d/51-gts4lv-speakers.conf` presents the first
output as stereo FL FR at 16 bits, the format the amplifiers were proven with; the owner then
heard the tone through PipeWire.

**Bluetooth pairing.** The first attempt failed ("passkey or PIN wrong" on the phone): the
tablet's agent asked `Confirm passkey ... (yes/no)` and nothing answered. A `bluetoothctl` agent
that answers yes during a short window paired the phone (a Pixel 10), which was then trusted.
`l2ping` 5 of 5, 180 to 210 ms. The pairing window is closed afterwards (`discoverable off`,
`pairable off`): it accepts any device while open.

**Bluetooth audio (phone to tablet), what it took:**
1. No audio server: `a2dp-source profile connect failed: Protocol not available`; the controller
   published no Audio Sink. Installing PipeWire/WirePlumber was the prerequisite.
2. WirePlumber's Bluetooth monitor needs the user on the active logind seat, and `alarm` has none:
   BlueZ got no A2DP endpoint. `52-gts4lv-bluetooth.conf` turns `monitor.bluez.seat-monitoring`
   off for the main profile; the controller then published Audio Sink and Audio Source.
3. The phone connected and BlueZ built the A2DP transport (UUID 110b), but WirePlumber failed
   to create the node, repeatedly: `failed to create node from factory 'adapter'`,
   `usage: node.name=<string>`; the codec the Pixel had chosen was Google's vendor codec
   (Opus). Offered codecs were limited to `sbc sbc_xq aac`, the phone was reconnected and
   WirePlumber restarted (also once with debug logging). After that the music played from the
   tablet. **Which of those changes unlocked it is not known.**

**Speakers during Bluetooth music.** At first only the two speakers on the camera side played;
a little later, after the restarts, the owner heard all four. What made the two on the USB-C side
start is not established.

**The level.** The first working level (amplifiers at -18 dB digital, analog gain at its minimum)
was my own conservative choice after the 0 dB incident, and it made the music much fainter than
Android's. With the protection DSP loaded and in the path, four ten-second phases while music
played (all four amplifiers, each value read back, capped, restored afterwards):

| Phase | Digital | Analog | The owner |
| --- | --- | --- | --- |
| 1 | -12 dB | 0 | (no defect reported) |
| 2 | -6 dB | 0 | (no defect reported) |
| 3 | 0 dB | 0 | the clearest |
| 4 | 0 dB | +6 | the quietest |

More analog gain made it quieter, not louder; the protection limiting is the likely reason and was
not verified. `gts4lv-audio` now leaves the amplifiers at **0 dB digital, analog 0**, and only
raises them after the protection firmware is confirmed loaded on all four; it never goes above
0 dB. Android uses a higher analog gain (the reference tree cites 14 and 17); whether going
there with this protection tuning and without the speakers' calibration (Samsung keeps
measured values in `/efs`) is worth it was not tried further.

**Not done:** that the phone reconnects by itself after a tablet reboot (the audio unit is not
started at boot, so there are no speakers until `gts4lv-audio start`), the microphones, and the
A2DP source direction (tablet to headphones).

## Image v6 (2026-11-05 evening)

The audio pieces were baked into a fresh root image (v6) and tested from a clean state.

- `gts4lv-audio start` brings the speakers to the working level (0 dB digital, analog 0, protection
  in the path) with the protection firmware confirmed on all four amplifiers first.
- On the fresh image PipeWire offered only a dummy sink: WirePlumber had no remembered profile for the
  card (`alsa_card.platform-sound`, only "off" and "pro-audio"). `51-gts4lv-speakers.conf` now starts
  the card in `pro-audio` (with `api.acp.auto-profile` and `auto-port` off) and gives the sink
  `priority.session` and `priority.driver` 2000, so the default output is `Tab S5e speakers` without
  a manual step.
- A 3 s, 1 kHz tone through PipeWire at 40 % sink volume (restored to 100 % afterwards), no
  power-up errors in `dmesg`: the owner heard it from all four speakers.
- Still the case: the audio is not started at boot (`gts4lv-audio.service` exists and is not enabled),
  because an ADSP left running across a hard reset can loop the bootloader. The phone has to be paired
  again on v6 and the reconnection after a reboot tried. Microphones, headphones and the speaker mapping
  are open.

## Final automatic speaker path (2026-11-07)

The final Omarchy Mobile image supersedes the last bullet above. `gts4lv-audio.service` is enabled and
ordered before SDDM; `gts4lv-adsp-stop.service` still stops the ADSP on every orderly shutdown. The live
path loaded protection firmware on all four CS35L41 amplifiers, selected DSP PCM source, capped the
hardware digital level at -12 dB with analog gain 0, and published `Tab S5e speakers` automatically.
It survived a normal reboot and the exact audio-inclusive rootfs completed a hands-off boot with the
same sink.

WirePlumber software volume is initialized to 25 percent only on the first successful graphical
session. A state marker then preserves the owner's later choice across reboots. Microphones and the
internal codec remain blocked by the repeatable ADSP AHB hang; Bluetooth reconnection after reboot and
the tablet-to-headphones direction remain open.
