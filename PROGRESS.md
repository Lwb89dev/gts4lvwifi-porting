# Progresso del port gts4lvwifi

Aggiornato il 2026-11-06 mezzogiorno, branch `feat/gts4lvwifi-mainline-bringup`.
Questo file è il racconto unico di quello che è stato fatto su questo SM-T720.
Le misure riga per riga stanno in `device/gts4lvwifi/NOTES.md`. Il runbook di
rollback sta in `docs/RECOVERY-RUNBOOK.md`.

## Passaggio di consegne: da Claude a Codex (aggiornato 2026-11-05, sera)

Il proprietario ha raggiunto il **98 % del limite settimanale** con Claude (Sonnet 5.5), mi ha chiesto di
fermarmi e **passa il lavoro a Codex adesso**. Questa sezione è per chi riprende. Per le regole del
progetto valgono `PROMPT.md` (milestone M0-M9) e questa sezione; il resto del file è la
cronaca, in ordine di tempo, e le frasi più vecchie possono essere superate da quelle più
nuove.

### Regole del proprietario, da rispettare

- **Il tablet è sacrificabile, con limiti.** Si può scrivere `recovery`, `userdata` e i file
  sotto `/data` (rootfs), e riavviare, senza chiedere ogni volta. **Mai** bootloader,
  calibrazione, `efs`, `persist`, firmware del modem: non sono recuperabili da questo PC.
  Prima di scrivere si controlla l'identità del dispositivo (sullo stesso PC può esserci un
  altro telefono, `adb -s <seriale del tablet>`); si tiene la copia di rollback in `out/`
  (`out/lineage-recovery-before-mainline.img`, sha256 `81f4d19e…`, e `out/prev/`).
- **Un sottosistema alla volta**, una variabile per tentativo, e si dice cosa è stato scritto.
- **Fuori dal progetto non si opera da soli** dentro `/home`, `/etc`, `/root`, `/usr`
  (ad esempio la cartella personale del proprietario): serve un permesso esplicito, ogni
  volta. `rm -rf` e simili distruttivi contro quei percorsi mai senza un sì dato in quel
  momento. Vale anche per i test diagnostici.
- **Il repository non è coperto da quel permesso:** niente push, niente riscrittura della
  storia, niente foto o seriali pubblicati senza una richiesta. Le foto della console
  (`photo_*.jpg` nella root) restano locali, ignorate da git, e il loro testo va trascritto
  in `docs/CONSOLE-LOG.txt` con data e ora. Credenziali Wi-Fi e chiavi mai nel repository.
- **Mai nel repository:** password Wi-Fi, nome della rete di casa, indirizzi Bluetooth (del tablet e
  del telefono) e MAC dei gadget. La rete di casa e il telefono (un Pixel 10) sono del proprietario.
  Prima di ogni commit: `git diff --cached | grep -i -E 'psk|passw|[0-9A-F]{2}(:[0-9A-F]{2}){5}'`.
- **Codice:** non più di tre livelli di indentazione (early return, funzioni più piccole).
  Niente codice copiato da `pulpoff` (licenza non dichiarata, `docs/LICENSES.md`): è
  consultabile per ordine e parametri, non per testo.
- **Non leggere il journal di sistema del PC host** (un comando è già stato rifiutato).
- Il proprietario parla italiano e non è uno strumento di misura: non gli si chiedono
  frequenze o termini tecnici (se ne è lamentato). Per i suoni si chiede solo «si sente?» e
  «da dove?», per lo schermo cosa vede.

### Come si lavora sul tablet

- Cavo USB: il tablet è `172.16.42.1`; l'indirizzo del PC lo assegna il DHCP del tablet.
  `ssh -F /dev/null -i out/keys/gts4lv_ed25519 -o IdentitiesOnly=yes root@172.16.42.1`
  (la chiave è in `out/`, non in git). Se Arch non risponde, la shell dell'initramfs è su
  telnet, porta 23. Per tornare ad Android: `boot-android` sul tablet.
- Il clock parte dal 1977 (l'RTC del PMIC non è scrivibile) ma, con il Wi-Fi connesso,
  `systemd-timesyncd` lo imposta da NTP in una decina di secondi. Senza Wi-Fi:
  `date -u -s @$(date -u +%s)` dal PC prima di `pacman`, che passa dal proxy
  `scripts/usb-http-proxy.py` (`scripts/arch-smoke.sh <pacchetto>`); con il Wi-Fi `pacman` va diretto.
- **Wi-Fi, credenziali:** non stanno nel repository né nell'immagine. Sul tablet vivo sono in
  `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` (600, solo hash). Per rifarle su un'immagine
  nuova: `printf '%s\n' "$PASSWORD" | wpa_passphrase "$SSID" | sed '/#psk=/d'` dopo le righe
  `ctrl_interface=/run/wpa_supplicant`, `update_config=0`, `country=IT`, in quel file con
  `chmod 600`. La unit non va abilitata a mano: la avvia udev quando compare `wlan0`.
- `scripts/run-with-log.sh <dir> '<comando>' [secondi]`: esegue un comando sul tablet con
  `dmesg -w` in streaming sul PC; è lo strumento per ogni prova che può resettare. Il log
  che arriva è quello che resta (pstore non serve: il bootloader Samsung azzera la RAM).
- Kernel: `scripts/build-kernel.sh` (applica prima le patch di
  `device/gts4lvwifi/kernel/` con `scripts/apply-kernel-patches.sh`), poi
  `scripts/build-initramfs.sh` (confeziona la recovery), `scripts/verify-recovery.py`, e
  `scripts/flash-recovery-shell.sh --reboot` dal tablet vivo (scrive solo `recovery`, rilegge
  e confronta lo sha256). Con il sorgente patchato la release è `…-g36f309c07087-dirty`:
  prima di riavviare con un kernel di release nuova, `scripts/sync-modules.sh --stage` copia i
  moduli in `/usr/lib/modules/<release>`.
- Rootfs: `scripts/build-rootfs.sh` (Docker + qemu-user, circa 4 minuti) e
  `scripts/verify-rootfs.py`; `scripts/rootfs-to-tablet.sh` la scrive in `/data` da Lineage.
- Sul tablet (da `device/gts4lvwifi/rootfs/overlay/usr/local/sbin/`): `gts4lv-firmware`
  (espone `modem`, `apnhlos`, `vendor` in sola lettura sotto `/run/gts4lv-fw`),
  `gts4lv-modem` (modem e Wi-Fi, con marker anti-ciclo), `gts4lv-dsp` (modem/ADSP **per nome**:
  la numerazione dei `remoteproc` cambia tra un boot e l'altro), `gts4lv-tone` (tono di
  prova con i controlli di sicurezza), `gts4lv-audio` (`start|stop|status`: ADSP, protezione degli
  amplificatori, percorso e livello di lavoro), `gts4lv-display` (`start|kick|bars`), `boot-android`.

### Stato dei sottosistemi

| Sottosistema | Stato | Come lo so |
| --- | --- | --- |
| Avvio Arch dalla recovery, USB, ssh, rete | funziona | da giorni, molti riavvii |
| Wi-Fi (WCN3990) | **connesso** alla rete di casa del proprietario su 5 GHz, DHCP, internet (HTTPS 200), circa 60 Mbit/s in download, riconnessione ok, **si riconnette da solo dopo il riavvio** (ssh a 7 s, Wi-Fi a 25 s); l'ora si sincronizza via NTP | misurato; tenuta 5 ore |
| Bluetooth | `hci0`; telefono accoppiato e fidato; **la musica del telefono suona dagli altoparlanti del tablet** (A2DP sink via PipeWire); sulla v6 le chiavi non ci sono più (stavano nella vecchia immagine): **il telefono va riaccoppiato**; non provati: riconnessione dopo il riavvio, tablet come sorgente (cuffie) | proprietario |
| Modem DSP | stabile; parte da unit al boot | misurato |
| Batteria/ricarica (SM5705) | funziona | misurato |
| Tocco (FTS1BA90A) | driver nostro, interrupt da device tree; via `evtest`: 19.153 eventi, 173 contatti aperti e chiusi, fino a 4 dita insieme. Hyprland riceve il flusso completo; il mapping persistente del pannello DSI-1 usa `transform=3` | proprietario, `scripts/touch-summary.py`, cattura Hyprland |
| Display (`msm` + pannello) | **funziona**: barre SMPTE complete (foto del proprietario, girate di 90° perché il modo è orizzontale), nessuna cucitura visibile. Serve `handover=1` al driver del pannello e un ciclo DPMS spento/acceso dopo `msm` (`gts4lv-display start`). Luminosità (160, 100, 40, 255, 160) senza artefatti; refresh a circa 63 Hz con i fotogrammi in arrivo (29 Hz a riposo). Aperti: la console di testo non scrive su `msmdrmfb`, off/on da compositor, tearing | proprietario |
| GPU | **funziona**: Freedreno FD615, OpenGL 4.6 / ES 3.2 e Turnip Vulkan 1.3; nessun fallback software | `scripts/gpu-smoke.sh` |
| Audio, altoparlanti | **suona** con la protezione DSP caricata e nel percorso, via PipeWire; tutti e quattro producono suono; livello di lavoro 0 dB digitale e analogico 0 (scelto dal proprietario fra quattro fasi; più guadagno analogico suonava più piano); l'abbinamento amplificatore-altoparlante e sinistra/destra non sono stabiliti. Servono `gts4lv-audio start` e l'utente `alarm`; sulla v6 l'uscita predefinita di PipeWire è già gli altoparlanti (testato: tono sentito da tutti e quattro) | proprietario, registri I2C |
| Audio, codec interno (microfoni, cuffie) | **l'ADSP va in crash** a ogni uso del codec digitale interno, anche in riproduzione (AHB bus hang in `0x62…`); il clock vero `INTERNAL_DIGITAL_CODEC_CORE` è rifiutato dal firmware e fa sparire la scheda | misurato, 6 crash |
| ADSP | parte e si ferma pulito | misurato |
| Sensori SSC | **parziali**: servizi e catalogo partono al boot; luce VEML3328, magnetometro AK0991x e bussola scorrono. LSM6DSM enumera ma ripete un vettore di gravità fisso, quindi l'autorotazione è bloccata. Il modello Wi-Fi non pubblica prossimità | `ssccli`, D-Bus, due reboot |
| microSD, fotocamere, codec video in uso, sospensione | non provati | — |
| M8 (Omarchy) | immagine installata e avviata; Hyprland mobile, Quickshell e squeekboard girano sul pannello con GPU hardware e touch calibrato. Il display manager resta disabilitato durante il bring-up | misurato sul tablet |
| M9 (pacchetti/CI) | non iniziato | — |

### Cose che fanno male, imparate qui

- **Audio: mai suonare senza leggere il volume.** Un tono è uscito a 0 dB senza protezione
  perché `amixer sset … -60dB` ha letto `-60dB` come opzione; l'errore era buttato in
  `/dev/null`. La scala degli amplificatori: 817 = 0 dB, 497 = -40 dB, 337 = -60 dB
  (0,125 dB per passo, `cset`, non `sset`). Limite di `gts4lv-tone`: -12 dB (-24 senza DSP).
  Il proprietario ha chiesto il volume al massimo e non è stato fatto: vedi `docs/AUDIO-PLAN.md`.
- **L'ADSP non va lasciato acceso a un riavvio** (il bootloader entra in un ciclo fino a
  Power + Volume giù). `gts4lv-adsp-stop.service` lo ferma allo spegnimento. Dopo un crash
  il remoteproc lo riavvia da solo: aspettare lo stato `running` prima di fermarlo.
  Fermare l'ADSP scarica il driver `pinctrl_sdm670_lpass_lpi` (i registri tornano ai default):
  senza, solo la prima riproduzione di un boot funzionava.
- **Il Wi-Fi si resetta con il `board-2.bin` di linux-firmware** (`NoExtract` nell'immagine):
  usa il `bdwlan.bin` di Samsung.
- **Tocco: leggere la coda eventi a tempo (polling) con la scansione accesa ha resettato
  il tablet** in 3 prove su 4; con l'interrupt regge. Sulla v6 il modulo non è più in blacklist e
  si carica da solo al boot.
- `msm` non si scarica con `rmmod`; un riavvio riporta alla console `simpledrm`.
- Se `gts4lv-modem` trova `/var/lib/gts4lv/modem-attempt`, salta l'avvio: il tentativo
  precedente non è arrivato a `wlan0`. Va tolto a mano dopo aver capito perché.

- **Display:** il driver del pannello ha `handover` spento per default: senza `handover=1` il
  pannello viene resettato e resta nero. Dopo `msm` serve un ciclo DPMS (`gts4lv-display start`).
  `modetest -v` sfarfalla per costruzione: non serve a giudicare il pannello. Con `msm` caricato la
  console di testo non scrive: un riavvio la rimette.
- **Audio server:** PipeWire rifiuta di girare come root (gira per `alarm`); la scheda in Pro Audio ha
  8 canali «aux» e un flusso stereo non trova dove andare (regola di WirePlumber nell'immagine); il
  controllo della seat di WirePlumber impediva la registrazione degli endpoint A2DP (disattivato).
- **I numeri cambiano da un boot all'altro:** `remoteprocN` dell'ADSP e del modem, il bus I2C degli
  amplificatori (5, poi 4), le interfacce di rete. Gli script chiedono per nome o per indirizzo;
  non scrivere mai numeri a mano.
- **Livello degli altoparlanti:** i quattro amplificatori stanno a 0 dB digitale, analogico 0, solo con
  la protezione nel percorso; più guadagno analogico suonava più piano. Mai suonare senza leggere
  il volume (l'incidente dei 0 dB senza protezione è descritto in `docs/AUDIO-PLAN.md`).
- **Un'unit abilitata male può bloccare l'avvio:** `wpa_supplicant@wlan0` abilitata al boot teneva
  fermo `sshd` per 90 s; ora la avvia udev quando compare `wlan0`.

### Dove siamo, in pratica

- Il tablet esegue la **v6** (rootfs costruita la sera del 2026-11-05, `sha256 0a5c84c4…`, 80 extent), scritta
  da Lineage con `rootfs-to-tablet.sh` e verificata; la recovery è `a473ef0a…` (kernel `-dirty` con il
  driver del tocco; la ramdisk ha gli extent della v6). Dentro ci sono PipeWire, WirePlumber con le sue
  regole, `gts4lv-display`, `gts4lv-audio`, `gts4lv-tone`, il Wi-Fi con la unit avviata da udev, NTP, e il
  modulo del tocco non più in blacklist. Il **ritorno**: la vecchia immagine è sul tablet come
  `/data/lost+found/gts4lv/rootfs-v1.img` (non cancellarla finché serve) e la sua recovery è
  `out/prev/recovery-6afcfc5e-arch-v1.img` (vedi `docs/RECOVERY-RUNBOOK.md`, «3c»). `msm`, il pannello e
  il driver dei pin LPI non partono da soli (blacklist): `gts4lv-display start`, `gts4lv-audio start`.
  Lineage è ancora in `boot`.
- **Stato vivo del tablet nel momento del passaggio** (da verificare con `gts4lv-audio status`): Arch v6 acceso
  sul cavo USB, Wi-Fi connesso, e `gts4lv-audio start` già eseguito, quindi l'**ADSP è acceso**, gli
  amplificatori a 0 dB con la protezione nel percorso, PipeWire attivo per `alarm` con gli altoparlanti
  come uscita predefinita. Il telefono **non** è accoppiato. Prima di riavviare: un `systemctl reboot`
  normale fa fermare l'ADSP a `gts4lv-adsp-stop.service`; a mano è `gts4lv-audio stop` (dopo un crash
  aspettare circa 8 s). **Mai un reset a tasti con l'ADSP acceso**: il bootloader può ciclare fino a
  Power + Volume giù. Dopo ogni avvio di Arch ADSP, display e audio sono spenti: `gts4lv-display start`,
  `gts4lv-audio start`.
- Le credenziali Wi-Fi stanno **solo** sul tablet (`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`, 600,
  hash) e, copiate prima del cambio d'immagine, in `out/wifi-wlan0.conf` (locale, ignorato da git): una
  immagine nuova non le ha e vanno rimesse (ricetta nella sezione «Come si lavora»). Anche le chiavi
  del Bluetooth stavano nella vecchia immagine: **il telefono va riaccoppiato**.
- **Published, with the history rewritten twice** (2026-11-05 evening, at the owner's request). The
  branches `feat/gts4lvwifi-mainline-bringup` and `main` of `Lwb89dev/gts4lvwifi-porting` were taken
  through two rewrites: (1) the tablet's and the phone's Bluetooth addresses (the tablet's came from
  pulpoff's public device tree) were replaced by a placeholder in the 14 commits that were not yet public;
  (2) `PROCESS.md`, which holds semi-private details, was removed from every commit, because the owner
  asked for it to be off GitHub. The file is now untracked (`.gitignore`) and exists only on the owner's PC.
  The trees are identical apart from that file. **For whoever continues:** every commit hash on the
  remote differs from older notes and from older local copies; **never force-push old history back and
  never push the local backup refs** (`backup/before-bt-scrub-2026-11-05`, `refs/original/*`), which still
  hold the addresses and `PROCESS.md`; push one branch at a time (`git push origin <branch>`, never
  `--all` or `--mirror`); if a push is rejected as non-fast-forward, stop and ask the owner. GitHub may keep
  the old commits reachable by their hash for a while (there are no forks and no pull requests); only
  GitHub Support can purge them.

### Prossimi blocchi, in ordine

1. **A tablet in mano, per prima cosa:** `gts4lv-audio status`; riaccoppiare il telefono sulla v6 e provare
   la musica via Bluetooth, poi **riavviare e vedere se si riconnette da solo**; decidere con il
   proprietario se `gts4lv-audio` parte al boot (oggi no, per il rischio dell'ADSP acceso:
   `gts4lv-audio.service` esiste ma non è abilitata). L'immagine v6 è fatta (sezione in fondo).
2. **Microfoni** (M7.6): il codec digitale interno manda in crash l'ADSP a ogni uso (anche in
   riproduzione). Il clock vero è stato provato e rifiutato (`docs/AUDIO-PLAN.md`; idee che restano:
   l'albero di Samsung per capire come sono collegati i microfoni di questo tablet, l'indirizzo
   completo del blocco). Si lavora con `run-with-log.sh` e si aspetta circa 8 s prima di fermare l'ADSP.
3. **Bluetooth**: riconnessione del telefono dopo un riavvio, il tablet come sorgente (cuffie), HFP.
4. **Altoparlanti**: abbinamento amplificatore-altoparlante e sinistra/destra (meglio con un microfono
   o con uno stereo vero a tablet in orizzontale).
5. **Display**: console di testo su `msmdrmfb`, tearing, off/on da compositor, caricarlo al boot.
   **Tocco**: bordi sinistro e alto, rotazione, ripresa dopo lo spegnimento, libinput e compositor.
6. **microSD** (serve la scheda e un nodo `sdhc_2`), **sensori** (`hexagonrpcd`, `libssc`,
   `iio-sensor-proxy`; il canale FastRPC dell'ADSP c'è), **sospensione**, **fotocamere**, **codec video**.
7. M8 (Omarchy: da `docs/OMARCHY-PLAN.md`, con `mesa` e `vulkan-freedreno` di ALARM, non quelli di
   `[omamobile]`, che sono solo Mali) e M9 (pacchetti, CI).

Alcune frasi più vecchie sono superate da quello che segue. `README.md`,
`docs/HARDWARE-MATRIX.md` e `docs/PORTING-ROADMAP.md` sono stati allineati la sera del 2026-11-05;
`docs/AUDIT.md` e `device/gts4lvwifi/BRINGUP-M1.md` hanno un avviso di «superato». Vale questo file.

## Obiettivo

Portare Omarchy (Arch Linux ARM, Hyprland, kernel mainline) sul Samsung
Galaxy Tab S5e Wi-Fi, SM-T720 / SM-T720N, codename `gts4lvwifi`,
Snapdragon 670, Adreno 615, 4 GB, eMMC a slot singolo, AMOLED
2560×1600. Il modello LTE SM-T725 è un'altra scheda ed è fuori scope.

Il primo successo è una shell USB. Display, GPU e touch vengono dopo.
Arch e Omarchy non partono prima di quella shell.

## Vincoli tenuti

- La base del kernel è `pulpoff/linux-gts4lv`, Linux 7.2.13, pin
  `36f309c07087`. `derekross/linux-omarchy-mobile` è un albero Tensor
  (Pixel) e non si usa. Il kernel Samsung 4.9 di Lineage è solo
  riferimento, pin `a30605a54f3b`.
- `tools/install-phone` di Omarchy non si lancia. Scrive uno slot
  fastboot B. Questo tablet non ha slot A/B e lo storage è eMMC.
- Linux sta nella partizione `recovery`, come immagine Android boot
  header v1 (`Image.gz` con il DTB concatenato). Il `recovery_dtbo` di
  Lineage si riusa byte per byte. Il bootloader rifiuta un overlay che
  non applica.
- L'unica partizione scritta è `recovery`. `boot`, `dtbo`, `vbmeta`,
  `misc`, `userdata`, il bootloader e le calibrazioni non sono stati
  toccati. `/data` è ext4 con cifratura file-based (`fileencryption=ice`)
  e non è stato riformattato.
- Un flash o un riavvio sul tablet è avvenuto solo dopo un sì esplicito
  per quell'azione, fino al 2026-11-04. Da allora vale un'autorizzazione
  permanente del proprietario: «il tablet è throwaway, puoi scrivere
  tranquillamente». Vale per le scritture di prova (`recovery`, file in
  `/data`, flash con Heimdall). Per scelta di cautela restano fuori
  bootloader, calibrazioni, `efs`, `persist` e firmware del modem: non si
  recuperano e fermerebbero il progetto. Si continuano a fare il controllo
  d'identità prima di ogni scrittura (sullo stesso host può esserci anche il
  Galaxy S24, che non è di questo progetto) e la copia di rollback. Il
  firmware stock non è su questo disco. Il rollback noto è la copia di `recovery` presa prima del primo
  flash.
- Una modifica di sottosistema per tentativo. `sources.lock` non è
  stato spostato.
- Sull'host c'è anche un Galaxy S24 (SM-S921B, prodotto `e1s`; seriale
  omesso da questo file). Non è questo tablet e non va interrogato. Il seriale
  del Tab S5e è `R52M410RCVR`. `adb` senza seriale, con un solo device
  in lista, non è il tablet.
- La stringa di prodotto della Download mode è `SDM710` (`04e8:685d`,
  `bcdDevice 2.1b`, seriale vuoto). `usb.ids` etichetta quell'id come
  Galaxy S II: l'etichetta è sbagliata. Il riconoscimento giusto è
  `SDM710`.

## Macchina di build

HP OMEN 16, Pop!_OS 24.04, apt, non pacman. Il cross compiler delle
immagini da simpledrm in poi è `aarch64-linux-gnu-gcc` di Ubuntu
13.3.0-6ubuntu2~24.04.1, binutils 2.42, con `bc`, `bison`, `flex` e
`libssl-dev`. `shellcheck`, `dtc` di sistema e `dt-validate` non ci
sono, quindi `dtbs_check` non è stato eseguito. Il `dtc` del kernel ha
decompilato il DTB e ha confermato
`compatible = "samsung,gts4lvwifi", "qcom,sdm670"`.

La prima immagine flashata era stata compilata con il toolchain nolibc
GCC 15.3.0 di kernel.org, in `src/_toolchain` (gitignored). Quella
immagine non va riflashata. Le build successive usano il GCC della
distro. `scripts/build-kernel.sh` non fa `mrproper`: parte da
`defconfig`, poi fonde `arch/arm64/configs/sdm670.config`, poi
`device/gts4lvwifi/kernel.config`. Il file `.config.old` dopo una build
è il defconfig grezzo, prima di `olddefconfig`. Un diff contro
`.config` sembra un migliaio di opzioni cambiate e non è una regressione.
`CONFIG_PCI=n` è voluto in `sdm670.config`.

Heimdall non è un pacchetto apt installato. Il binario è
`src/_host/root/usr/bin/heimdall`, versione 2.0.2, estratto dal deb
`heimdall-flash` 2.0.2-2build2. `--no-reboot` lascia la Download mode.
Un comando successivo nella stessa sessione vuole `--resume`.

## Tablet misurato

Letto via adb il 2026-11-04, prima senza root (uid 2000), poi con debug
con root. `adb unroot` è stato eseguito alla fine di quelle letture.

| Fatto | Valore |
| --- | --- |
| Modello | SM-T720, `ro.product.device=gts4lvwifi`, `gts4lvwifixx` |
| Sistema | LineageOS `22.2-20260909-NIGHTLY-gts4lvwifi`, Android 15, userdebug |
| Kernel Android | `4.9.337-ga30605a54f3b`, lo stesso commit del tree Lineage fissato |
| SoC | `Qualcomm Technologies, Inc SDM670` |
| RAM | `MemTotal` 3735364 kB |
| Bootloader | `T720XXS2DUH1`, sbloccato: `verifiedbootstate=orange`, `flash.locked=0`, `warranty_bit=1` |
| Slot | `ro.boot.slot_suffix` vuoto |
| `/data` | ext4, `fileencryption=ice`, circa 49 GB di cui circa 29 GB liberi |
| eMMC | `soc/7c4000.sdhci`. La SD nell'fstab è `8804000.sdhci` |

| Nome | Nodo | Byte |
| --- | --- | --- |
| boot | mmcblk0p48 | 67108864 |
| recovery | mmcblk0p49 | 72744960 |
| dtbo | mmcblk0p47 | 8388608 |
| vbmeta | mmcblk0p23 | |
| misc | mmcblk0p34 | |
| system | mmcblk0p50 | 4932501504 |
| vendor | mmcblk0p51 | 939524096 |
| product | mmcblk0p52 | 629145600 |
| cache | mmcblk0p53 | 419430400 |
| userdata | mmcblk0p57 | 54951656960 |

`recovery` non è 64 MiB. 67108864 è `boot`, ed è anche il numero del
BoardConfig di Lineage. Il PIT chiama la partizione `RECOVERY`, id 49,
142080 blocchi da 512 byte, cioè 72744960. L'aritmetica `$(( ))` della
shell del tablet è a 32 bit e va in overflow su `system` e `userdata`.

Il backup di `recovery` non si fa con `adb exec-out dd`: una pagina è
tornata da 4171 byte, 75 in più. La copia giusta è `dd` sul device in
`/data/local/tmp`, poi `adb pull`, poi `cmp` della rilettura. I file
temporanei sono stati rimossi.

## Header

`boot` e `recovery` di Lineage sono header v1, pagina 4096, kernel
`0x8000`, ramdisk `0x02000000`, tags `0x01e00000`, second stage assente,
nome `SRPSA14B001`. `os_version` copiato dalla recovery viva è
`0x1e0001a8` (Android 15.0.0, patch 2026-08). Header 1648 byte. La
cmdline di Lineage include `androidboot.boot_devices=soc/7c4000.sdhci`.

`boot` non ha un recovery dtbo. La recovery di Lineage ne porta uno di
1305887 byte all'offset 29597696, identico ai primi 1305887 byte della
partizione `dtbo`. Salvato in
`device/gts4lvwifi/lineage-recovery-dtbo.img`, sha256
`bca502bdea00d1e629fb3b04f8a0734d0e4bb47b5ff220e6539f7abc33efe3f4`,
ed è in git. Le nostre immagini hanno un offset dtbo diverso perché
kernel e ramdisk hanno un'altra dimensione. I byte e la lunghezza del
dtbo coincidono. Il packer (`scripts/pack-recovery.py`) rifiuta pagina,
header, dtbo o dimensione sbagliati. La struct è quella di
`mobian/kit/mkbootimg.py` di pulpoff (`<8s10I16s512s32s1024sIQI`).

La cmdline in `device.conf` è
`console=tty0 fw_devlink.sync_state=timeout clk_ignore_unused pd_ignore_unused panic=10`.
`fw_devlink.sync_state=timeout` va tenuto: la GMU dell'Adreno non ha un
driver proprio. pulpoff usa anche `regulator_ignore_unused` e
`icc_ignore_unused`. Non sono stati aggiunti. Il suo README dice che
`icc` e `pd` ignore non servono in un boot normale, e che
`regulator_ignore_unused` servirà più avanti per il pannello perché
`msm` è un modulo.

## Cosa è stato costruito, sul PC

`scripts/fetch-sources.sh` ha scaricato i tree di `sources.lock` sotto
`src/` (gitignored, come `out/`).

| Tree | Commit | Ruolo |
| --- | --- | --- |
| pulpoff/linux-gts4lv | `36f309c0708764886b6528b9ef0603bb73cc4731` | Kernel e DTS della scheda |
| Lineage `android_device_samsung_gts4lvwifi` | `b54236c99ffb18aab2387833274cca7009c6c17c` | Prodotto Wi-Fi, `lineage-22.2` |
| Lineage `android_device_samsung_gts4lv-common` | `d1b339be7abea07f62fef2bee3b7a2006694df67` | Partizioni, header, fstab |
| Lineage `android_kernel_samsung_sdm670` | `a30605a54f3b92627d868f169c72ef9c6ef82123` | Solo DTS e defconfig del 4.9, sparse |
| derekross/omarchy-mobile | `e7ad2759cb73f4b6449234c94dbaf2428ac33cb9` | Riferimento userspace. L'installer non si usa |

Il device tree Lineage non è un DTS Linux. Il DTS mainline è
`arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dts`. Le label vuote
per l'overlay del bootloader stanno in
`sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`.

Release del kernel: `7.2.13-gts4lvwifi-g36f309c07087`
(`CONFIG_LOCALVERSION="-gts4lvwifi"`).

`device/gts4lvwifi/kernel.config`, sopra defconfig e `sdm670.config`:

- `CONFIG_DRM_SIMPLEDRM=m`. `CONFIG_DRM` resta `=m`, quindi simpledrm
  non può essere `=y`. `CONFIG_FB_SIMPLE` e
  `CONFIG_DRM_PANEL_SAMSUNG_ANA38401` restano spenti.
  `CONFIG_SYSFB_SIMPLEFB` è roba x86/EFI e non serve. Il framebuffer nel
  DTS è `framebuffer@9c000000`.
- `CONFIG_PSTORE_RAM=y` e `CONFIG_PSTORE_CONSOLE=y`. `ramoops` è in
  `modules.builtin`. Non c'è un `ramoops.ko`. La regione DTS è
  `ramoops@a1300000`, 1 MiB, record/console/ftrace/pmsg da `0x40000`,
  lo stesso layout del 4.9. Un taglio di corrente cancella il buffer.
- `CONFIG_I2C_GPIO` non è impostato. `CONFIG_I2C=y` e
  `CONFIG_I2C_CHARDEV=y` ci sono già. Il bus bit-banged non esiste.
- `CONFIG_PHY_QCOM_QUSB2` resta `=m`. Lo carica l'init, non è stato
  reso built-in.
- `CONFIG_USB_DWC3=y` e `CONFIG_USB_DWC3_QCOM=y`. Le funzioni gadget
  sono moduli.

L'initramfs (`device/gts4lvwifi/initramfs/init`, BusyBox 1.36.1,
sha256 del tarball
`b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314`,
link statico aarch64) è pid 1. Monta proc, sysfs, devtmpfs, devpts,
tmpfs e configfs. Non scrive l'eMMC, non riavvia, non tocca `misc`.
Il log è `echo "gts4lv-init: $*" > /dev/kmsg`.

Ordine di `insmod`, quello di `modules.dep`: `backlight`, `drm`,
`drm_kms_helper`, `drm_client_lib`, `drm_sysfb_helper`,
`drm_shmem_helper`, `simpledrm`, `phy-qcom-qusb2`, `libcomposite`,
`u_serial`, `usb_f_acm`, `u_ether`, `usb_f_ncm`, `usb_f_rndis`.
`phy-qcom-qusb2.ko` non ha dipendenze (27336 byte).

Poi il gadget configfs `g1`: VID `0x18d1`, PID `0xd001`, manufacturer
`Samsung`, product `gts4lvwifi first light`, attesa fino a 60 secondi
di un UDC, bind, log `gadget bound to $udc` oppure `no UDC`. Poi cerca
un bus I2C il cui `of_node` si chiama `i2c-charger` e lancia
`/usr/sbin/muic-usb`. Se il bus non c'è, logga `muic not switched`.
Poi `ip addr add 172.16.42.1/24 dev usb0`, udhcpd con un solo lease
`172.16.42.2`, telnetd su `172.16.42.1`, e un loop di shell su
`/dev/ttyGS0`.

`muic-usb` è C statico (`aarch64-linux-gnu-gcc -static -Os -s`). Fa
`I2C_SLAVE` e, se fallisce, `I2C_SLAVE_FORCE`, poi una write SMBus
byte-data: registro `0x13` (`MANSW1`), dato `0x24`, indirizzo `0x25`.
È lo stesso trasferimento di `i2cset -y BUS 0x25 0x13 0x24` nell'init
di pulpoff. Senza quella scrittura i D+/D- possono non arrivare al SoC.
Il nodo DTS `i2c-charger` è `i2c-gpio` (SDA gpio 43, SCL gpio 44). Il
commento dice che il MUIC è a `0x25`. Il figlio `charger@49` è il
caricatore, un altro indirizzo.

Come distinguere il nostro gadget da Android, quando l'host lo vede:

| Chi | Id | Segni |
| --- | --- | --- |
| Initramfs | `18d1:d001` | product `gts4lvwifi first light`, indirizzo `172.16.42.1` |
| Lineage ADB | a volte `18d1:d001` | `bcdDevice 4.09`, product `SAMSUNG_Android`, classe 255/66/1, seriale `R52M410RCVR` |
| Lineage MTP | `04e8:6860` | `bcdDevice 4.09`, product `SAMSUNG_Android` |
| Download mode | `04e8:685d` | product `SDM710`, `bcdDevice 2.1b` |

L'errore `/init: line 40: can't open /proc/device-tree/serial-number`
visto in foto è la shell che apre quel file. Il `2>/dev/null` sul
redir non copre l'apertura dell'input. Il seriale di fallback è la
stringa `gts4lvwifi`. È innocuo. Nel sorgente attuale quella riga si è
spostata (riga 43) perché è stato aggiunto `phy-qcom-qusb2`.

I test offline `python3 tests/test-pack-recovery.py`,
`scripts/verify-initramfs.sh` e `scripts/verify-recovery.py` sono
passati sull'immagine PHY: initramfs 1861108 byte, recovery 16736256
byte, kernel concatenato 13559645, ramdisk 1861108. Il workflow
`.github/workflows/kernel.yml` è invariato: dispatch manuale, solo
`Image.gz` e DTB, senza moduli.

## Immagini

Il kernel dentro l'immagine PHY e dentro quella ramoops è lo stesso.
Il DTB non è cambiato da simpledrm in poi.

| File | Byte | sha256 |
| --- | --- | --- |
| Image.gz (ramoops e PHY) | 13458503 | `efcf82d92cbee39558ff019254346bca54f3fed0dbb50e760ba5379c4f5673e8` |
| DTB | 101142 | `e496d21301ce3306f11a9bc0092e457b04ab585016c71dc97b19c22fb13e1212` |
| Image.gz-dtb | 13559645 | `997d6d975c2f43c17eaca0ab8cb100473c6aae36a3e58f761393efb1badaf8c9` |

Questa tabella e le due sopra riguardano l'immagine PHY, quella oggi in
`recovery`. L'immagine I2C_GPIO, più recente e non flashata, è nella
sezione dedicata più sotto. Il manifest descriveva l'immagine PHY:

| File | Byte | sha256 |
| --- | --- | --- |
| recovery.img | 16736256 | `cf1703154e13732b5040714980438527632ea75f7ec09106bd7c84d753c0d864` |
| initramfs.cpio.gz | 1861108 | `812e1aae8b0cd2c0cce0e4ea186f8c3d78b29fcaab7d76d5f40c78478e93a5c5` |

Conteggio `dd` di rilettura, se un giorno si rilegge da Android:
`16736256 / 4096 = 4086`. Questa immagine è stata scritta da Download
mode con Heimdall `--no-reboot`. Non è stata riletta byte per byte:
in Download mode non c'è `dd`. Il boot della seconda foto è quello di
questa immagine, perché solo il suo init stampa `gadget bound`.

Immagini precedenti, da non confondere con il file attuale:

| Immagine | Byte | sha256 | Esito |
| --- | --- | --- | --- |
| GCC 15.3.0 nolibc | 15839232 | `ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7` | Schermo nero, niente USB. Non riflashare |
| simpledrm, GCC distro, pstore ancora modulo | 16715776 | `71e09d2993306753e0ce4ebafb27b4fd83cc1e195438dd25dc7b4b55f3c2477a` | Rilettura ok, niente USB. Initramfs `ad9acb6670ffb3e05d5dbd592f874ad4c8b4b92588ba8a958c6e3f421badfedf` (1855221). Image.gz `35404e2b0f4d439d424edde353d4aeff34131637588d4acf40eecf05242b8426` (13447162). Image.gz-dtb `ca07119d914b06b89167f262ef94978716ef078190886f17aedfb8d1cafd76bd` (13548304). DTB già quello sopra |
| ramoops built-in | 16728064 | `d57f386497b67aec1de7a4386a5cd9a84e89d737763a3d9bd14ab77709fccb11` | Terminale, poi spegnimento. Initramfs `b60c769fb5e1ac5387d884f9f8d28af7a7cc1580946a3e208082d3171b63ea12` (1855217). Rilettura 4084 pagine |
| Copia Lineage, rollback | 72744960 | `81f4d19e4d9d3ba37c2044d57b77c72f01487dbaaa3a24173b14bacc161b14a7` | `out/lineage-recovery-before-mainline.img`, gitignored, magic `ANDROID!` |

## Cronologia sul tablet

1. Misure adb e backup di `recovery`, senza scrivere. La copia è il
   file di rollback qui sopra.

2. Primo flash, immagine GCC 15. Scritta solo in `recovery` mentre
   girava Lineage. La rilettura coincideva. `misc` era vuoto.
   `adb reboot recovery` alle 14:01. Schermo nero. Il host ha visto la
   disconnessione USB alle 14:01:43 e poi nessun `04e8` e nessun
   `18d1`. Download mode `04e8:685d`. Heimdall ha riscritto l'intera
   copia da 72744960 byte sulla partizione PIT `RECOVERY` e ha
   riavviato. Il boot successivo era Lineage: `uname -r` =
   `4.9.337-ga30605a54f3b`, `sys.boot_completed=1`, header di recovery
   uguale al backup, `misc` vuoto. adbd è tornato a uid 2000. Un
   `18d1:d001` visto dopo quel ripristino era ancora Android
   (`bcdDevice 4.09`, `SAMSUNG_Android`), non l'initramfs. Nessun
   `uname` mainline.

3. Seconda immagine, simpledrm con il GCC della distro. simpledrm e le
   dipendenze DRM entrano nell'initramfs prima del gadget. Scritta solo
   in `recovery`, rilettura coincidente, `boot` intatto, `misc` vuoto.
   `adb reboot recovery` alle 19:50:41. `04e8:6860` è caduto alle
   19:50:43. Per 90 secondi nessun `04e8` e nessun `18d1`.
   `172.16.42.1` non ha risposto. Il host non vede il pannello.
   Download mode di nuovo. Heimdall ha rimesso la stessa copia Lineage
   e ha riavviato. Verifica dopo il «riavviato e pronto»: stesso
   kernel 4.9, `boot_completed=1`, recovery identica al backup, magic
   `ANDROID!`, `misc` vuoto, adbd uid 2000.

4. Terza immagine, `CONFIG_PSTORE_RAM=y` e `CONFIG_PSTORE_CONSOLE=y`.
   Le due immagini già flashate avevano il pstore a modulo, quindi
   ramoops non si attaccava prima di init e la console era persa.
   Questa è stata scritta con `dd` mentre girava Lineage. 4084 pagine
   rilette e confrontate. `adb reboot recovery` non è stato usato:
   quel comando scrive `boot-recovery` in `misc` e, se il kernel si
   pianta, il bootloader rientra nella recovery rotta. Avvio manuale
   con Volume su + Power. È comparso un terminale nero, poi il tablet
   si è spento del tutto. L'ultima enumerazione Lineage era alle
   20:22:38 (`04e8:6860`, `bcdDevice 4.09`, seriale `R52M410RCVR`).
   Quella porta è caduta alle 20:30:14 e non è tornato `18d1:d001`.
   Lo spegnimento completo cancella ramoops. Il log di quel boot non
   è in `/sys/fs/pstore`.

5. Dopo quel boot il tablet è sembrato in bootloop. Il DTS lo spiega.
   `&pon` ha `qcom,hard-reset-restart` (l'ABL può bloccarsi su un reset
   tiepido; il reset duro è voluto). `mode-normal` e `mode-recovery`
   sono `0x01` (RECOVERY). `mode-android` è `0x14`, che avvia `boot`
   cioè Lineage. Un reboot chiesto dal kernel riparte quindi in
   recovery e sembra un loop finché un reset da tasti o la Download
   mode non puliscono il registro. Il commento nel DTS lo scrive per
   il 2026-10-27 sul tablet di pulpoff. Download mode, poi la stessa
   immagine ramoops (`d57f3864…`) è stata riscritta con Heimdall
   `--no-reboot`. Non è stato rimesso il backup Lineage. Il device in
   Download mode era `04e8:685d`, product `SDM710`, bus 003. Il Galaxy
   S24 è rimasto in MTP e non è stato indirizzato. Il tablet è rimasto
   in Download mode dopo l'upload.

6. Foto `photo_2026-11-04_20-40-21.jpg` di quel boot. Righe lette:

   - `gts4lv-init: up, kernel 7.2.13-gts4lvwifi-g36f309c07087` circa a 1,06 s
   - `clk: Not disabling unused clocks` e `PM: genpd: Not disabling unused power domains`
   - `mmc0` su `7c4000.mmc`, HS400, `mmcblk0` `DH6DAB` 58,2 GiB, partizioni fino a `p56`, `boot0`/`boot1` da 4 MiB, `rpmb` da 16 MiB
   - `[drm] Initialized simpledrm 1.0.0 for chosen/framebuffer@9c000000` e un framebuffer a colori 320×100
   - `/init: line 40: can't open /proc/device-tree/serial-number`
   - `platform a600000.usb: deferred probe pending: dwc3: failed to initialize core` circa a 11,26 s
   - poi `Timed out, forcing sync_state()` da `gcc`, `qnoc-sdm670`, `gpucc`, `videocc`, `disp_cc` e `qcom-rpmhpd`
   - `random: crng init done` circa a 23,4 s

   Nessun `Kernel panic`. Il nome `gcc-sdm845` nei timeout è il driver
   che sdm670 riusa. Con `fw_devlink.sync_state=timeout` quei timeout
   sono attesi. Il kernel era ancora vivo a 23 secondi. L'eMMC funziona.
   simpledrm dimostra che il bootloader salta nel kernel e che il
   framebuffer scelto dal bootloader è vivo. L'indirizzo `a600000.usb`
   nel log è il figlio `snps,dwc3`. Il glue è `usb@a6f8800`.

7. Causa del deferral. `dwc3` è built-in. `CONFIG_PHY_QCOM_QUSB2=m` e
   quel modulo non era nell'initramfs. `_of_phy_get` torna
   `-EPROBE_DEFER` se il provider non c'è. `dwc3_core_init` propaga
   quell'errore e il chiamante lo sostituisce con
   `failed to initialize core`. `dev_err_probe` conserva la ragione
   solo per `-EPROBE_DEFER` e ci mette davanti il nome del driver, da
   cui la stringa `dwc3: failed to initialize core`. Il nodo USB nel
   DTS: `&usb_1_hsphy` con `vreg_l1b_0p925`, `vreg_l10a_1p8`,
   `vreg_l7b_3p125`; `&usb_1` con `qcom,select-utmi-as-pipe-clk`;
   `&usb_1_dwc3` con `dr_mode = "otg"`, `usb-role-switch`,
   `role-switch-default-mode = "peripheral"`, solo il PHY usb2,
   `maximum-speed = "high-speed"`. Il dtsi del Pixel 3a usa
   `dr_mode = "peripheral"`. Non è stato cambiato nello stesso passo.
   L'nvmem qusb2 è la cella qfprom `hstx-trim@1eb`. Una cella assente
   non fa fallire il probe.

8. Quarto flash, solo l'initramfs cambiato: `phy-qcom-qusb2` entra dopo
   simpledrm e prima del gadget. Il kernel è lo stesso della ramoops.
   Autorizzato con il tablet già in Download mode («procedi»). Heimdall
   `--no-reboot` ha scritto `cf170315…` su `RECOVERY`. L'unico device
   di Download mode era `04e8:685d` product `SDM710`. Uscita dalla
   Download mode alle 20:58:15. Per 90 secondi il host non ha visto
   `18d1:d001` e il journal non ha una nuova enumerazione. Alle 21:00:39
   non c'era nessun id USB Samsung.

9. Foto `photo_2026-11-04_21-00-39.jpg` di quel boot. Righe lette:

   - `gts4lv-init: up, kernel 7.2.13-gts4lvwifi-g36f309c07087`
   - `gts4lv-init: gadget bound to a600000.usb`
   - `gts4lv-init: muic not switched`
   - `gts4lv-init: usb0 172.16.42.1`
   - `gts4lv-init: telnet 172.16.42.1`

   Il controller è salito. Il gadget è legato. Dentro il tablet
   l'indirizzo e telnet sono configurati. Il MUIC non ha ricevuto
   `MANSW1=0x24`, quindi i D+/D- non sono stati portati al SoC e il
   host non può vedere `18d1:d001`. Non è un flash fallito.

## Perché l'USB si ferma qui

`CONFIG_I2C_GPIO` è spento. Senza quel driver il nodo `i2c-charger` non
viene creato, init non trova il bus e stampa `muic not switched`.
`muic-usb` non ha dove scrivere. Il prossimo cambiamento, e solo
quello, è `CONFIG_I2C_GPIO=y` nel fragment, built-in e non modulo:
init cerca il bus subito, intorno al secondo di boot, e un modulo non
sarebbe ancora caricato. Questa opzione cambia `Image.gz`. Non è un
rebuild del solo initramfs. Non è stato fatto. Non si cambia nello
stesso passo `dr_mode`, la cmdline, il pannello o
`CONFIG_DRM_PANEL_SAMSUNG_ANA38401`.

Il successo, quando quell'immagine verrà avviata, è sul host:
`lsusb` con `18d1:d001` e product `gts4lvwifi first light`, poi ping e
telnet a `172.16.42.1`. Si flasha solo con un sì nuovo e con la
Download mode confermata come `SDM710`.

## Stato adesso

- In `recovery` c'è l'immagine I2C_GPIO `63028e49…`, scritta con Heimdall
  alle 21:15:55 e avviata: prima shell raggiunta (sezione sopra). La
  partizione non è stata riletta.
- `boot` contiene ancora Lineage. Non è mai stata scritta.
- Dopo i due rollback verificati il sistema vivo era Lineage 22.2,
  kernel `4.9.337-ga30605a54f3b`. L'ultimo contenuto scritto in
  `recovery`, dopo quei rollback, non è la copia Lineage: prima
  l'immagine PHY, adesso l'immagine I2C_GPIO.
- L'ultima osservazione USB dell'host, alle 21:18:37, è `18d1:d001` con
  product `gts4lvwifi first light`. La foto delle 21:19:18 mostra
  `muic usb on i2c-1`. Poi il tablet è stato riportato a Lineage (21:35,
  vedi «M5 chiuso»): adesso è su Lineage 22.2.
- M0 (audit e host) è fatto. M1 (artefatti kernel) è fatto offline, e
  il kernel è arrivato al framebuffer sul tablet. M2 e M3 sono
  verificati offline e parzialmente sul device: simpledrm, eMMC e UDC
  ci sono. M4 è il runbook. M5: passato. Shell sull'host (telnet su `172.16.42.1`, `uname`, `dmesg`,
  DT letti) e ritorno a Lineage verificato alle 21:36 (vedi sezione
  «M5 chiuso»). Il tablet è su Lineage 22.2, kernel 4.9.337. M6–M9
  (rootfs Arch, hardware completo, Omarchy, CI di distribuzione) non
  sono iniziati.
- Avere un driver nel config non è una prova che l'hardware funzioni.
  Quello che è stato visto sul pannello di questo tablet è simpledrm
  sul framebuffer del bootloader, l'eMMC, e il bind del gadget. Il
  README di pulpoff elenca, sul suo SM-T720, display ANA38401, Adreno
  615, touch FTS1BA90A, WCN3990, quattro CS35L41, gauge SM5705,
  camere, Venus, sensori ADSP, USB gadget e host, s2idle. Sono fatti
  suoi, non misure nostre.

## Rollback

Se un avvio non torna una shell e serve Lineage:

1. Spegnere tenendo Power e Volume giù finché resta spento. Per
   conservare ramoops non si tiene la combo fino allo spegnimento: si
   lascia al reset. Un taglio completo cancella `0xa1300000`.
2. Download mode: Volume su + Volume giù, inserire l'USB, confermare
   con Volume su. Controllare `04e8:685d` e product `SDM710`.
3. Heimdall 2.0.2 scrive
   `out/lineage-recovery-before-mainline.img` sulla partizione
   `RECOVERY` e nient'altro. Un reboot di Heimdall dopo un ripristino
   è già finito in `boot` (Lineage), non in recovery.
4. Per entrare nella nostra recovery: da spento, Volume su + Power.
   Non `adb reboot recovery`.

La sezione 4 del runbook dice come leggere `/sys/fs/pstore` da Lineage
dopo un reset tiepido, solo per un'immagine con pstore built-in. Le
due immagini di inizio giornata non lo avevano. Le foto hanno sostituito
il log perso nello spegnimento.

## Git

`main` è fermo a `ab68c98` (handoff iniziale). Il lavoro di bring-up
è su `feat/gts4lvwifi-mainline-bringup`, pushato, senza force:

| Commit | Cosa registra |
| --- | --- |
| `8347e41` | Scheletro del repo |
| `d50b4d7` | Mappa partizioni misurata |
| `de3b5f2` | Dimensione vera di recovery e il suo dtbo |
| `ab68c98` | Handoff, su `main` |
| `09bf582` | Percorso recovery offline e il primo boot fallito |
| `12b43e9` | Ignora il bytecode Python |
| `a977cec` | simpledrm nell'initramfs, prima del gadget |
| `b528fe8` | Secondo boot: immagine simpledrm, niente USB |
| `e9291d0` | Ripristino Lineage dopo quel boot |
| `8038943` | ramoops built-in |
| `1fb11c4` | Scrittura della recovery ramoops, prima del boot manuale |
| `fc12d08` | Terminale visto, poi spegnimento |
| `505c380` | Riscrittura della stessa immagine da Download mode |
| `69ab7f2` | Prima foto: init partito, dwc3 no |
| `98fa3ab` | PHY USB2 caricato prima del gadget |
| `875c90e` | Seconda foto: gadget legato, bus MUIC assente |

`PROMPT.md` e questo `PROGRESS.md` sono in git dal 2026-11-04 (su richiesta
del proprietario). Le foto della console (`photo_*.jpg` nel root: si vede
anche la stanza e una mano) sono ignorate da `.gitignore` dal 2026-11-04 e il
loro testo è trascritto e datato in `docs/CONSOLE-LOG.txt`. Per un periodo due
commit locali le contenevano nella storia; il 2026-11-05, prima del primo push
e su richiesta di pubblicare, sono stati tolti dalla storia **locale non
pubblicata** con `git filter-branch` (nessun push forzato, nulla di già
pubblico toccato). Gli hash dei commit da quel punto in poi sono cambiati; il
ramo `backup/pre-push-2026-11-05` conserva la versione precedente, solo in
locale. Le foto non sono mai state su GitHub. `.gitignore` copre anche `src/`,
`out/` e `__pycache__`. Non si committano dump di partizioni,
firmware, dump di seriali, MAC.

## Immagine I2C_GPIO, costruita e non flashata

`CONFIG_I2C_GPIO=y` è in `device/gts4lvwifi/kernel.config`. Build del
kernel con il GCC della distro, nessun warning, `.config` finale con
`CONFIG_I2C_GPIO=y`, `i2c_gpio_probe` in `System.map`. Il DTB è identico
(`e496d213…`). Il contenuto estratto dell'initramfs è identico a quello
dell'immagine PHY (il file `.cpio.gz` ha un hash diverso solo per mtime e
compressione). Cambia solo `Image.gz`.

| File | Byte | sha256 |
| --- | --- | --- |
| Image.gz | 13463509 | `54628c696d9725ec7274ca8eab902befea539628046fcc16ba30033d8b3cec89` |
| Image.gz-dtb | 13564651 | `9cb75ad0ca8e31c5b253632cce534dc7d98edb03a4a881b3bb96060eced4b52e` |
| initramfs.cpio.gz | 1861094 | `380b5224f36e97402a532b512ba498a1f45bc658b9cf10b094fd07ec518d456d` |
| recovery.img | 16740352 | `63028e49dcf8c2f414223f961ac0d6f8b1e488bef28aa11544da336fca61e18e` |

Conteggio `dd` di rilettura: `16740352 / 4096 = 4087`. Il manifest
`out/MANIFEST.sha256` ora descrive questa immagine. L'immagine PHY
`cf170315…` (e i suoi `Image.gz` e initramfs) sono copiati in `out/prev/`.
Test passati offline: `tests/test-pack-recovery.py`,
`scripts/verify-initramfs.sh`, `scripts/verify-recovery.py`.

Nota aperta: il `sdm670.config` di pulpoff ha `CONFIG_I2C_GPIO=n` e
`defconfig` ha `=m`, ma il suo `mobian/kit/init` cerca lo stesso il bus
`i2c-charger`. Non so spiegarlo dal solo albero. Il fatto misurato è la
foto: `muic not switched` con questa opzione spenta.

## Quinto flash: immagine I2C_GPIO scritta, non ancora avviata

Autorizzato con il tablet già in Download mode («procedi pure»). Prima
della scrittura: unico id Samsung sull'host `04e8:685d`, product `SDM710`,
`bcdDevice 2.1b`, `heimdall detect` ok, file di rollback con sha256
`81f4d19e…` e magic `ANDROID!`, immagine con sha256 `63028e49…`. Comando:
`heimdall flash --RECOVERY out/recovery.img --no-reboot` (Heimdall 2.0.2).
Esito: `RECOVERY upload successful`, exit 0, 21:15:55–21:16:00, solo
`RECOVERY`. Non riletta (in Download mode non c'è `dd`). Il tablet è
rimasto in Download mode. Log in `out/heimdall-i2cgpio-flash.log`; il
monitor USB dell'host scrive in `out/usb-watch-i2cgpio.log`.

## Prima shell Linux sul tablet (M5, primo risultato)

Il tablet è uscito dalla Download mode alle 21:18:18 (nessun id USB) e a
21:18:37 l'host ha visto `18d1:d001`, product `gts4lvwifi first light`,
`bcdDevice 7.02`, funzioni NCM, RNDIS e ACM. La foto
`photo_2026-11-04_21-19-18.jpg` mostra `gadget bound to a600000.usb`,
`muic usb on i2c-1` (a 1,343 s), `usb0 172.16.42.1`, `telnet 172.16.42.1`,
poi i `Timed out. Forcing sync_state()` attesi a 11,77 s. Nessun panic.
`i2c-gpio` ha creato `i2c-charger` a 0,977 s (linee 580/581). È la prima
volta che `muic not switched` non compare: la causa era
`CONFIG_I2C_GPIO`, come previsto.

Sull'host l'interfaccia USB `enx…` (nome derivato dal MAC casuale del gadget, omesso) ha preso
`172.16.42.2/24` dal nostro udhcpd.
`ping 172.16.42.1`: 3 su 3, 2,4–4,0 ms. La prima connessione alla porta 23
è andata in timeout, le successive (nc e telnet) sono riuscite. Shell via
telnet, solo comandi di lettura, log in `out/first-shell-*.log`:

- `uname -a`: `Linux (none) 7.2.13-gts4lvwifi-g36f309c07087 #5 SMP PREEMPT
  Wed Nov 4 21:13:27 CET 2026 aarch64`. È la build I2C_GPIO.
- 8 CPU: 6 con `CPU part 0x803` e 2 con `0x802` (Kryo 360), MemTotal
  3635968 kB.
- Mount: solo `rootfs`, proc, sysfs, devtmpfs, devpts, tmpfs, configfs.
  Nessuna partizione Android montata. `/sys/fs/pstore` vuoto.
- Moduli caricati: solo quelli dell'init (DRM/simpledrm, `phy_qcom_qusb2`,
  libcomposite e le funzioni gadget).
- Classi: `drm` con `card0` (simpledrm), `input` con solo `gpio-keys`,
  nessun `power_supply`, `udc` `a600000.usb` con `usb_role`.
- Temperature 30,2–31,4 °C, `loadavg` 0,12.

Identificazione del Device Tree. Il DT in esecuzione ha i nodi del nostro
DTS (`i2c-charger`, `i2c-fuelgauge`, `i2c-usbpd`, `masked-devices`), ma
`model` è `Samsung GTS4LVWIFI PROJECT (board-id,05)`, `compatible` è
`qcom,sdm670-mtp qcom,sdm670 qcom,mtp`, `qcom,msm-id` è `0x150 0`,
`qcom,board-id` è `8 5`. Il nostro DTB ha `compatible =
"samsung,gts4lvwifi", "qcom,sdm670"`. Spiegazione compatibile con i fatti:
l'overlay `recovery_dtbo` che il bootloader applica riscrive le proprietà
radice. Verificato sul file: la tabella DTBO (magic `0xd7b7ab1e`) ha 6
voci. La voce 3 ha `model "Samsung GTS4LVWIFI PROJECT (board-id,05)"`,
`compatible "qcom,sdm670-mtp", "qcom,sdm670", "qcom,mtp"` e
`qcom,board-id <0x08 0x05>`. La cmdline del boot ha
`androidboot.dtbo_idx=3`: il bootloader ha scelto quella voce e le sue
proprietà radice sono quelle lette dal vivo. I suoi frammenti riguardano
nodi del 4.9 (`qcom,qpnp-smb2`, `qcom,fg-gen3`, `qcom,qpnp-wled` e simili),
che il DTS mainline copre con le label vuote di
`sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`. Conseguenza pratica: la
userspace non può riconoscere la scheda dal `compatible` di
`/proc/device-tree`; il `model` col board-id e `androidboot.em.model=SM-T720`
sulla cmdline sono i segni disponibili.

Rilettura e `misc`, dalla shell, in sola lettura (`out/first-shell-emmc.log`).
I nomi e le dimensioni delle partizioni viste da Linux coincidono con la
mappa misurata da Android (`vbmeta` p23, `misc` p34, `dtbo` p47, `boot`
p48, `recovery` p49, `system` p50, `userdata` p57). La rilettura di
`/dev/mmcblk0p49`, 4087 pagine da 4096, ha sha256
`63028e49dcf8c2f414223f961ac0d6f8b1e488bef28aa11544da336fca61e18e`, uguale
a `out/recovery.img`: la scrittura Heimdall è arrivata integra. Questo
chiude il buco lasciato dalle immagini precedenti, che in Download mode
non si potevano rileggere. `misc` è tutto zero nel primo blocco da 4 KiB.
Stato USB `configured`, ruolo `device`.

Dal `dmesg` (508 righe): `[Firmware Bug]: Kernel image misaligned at boot`,
`psci: failed to set PC mode: -3` e `WARNING: x1-x3 nonzero in violation of
boot protocol` sono del bootloader e non hanno fermato il boot. ramoops
(`0xa1300000`, 1 MiB) si registra a 0,17 s. Gli errori `could not get
#gpio-cells` riguardano i nodi sotto `masked-devices`.

Il telnet su `usb0` non ha autenticazione: va bene per il bring-up su un
cavo, non oltre. (Quando questa sezione è stata scritta il ritorno a
Lineage non era ancora stato eseguito: vedi «M5 chiuso» più sotto.)

## Il reset a tasti non riporta a Lineage

Alle 21:29:04 il proprietario ha fatto un reset con Power + Volume giù.
L'host ha perso l'USB alle 21:29:04–05 e alle 21:29:50 è tornato il nostro
gadget (`18d1:d001`, `uptime` 48 s alla lettura successiva). Il bootloader
ha rientrato nella nostra recovery (`androidboot.boot_recovery=1`, voce
DTBO 3), non in `boot`. `misc` era vuoto prima e dopo. Quindi l'ipotesi
scritta nel runbook («con `misc` vuoto un reset a tasti entra in `boot`») è
**smentita** da questo caso. Il perché non è provato: o il registro PMIC dei
motivi di riavvio ha ancora `RECOVERY` (0x01) da un riavvio precedente, o
un tasto era premuto al reset. `/sys/fs/pstore` è vuoto anche dopo aver
montato `pstore` a mano (l'initramfs non lo monta): un reset duro toglie
corrente alla DRAM, quindi il log del boot precedente non c'è.

Causa trovata nell'initramfs: `CONFIG_POWER_RESET_QCOM_PON=m` e il modulo
`qcom-pon` non è caricato dall'init. Senza di lui `/sys/class/reboot-mode`
è vuoto, un `reboot android` non scrive nessun motivo in
`PON_SOFT_RB_SPARE` (0x8f), e prima di un restart il PS_HOLD non viene
portato a hard reset. Il commento del driver dice che l'ABL Samsung di
questo tablet può bloccarsi su un reset tiepido. Il DT ha `mode-android =
0x14` (`NORMALBOOT`, avvia `boot`). Verificato dal vivo: caricando
`qcom-pon` a mano (modulo senza dipendenze, 10696 byte, sha256
`c22dfe9c842dc83213fa4af7d33b091c25c660133ae23b56cab659df23f22bf9`)
compare `/sys/class/reboot-mode/qcom-pon` e anche gli input
`pm8941_pwrkey` e `pm8941_resin`. Il modulo e uno strumento `rebootmode`
(reboot(2) con comando, statico, 597944 byte) sono stati copiati con `nc`
solo in `/tmp` del tablet, cioè in RAM. Da fare in modo permanente: far
caricare `qcom-pon` all'init e includere `rebootmode` nell'initramfs.

## M5 chiuso: ritorno a Lineage verificato

Con un sì esplicito del proprietario, dalla shell con `qcom-pon` già
caricato in RAM e controlli passati (`/sys/class/reboot-mode/qcom-pon`
presente, `misc` a zero), alle 21:35:20 è stato lanciato
`/tmp/rebootmode android`. Cronologia dell'host
(`out/usb-watch-return.log`): 21:35:20 il gadget cade, 21:35:21 nessun id,
21:35:57 `04e8:6860` `SAMSUNG_Android` `bcdDevice 4.09`. Con
`adb -s R52M410RCVR` alle 21:36:23:

| Controllo | Valore |
| --- | --- |
| `sys.boot_completed` | `1` |
| Modello / device | `SM-T720` / `gts4lvwifi` |
| Sistema | `22.2-20260909-NIGHTLY-gts4lvwifi`, Android 15 |
| `uname -r` | `4.9.337-ga30605a54f3b` |
| `ro.boot.boot_recovery` | `0` (era `1` nel nostro boot) |
| Bootloader | `T720XXS2DUH1`, `verifiedbootstate=orange`, `warranty_bit=1` |
| adbd | `uid=2000(shell)`, non root |

`/proc/cmdline` non è leggibile dall'utente shell su questa build: un
primo controllo con `grep` su quel file dava un falso zero e non conta. Il
riscontro valido sono le proprietà `ro.boot.*`. Nessuna partizione scritta
in questo passo. Il percorso è in `docs/RECOVERY-RUNBOOK.md`, sezione 3b.

Stato di M5 secondo `PROMPT.md`: shell reale con `uname`, `dmesg` e DT
letti, `boot` mai scritta, ritorno a Lineage verificato. **Passato.**
Limiti: il ritorno è stato provato solo con il modulo `qcom-pon` copiato a
mano in RAM, perché l'init attuale non lo carica; e in `recovery` c'è
ancora la nostra immagine, non quella di Lineage.

## Sesto flash: qcom-pon e boot-android nell'initramfs, passato

Autorizzato dal proprietario («hai il mio sì a procedere» sui quattro passi
proposti: init permanente, ricostruzione e verifiche, scrittura, avvio di
M6). Commit `307cd5a`. Cambia solo l'initramfs, il kernel e il DTB sono
quelli dell'immagine I2C_GPIO (`54628c69…`, `e496d213…`). Differenze
rispetto all'initramfs precedente, verificate estraendolo: `init` (blocco
`insmod qcom-pon.ko` dopo `log "telnet …"`, così il percorso USB già
dimostrato non cambia), `lib/modules/qcom-pon.ko`, `usr/sbin/rebootmode`
(da `rebootmode.c`, compilato con `-Wall -Wextra`, stesso binario
`20e4832e…` già provato) e `usr/sbin/boot-android` (rifiuta se
`/sys/class/reboot-mode/qcom-pon` manca o se `misc` non è vuoto, poi
`rebootmode android`).

| File | Byte | sha256 |
| --- | --- | --- |
| initramfs.cpio.gz | 2129613 | `1143385f1f46b58848bd79f23b63b68e024a00d1fb53019d6927784464a138b4` |
| recovery.img | 17006592 | `4908aecf34eaec7a5f3374f8b3f6e91d4125b101ecd425c5d52a97dc4930d4a5` |

Offline: `tests/test-pack-recovery.py`, `scripts/verify-initramfs.sh`
(esteso: nuovi file, `qcom-pon` dopo il telnet) e `scripts/verify-recovery.py`
passano. Conteggio `dd`: `17006592 / 4096 = 4152`.

Sul tablet: identità verificata da Lineage (SM-T720, `gts4lvwifi`, seriale
giusto, unico device di `adb`, batteria 68% in carica), `adb reboot download`
(unico id `04e8:685d`, `SDM710`, `bcdDevice 2.1b`), Heimdall
`flash --RECOVERY out/recovery.img --no-reboot`, 21:41:55–21:42:00,
`upload successful`. Avvio manuale del proprietario. Alle 21:43:03 l'host
ha visto il gadget. Dalla shell: `qcom-pon loaded, reboot-mode ready` a
1,281 s (anche nella foto `photo_2026-11-04_21-43-44.jpg`), nessun
`insmod` manuale; `/sys/class/reboot-mode/qcom-pon` presente; input
`pm8941_pwrkey` e `pm8941_resin`; `misc` a zero; rilettura di
`/dev/mmcblk0p49` (4152 pagine) con sha256 `4908aecf…`, uguale all'immagine
scritta. Poi `boot-android` dalla shell (21:43:41): `restarting into
LineageOS`, l'host ha visto `04e8:6860` alle 21:44:17, e con
`adb -s R52M410RCVR` `sys.boot_completed=1`, `4.9.337-ga30605a54f3b`,
`ro.boot.boot_recovery=0`, adbd `uid 2000`. Il ritorno ad Android ora non
dipende da file copiati a mano. In `recovery` c'è l'immagine `4908aecf…`;
il tablet è su Lineage. Log in `out/third-shell-qcompon.log`,
`out/heimdall-qcompon-flash.log`, `out/usb-watch-qcompon.log`.

## M6 avviato: analisi e tarball verificato (nessun accesso al tablet)

Piano in `docs/ROOTFS-PLAN.md`. Fatto, sul PC:

- Il build upstream del rootfs (`tools/build-rootfs`) richiede Docker più
  binfmt aarch64, il keyring [omarchy] di un laptop Omarchy, e ragiona su
  un'immagine che cresce su tutto `userdata` dopo `install-phone`. Qui non
  c'è `docker`, `podman`, `qemu-aarch64` né binfmt aarch64, `sudo` chiede la
  password, e `userdata` non si tocca. I pacchetti apt `docker.io 29.1.3`,
  `qemu-user-static 8.2.2`, `binfmt-support`, `podman 4.9.3` sono
  disponibili e non installati.
- I repository Arch Linux ARM hanno già `mesa` e `vulkan-freedreno 26.2.6`,
  `hyprland 0.57.1`, `networkmanager`, `pipewire`, `systemd 262.1`,
  `pacman 7.1`, `linux-firmware-qcom`. Niente da compilare per M6.
- Kernel: le opzioni di systemd sono tutte presenti. `BLK_DEV_DM=m` e
  l'initramfs non ha `dm-mod.ko` (il target `linear` è dentro `dm-mod`, non
  esiste un `DM_LINEAR` separato). **La microSD non è nel DTS**: c'è solo
  `&sdhc_1`; il DTS Samsung 4.9 ha `&sdhc_2` con `cd-gpios = <&tlmm 3 0x1>`,
  quindi serve un nodo nuovo e un kernel nuovo.
- `scripts/fetch-alarm-rootfs.sh` ha scaricato e verificato (MD5, firma con
  la chiave pinned `68B3537F…`) il tarball `ArchLinuxARM-aarch64-latest`,
  829367415 byte, sha256 `42a4eeaa…`, fissato in `rootfs.lock`, in
  `src/alarm/` (gitignored). Contenuto: 2015 MiB decompresso, 165 pacchetti,
  `systemd 261.2`, `openssh`, il kernel Arch 7.1.6 e 950 MiB di firmware che
  non servono. **Gli account `root` e `alarm` hanno le password pubbliche di
  default** (`root`/`root`, `alarm`/`alarm`, verificato calcolando l'hash in
  locale) e `sshd` accetta la password: vanno bloccati. `systemd-networkd`
  ha solo `en.network` ed `eth.network`, quindi `usb0` va configurata a
  parte. GNU tar scarta gli xattr `security.capability`.

Opzioni di storage confrontate nel piano: A microSD, B file in `userdata`
via dm-linear, C ripartizionamento, D rootfs in RAM scaricato via USB.
Consiglio D come prima prova (stima di 585–715 MiB contro 3,47 GiB di RAM,
non misurata) e poi A o B.

## M6 passato: Arch Linux ARM avviato dal file in `/data` (2026-11-04, 22:34)

Con l'autorizzazione permanente del proprietario («il tablet è throwaway»).

- **Immagine.** `scripts/build-rootfs.sh` costruisce `out/rootfs/rootfs.img` in
  container aarch64 (Docker 29.1.3 più `qemu-user-static`, installati dal
  proprietario): il tarball verificato, keyring `archlinuxarm`, kernel Arch,
  `mkinitcpio` e firmware inutile rimossi con pacman, `linux-firmware-qcom`
  aggiunto, `root` e `alarm` bloccati (le password pubbliche non
  sopravvivono), `sshd` a sola chiave con una chiave dedicata in `out/keys/`
  (gitignored, mai la `~/.ssh` del proprietario), `usb0` con `172.16.42.1/24`
  e DHCP server per il lease `.2`, moduli del nostro kernel con `depmod`.
  ext4 da 6 GiB, `e2fsck` pulito, 154 pacchetti, sha256
  `c68262ca93b825a01ae616144cf77161ba57d13befbc770a06ae0c1516959444`.
  Controllato con `debugfs` prima di spedirlo.
- **Sul tablet.** `scripts/rootfs-to-tablet.sh` verifica identità, che `/data`
  stia direttamente su `mmcblk0p57` in ext4 senza strato di cifratura sotto,
  lo spazio, poi copia il file in `/data/lost+found/gts4lv/rootfs.img` (hash
  riletto sul tablet uguale) e registra gli estratti con il nostro `fiemap`:
  125 estratti, flag solo 0 e `LAST`, nessun buco, tutti allineati.
- **Initramfs.** Carica `dm-mod`, mappa gli estratti con il nostro `dmlinear`
  (codice scritto da noi, non quello di pulpoff, di licenza non chiarita),
  monta l'ext4 in lettura e scrittura e passa ad Arch con `exec switch_root`,
  dopo aver ucciso `telnetd` e `udhcpd` (shell senza password). Il file
  `/boot-attempt`, creato prima del passaggio e tolto da un servizio
  dell'immagine, fa restare l'init nella shell USB se l'ultimo tentativo non è
  finito.
- **Primo tentativo, fallito per un mio errore.** Foto
  `photo_2026-11-04_22-16-53.jpg`: `dm-mod` caricato, `EXT4-fs (dm-0):
  mounted filesystem … r/w`, `GTS4LV-SWITCHROOT`, poi BusyBox stampa l'uso di
  `switch_root`. Nel sorgente di BusyBox l'uso compare se il processo non è
  PID 1: avevo scritto `switch_root` senza `exec`, quindi girava come figlio
  della shell. Il tablet è rimasto senza telnet. Dopo un reset a tasti il
  marker ha fatto restare l'init nella shell (`arch: the last attempt never
  finished, staying`), come progettato. Correzione `exec switch_root`
  (commit `df598d7`).
- **Secondo tentativo, 22:34.** `sshd` (porta 22) aperta, telnet (23) chiuso.
  `systemctl is-system-running`: `running`, 0 servizi falliti, root su
  `/dev/dm-0` (il file in `/data`), `usb0` `172.16.42.1/24`, 3550 MB di RAM
  con 286 usati, `systemd 262.1`, `pacman 7.1.0`, marker già tolto.
- **`pacman` e Landlock.** `pacman -Sy` falliva: `restricting filesystem
  access failed because Landlock is not supported by the kernel`. Il kernel
  aveva `# CONFIG_SECURITY_LANDLOCK is not set` e un solo LSM, `capability`.
  Aggiunto `CONFIG_SECURITY_LANDLOCK=y` a `device/gts4lvwifi/kernel.config`
  (build #6, nessun warning, `Image.gz` `499b5503…`, DTB invariato
  `e496d213…`). Immagine `recovery.img` 17395712 byte, 4247 pagine, sha256
  `23ce16564b90d4f846ee06923e91fe7355a88409b30899a096f54af9de08b85e`,
  scritta dalla shell SSH di Arch con `scripts/flash-recovery-shell.sh`
  (rilettura identica) dopo `scripts/sync-modules.sh` per tenere i moduli del
  rootfs della stessa build. LSM attivi dopo: `capability,landlock`.
- **Accettazione.** `scripts/arch-smoke.sh`: imposta l'orologio dall'host (il
  tablet non ha RTC e parte nel 1977, `pacman` rifiuterebbe le firme), avvia
  `scripts/usb-http-proxy.py` sull'indirizzo USB dell'host (niente NAT, niente
  `sudo`), `pacman -Sy` sincronizza `core`, `extra`, `alarm`, `aur`,
  `pacman -S tree` installa con controllo di keyring e integrità, `pacman -Qk
  tree`: 7 file su 7. Systemd, shell SSH su USB, rete USB e gestione pacchetti
  funzionano: criterio di M6 soddisfatto.
- **Ritorno ad Android da Arch.** `boot-android` (nuovo, nell'overlay del
  rootfs, installato anche a mano nel sistema in esecuzione) cancella la
  richiesta `boot-recovery` di `misc`, rifiuta qualunque altro comando, poi
  `systemctl reboot --reboot-argument=android`. Provato alle 22:43:21: alle
  22:44:53 `adb` vedeva Lineage, `boot_completed=1`, kernel 4.9.337,
  `boot_recovery=0`.

## Il giro Lineage → Arch non è chiuso: la recovery sembra riscritta

Alle 22:45:30 `adb reboot recovery` dopo quell'avvio di Lineage non ha
riportato in Arch. Dopo 7 minuti e oltre: nessuna porta 22 o 23, e l'host
vede `18d1:d001`, product `SAMSUNG_Android`, `bcdDevice 4.09`, **una sola
interfaccia (ADB)**, `adb` lo dà `unauthorized` e non cambia in 5 minuti.
Non è l'MTP+ADB (`04e8:6860`) che Lineage mostra da avviato. L'ipotesi, non
verificata: all'avvio Android `install-recovery.sh` (AOSP; il device tree
Lineage non imposta `BOARD_USES_FULL_RECOVERY_IMAGE`) ha trovato la partizione
`recovery` diversa da quella attesa e l'ha riscritta con quella di Lineage,
quindi `adb reboot recovery` ha avviato la recovery di Lineage, che non conosce
la chiave `adb` perché `/data` cifrato non è montato. Coerente con tutto il
resto: finora ogni scrittura di `recovery` è stata seguita da un riavvio
diretto, mai da un avvio di Android in mezzo. Non c'è modo di entrare nel
tablet senza tasti: serve il proprietario.

Da fare appena il tablet è raggiungibile:

1. Con i tasti: Power + Volume giù finché si spegne e riparte. Con `misc` pulito
   (lo ha cancellato `boot-android`) e la recovery di Lineage dentro, un avvio
   normale dovrebbe andare in `boot`, cioè Lineage.
2. Da Lineage con `adb root`: leggere la partizione `recovery` e confrontarla
   con `out/lineage-recovery-before-mainline.img` (sha256 `81f4d19e…`) e con
   `out/recovery.img`, per confermare o smentire l'ipotesi.
3. Se confermata: spegnere `install-recovery` su Lineage (la proprietà della
   voce «Update recovery» delle opzioni sviluppatore, o il servizio
   `flash_recovery`) e verificare che resti spento dopo un riavvio. Poi
   `scripts/flash-recovery-adb.sh` e `adb reboot recovery`.

## Notte del 2026-11-04: lavoro offline mentre il tablet non è raggiungibile

Il proprietario ha lasciato il PC acceso e ha chiesto di proseguire con le
milestone successive. Il tablet è rimasto in uno stato che richiede i tasti
(vedi sopra), quindi tutto quello che segue è offline. Un osservatore staccato
(`out/night-watch.log`) registra ogni cambio di id USB, stato `adb` e porte
22/23; dalle 23:01 mostra `18d1:d001`, `unauthorized`, nessuna porta, senza
variazioni.

- **Controlli statici (M9).** `.github/workflows/static.yml` gira a ogni push e
  pull request: shellcheck a soglia `warning` su tutti gli script, yamllint
  (`.yamllint`), gli strumenti C compilati con `-Werror` per aarch64, i test del
  packer, e una guardia che non siano tracciati foto, immagini, chiavi o cpio
  (eccezione documentata: il `dtbo` di Lineage). Ho corretto i vecchi avvisi
  SC1007 e SC2125; l'initramfs ricostruito ha gli stessi 23 file con gli stessi
  hash di quello flashato. `kernel.yml` non è toccato.
- **Matrice hardware.** `scripts/hw-matrix.py` parte dal DTB compilato, trova i
  dispositivi abilitati, il sorgente del driver, il simbolo Kconfig e se il
  modulo esiste. `docs/HARDWARE-MATRIX.md` separa le misure fatte sul tablet da
  quello che la build ha solo. Trovati vuoti veri nella configurazione: non sono
  compilati il driver del pannello (`DRM_PANEL_SAMSUNG_ANA38401`), i CS35L41,
  `BATTERY_SM5705` (il suo Kconfig dice che i chip caricano da soli e il driver
  solo riporta) e i due sensori camera; manca `CONFIG_INPUT_UINPUT` per il
  demone del touch.
- **Kernel M7.** Sei opzioni, tutte `=m` e nessuna caricata all'avvio, aggiunte
  a `device/gts4lvwifi/kernel.config`. Build senza warning, tutti i `.ko`
  presenti. **Non è nell'immagine che è sul tablet.**
- **Licenze.** I file di `mobian/` di pulpoff non hanno nessuna intestazione né
  file di licenza: non copio nulla (`dmlinear`, `fiemap`, `rebootmode` sono
  scritti da zero), uso i suoi script solo per ordine e parametri.
  `docs/LICENSES.md`.
- **Pacchetti Qualcomm.** Arch Linux ARM non ha `qrtr`, `rmtfs`, `tqftpserv`,
  `pd-mapper`, `hexagonrpc`. Cinque `PKGBUILD` in `packages/`, pinnati per tag e
  sha256 (BSD-3-Clause, `hexagonrpc` GPL-3.0), compilati da
  `scripts/build-packages.sh` nel container come utente non privilegiato:
  aarch64, con licenze e unità systemd. L'unità di `rmtfs` usa `-r`, quindi le
  partizioni del modem si leggono e non si scrivono.
- **Rootfs v2** (`out/rootfs/rootfs.img`, sha256
  `f4bbee5544b1058cfdb12bb3bb54c13e98161f1f93b00381f002205df6f7357f`): 231
  pacchetti, i cinque nostri, `libssc`, `iio-sensor-proxy`, `iw`,
  `wpa_supplicant`, ALSA, `mesa` e `vulkan-freedreno` di Arch Linux ARM, più
  overlay: blacklist dei moduli da caricare a mano (i pin LPASS bloccano il bus
  finché l'ADSP non gira), `gts4lv-firmware` (monta `modem`, `apnhlos` e
  `vendor` in sola lettura e collega i file sotto `/run`, nulla viene copiato),
  `gts4lv-dsp` e un'unità che ferma l'ADSP allo spegnimento (con l'ADSP acceso
  l'ABL entra in loop). Ancora sul tablet c'è la v1 (extents in
  `out/prev/rootfs-extents-v1.txt`); la v2 non è stata copiata.
- **M8.** `docs/OMARCHY-PLAN.md`. Gli indici dei repository mostrano
  `[omarchy]` (187 pacchetti stable) e `[omamobile]` (43) pubblicati per aarch64.
  Scoperta importante: il `mesa` di `[omamobile]` è una build solo Mali, senza
  Freedreno; con l'ordine dei repository dell'upstream sostituirebbe il nostro e
  toglierebbe l'accelerazione sull'Adreno 615. `mesa` e `vulkan-freedreno` devono
  venire da Arch Linux ARM. L'insieme mobile è di 443 pacchetti e 748 MiB da
  scaricare: la prossima immagine va a 12 GiB.
- **Documentazione.** `README.md` riscritto, `AUDIT.md` e `BRINGUP-M1.md` marcati
  come superati.

## Quando il tablet è raggiungibile

Il proprietario deve prima tenere Power + Volume giù finché si spegne e riparte
(vedi la sezione sul giro Lineage → Arch). Poi, nell'ordine:

1. Lineage con `adb root` (`scripts/lineage-recovery-check.sh`, sola lettura): leggere `recovery` e confrontarla con
   `out/lineage-recovery-before-mainline.img` (`81f4d19e…`) e con
   `out/prev/recovery-landlock-23ce1656.img` (l'immagine scritta alle 22:40).
   Confermare o smentire che Android la riscrive.
2. Se confermato, spegnere `install-recovery` su Lineage e verificare che resti
   spento dopo un riavvio.
3. Ricompilare l'immagine con il kernel M7 (`scripts/build-initramfs.sh`), copiare
   il rootfs v2 con `scripts/rootfs-to-tablet.sh` (nuovi estratti, quindi
   ricostruire initramfs e immagine dopo), scrivere con
   `scripts/flash-recovery-adb.sh` e `adb reboot recovery`.
4. In Arch: `scripts/arch-smoke.sh`, poi i passi di `docs/PORTING-ROADMAP.md`
   nell'ordine del paragrafo 4, uno per volta e annunciati.

## 2026-11-05 mattina: il giro Lineage → Arch è chiuso, batteria e firmware ok, poi uno stallo

- **Pubblicato su GitHub.** `git push` normale (avanzamento rapido) di 25 commit
  sul ramo `feat/gts4lvwifi-mainline-bringup`; la CI `static` è verde sui due
  push (`5d2bbf9`, `2846643`). Le foto non sono mai state inviate: le due
  commit che le aggiungevano erano state scartate dalla storia locale prima
  del primo push. Controllato sul remoto: nessun commit raggiungibile dai
  rami remoti tocca un `jpg` o `photo_*`, l'albero su GitHub ha 0 immagini, i
  due hash delle foto sono assenti. Quindi non è servito un push forzato e non
  ne è stato fatto uno. Il ramo di backup locale e i `refs/original` di
  `filter-branch` sono stati cancellati, perché un `git push --all` li avrebbe
  pubblicati.
- **La `recovery` veniva riscritta da Android: confermato.** Alle 07:10 la
  partizione aveva sha256 `81f4d19e…`, cioè esattamente la copia originale di
  Lineage. Meccanismo letto sul tablet: `/vendor/bin/install-recovery.sh`
  confronta lo SHA1 dei primi 64 MiB della partizione con quello atteso e, se
  differisce, riflasha `/vendor/etc/recovery.img`; la regola
  `vendor_flash_recovery.rc` lo lancia con `on
  property:persist.vendor.recovery_update=true`, valore che era `true`.
  Con `setprop persist.vendor.recovery_update false`, la nostra immagine
  scritta e un riavvio **normale** di Android, la `recovery` coincide ancora con
  `out/recovery.img` (`MATCH`) e il servizio non è partito. Poi `adb reboot
  recovery` → Arch in 57 s. `scripts/lineage-recovery-check.sh` è lo
  strumento di sola lettura che lo ha mostrato. Dopo il riavvio la proprietà
  risultava vuota, non `false`: non so se il framework la riscrive più avanti.
- **Batteria (M7.7).** `modprobe sm5705_battery`: compaiono `sm5705-battery` e
  `sm5705-charger`. Letti: `Charging`, 96%, 4,27–4,29 V, +336…+468 mA, 28,5 °C,
  `charge_full_design` 7040000 µAh, 27,1 Wh. Il tablet carica sotto Linux.
- **Firmware (passo 0).** `gts4lv-firmware` ha montato `modem` e `apnhlos`
  (vfat) e `vendor` (ext4) in sola lettura e collegato 459 file sotto `/run`;
  esistono tutti e cinque i nomi che il device tree chiede (`mba.mbn`,
  `modem.mdt`, `adsp.mdt`, `venus.mdt`, `a615_zap.mdt`). Nulla copiato.
- **Moduli caricati da soli in questa Arch.** 97, tra cui `msm`, `ath10k_snoc`,
  `qcom_q6v5_mss`, `qcom_q6v5_pas`, `pinctrl_sdm670_lpass_lpi`, `venus_core`,
  `hci_uart`, e il tablet è rimasto `running`. Nel `dmesg` (`out/arch-dmesg-20261105.log`):
  `msm_dsi_phy … DSI PLL(0) lock failed` due volte con warning di bilanciamento
  dei clock (`clk_core_disable`, `clk_core_unprepare`) e call trace, nessun
  crash; `venus` e l'ADSP senza firmware (il percorso non era ancora
  impostato); `regulatory.db` assente (`wireless-regdb` è nella v2). Nessun
  errore di versione dei moduli: quelli della build #6 si sono caricati sul
  kernel #7. C'è `/dev/watchdog0` con `qcom_wdt` caricato.
- **Il kernel ha già un pd-mapper** (`qcom_pd_mapper` caricato). Il `pd-mapper`
  in userspace che avevo pacchettizzato sarebbe un duplicato: tolto.
- **Modem DSP.** `systemctl start rmtfs` (unità con `-r -P -s`) ha avviato da
  solo il DSP del modem, perché `-s` significa «sincronizza e avvia il
  remoteproc»: `Booting fw image qcom/sdm670/gts4lv/mba.mbn, size 238304`,
  `MBA booted without debug policy, loading mpss`, `remote processor
  4080000.remoteproc is now up`, circa 1,4 s. Dopo 18 s ancora nessun `wlan0` e
  nessuna riga di `ath10k`. **Circa 30 s dopo l'avvio del modem l'USB è sparito
  (07:20:41): il tablet si è resettato.** Non so se il reset è causato dal
  modem; è l'ipotesi con cui coincide la sequenza, non una prova. È tornato su
  USB alle 07:21:53 con il nostro gadget, ma da allora né la 22 né la 23
  rispondono, l'interfaccia dell'host non riceve IPv4 e non risponde nemmeno
  l'IPv6 link-local, e l'USB resta stabile. Dopo il riavvio la regola udev
  `rmtfs.rules` (installata dal pacchetto) avvia `rmtfs`, quindi il modem, a
  ogni boot: è la causa che sospetto, non confermata. Serve la foto dello
  schermo.
- **Difetto di sicurezza trovato e corretto.** `cp -a` nello script di build
  copiava uid 1000 (`alarm` nell'immagine) e modo 775 sulle directory già
  esistenti: `/etc`, `/etc/systemd`, `/etc/ssh` e tutto l'albero dei moduli del
  kernel risultavano di `alarm:alarm`; il deploy dal vivo aveva reso `/` e
  `/usr` `775`. `alarm` è bloccato e nessun servizio gira come lui, ma
  l'esposizione c'era. Riparato sul tablet (462 directory sbagliate → 5, le
  directory di gruppo di serie di Arch) e negli script: ora la copia passa da
  `tar` come root, senza scrittura di gruppo o altri e senza toccare le
  directory esistenti. `scripts/verify-rootfs.py` legge l'export del
  container: 2465 errori sulla v2, passa sulla v3.
- **Rete di sicurezza per il prossimo avvio.** Ho aggiunto all'overlay una
  console root sulla seriale USB (`gts4lv-debug-console.service`, solo per il
  bring-up: chi ha il cavo ha root) e mascherato la regola udev di `rmtfs`,
  così il modem parte solo per una decisione esplicita. Non sono sul tablet.

## 2026-11-05, dopo lo stallo: la rete non era morta, e lo schermo nero ha una causa

Il proprietario ha riavviato il tablet e ha descritto cosa vedeva: shell,
kernel, moduli caricati («ok» verdi di `systemd`), schermata di login, poi
schermo nero.

- **Lo «stallo» era il DHCP.** Dall'host nessuna porta rispondeva e
  l'interfaccia USB restava senza IPv4, ma con un indirizzo fisso assegnato
  all'host (`nmcli … save no`, solo in memoria, nulla scritto in `/etc`) il
  tablet rispondeva al ping e `sshd` era aperto: Arch era sano (`running`, 0
  unità fallite, `usb0` `routable`). Causa: `10-usb0.network` aveva
  `PoolSize=1` e `systemd-networkd` conserva i lease su disco. Il lease
  salvato era per `172.16.42.2` al MAC dell'host del boot precedente, con
  scadenza `2026-11-04 21:24` (orologio impostato da `arch-smoke`), mentre il
  tablet riparte ogni volta dal 1977: per il server DHCP il lease scadeva fra
  quasi 50 anni, il pool era pieno e ogni client nuovo (il gadget ha MAC casuali)
  non riceveva niente. Corretto: `PoolSize=8`, lease di 300 s, `PersistLeases=no`.
  L'host ora ottiene l'indirizzo da solo (`.6`, poi `.7`: non è più fisso, e
  `arch-smoke.sh` e `usb-http-proxy.py` ora lo rilevano dalla rotta).
- **L'orologio.** `date -s` funziona, `hwclock --systohc` no (`RTC_SET_TIME … No
  such device`): l'RTC del PMIC non è scrivibile con questo device tree, quindi
  ogni avvio riparte dal 1977. Non risolto: per ora lo imposta l'host quando
  serve (`arch-smoke.sh`).
- **Lo schermo nero: causa misurata.** `octa-vdd` è l'alimentazione del
  pannello, un regolatore fisso sul GPIO 21 del TLMM con `regulator-boot-on` e
  nessun consumatore finché il driver del pannello non è caricato. Il codice di
  pulizia dei regolatori lo spegne a 31,226 s (`octa-vdd: disabling`,
  `state=disabled`, `num_users=0`). Quindi in ogni avvio lo schermo si spegne a 31
  secondi; le mie foto erano tutte scattate prima. Il piano del display aveva
  l'ipotesi opposta, sbagliata: corretto in `docs/DISPLAY-PLAN.md`.
- **Tentativo con la sola cmdline.** `regulator_ignore_unused` aggiunto a
  `device.conf` (nient'altro cambiato: kernel e DTB identici byte per byte, i 23
  file della ramdisk identici, nell'header cambia solo la cmdline). Immagine
  `b7a12018…`, scritta da SSH con `scripts/flash-recovery-shell.sh --reboot` e
  riletta. Misurato dopo il riavvio: la cmdline è arrivata, `octa-vdd` è
  `enabled` a 10 s e a 48 s, `dmesg` non ha più nessuna riga `: disabling`.
  Che il pannello resti acceso lo conferma chi guarda lo schermo.
- **Il modem.** Al boot `rmtfs` (avviato dalla regola udev del pacchetto) ha
  provato ad avviare il DSP a 5,07 s, ma il firmware non era ancora visibile e il
  caricamento è fallito con `-2`: in quel boot il modem non è partito. Il reset
  delle 07:20 è seguito all'avvio *manuale*. La regola udev è ora mascherata sul
  tablet vivo (`/etc/udev/rules.d/rmtfs.rules` → `/dev/null`) e nell'overlay.
  Ancora da capire: se è il modem a resettare il tablet. Servono la console
  seriale USB (`gts4lv-debug-console`, nell'immagine v3, non ancora sul tablet)
  e un avvio manuale con qualcuno ai tasti.
- **I CS35L41.** I quattro amplificatori sono stati caricati da soli in questo
  boot (`snd_soc_cs35l41_i2c`) e hanno risposto agli indirizzi `3-0040..0043`
  con «Subsystem ID not found» e supply `VA`/`VP` sostituiti da regolatori fittizi.
  Non è ancora stato misurato se il probe riesce.

- **Esito del tentativo e MAC fissi.** Il proprietario ha visto la console accesa
  dopo il riavvio con `regulator_ignore_unused` (`octa-vdd` `enabled` anche a 415 s).
  Poi, come cambiamento a sé, l'init imposta MAC fissi e *localmente amministrati*
  al gadget (`02:67:74:73:34:01..04`, nessuno è l'indirizzo di un dispositivo):
  con MAC casuali l'host rinominava l'interfaccia ad ogni avvio. Immagine
  `d72aa929…`, scritta da SSH e riletta; dopo il riavvio l'host vede
  `enx026774733401` (NCM) e `enx026774733403` (RNDIS), con indirizzo da DHCP.
  Sul tablet sono stati installati, via proxy, gli strumenti di
  `device/gts4lvwifi/rootfs/packages.txt` (`iw`, `evtest`, `i2c-tools`, ALSA,
  `mesa-utils`, `vulkan-tools`, `libssc`, `iio-sensor-proxy`…) e tolto `pd-mapper`.

## 2026-11-05, Wi-Fi: la causa dei reset erano i dati di board

Il proprietario era assente (circa mezz'ora, poi di più): tutto fatto da SSH, con
il tablet che si riavvia da solo quando il test lo resetta (rientra in circa 70 s,
senza tasti). Ogni prova ha cambiato una sola cosa.

| Prova | Cosa cambia | Esito |
| --- | --- | --- |
| 1 (`out/modem-test/`) | modem avviato da `rmtfs`, `ath10k_snoc` caricato | dopo l'handshake QMI (`chip_id 0x140`, `board_id 0xff`, firmware `WLAN.HL.3.2.6.c1-00500`) il tablet si resetta dopo 10-17 s, senza panic né oops |
| 2 (`out/modem-test-noath/`) | come 1, ma `ath10k_snoc` e `ath10k_core` scaricati | il modem resta `running` per tutti i 167 s misurati: da solo non resetta nulla |
| 3 (`out/ath10k-debug/`) | `CONFIG_ATH10K_DEBUG=y` (solo moduli), `debug_mask=0xffffffff` | ath10k sceglie **`board-2.bin` di linux-firmware** (`using board api 2`, voce generica `bus=snoc,qmi-board-id=ff`), «qmi bdf download request completed» e «qmi cal report request completed» a +0,02 s, poi silenzio fino al reset. Nessun passo dell'host è sospeso: il firmware sul modem non dichiara mai «fw ready» |
| 4 (`out/ath10k-board1/`) | `board-2.bin` spostato via (`.gts4lv-off`): ath10k ripiega su `board.bin` = `bdwlan.bin` di Samsung | «using board api 1», «wifi fw ready event received» dopo 2,3 s, «firmware ver … api 5», **`wlan0` compare, nessun reset, 172 s stabili** |

Conclusione: con i dati di board generici di linux-firmware il firmware WLAN
manda in blocco il SoC; con quelli di Samsung funziona. Non so *perché* i dati
generici resettino tutto (non ho una console che sopravviva al reset), ma la
differenza è misurata con una sola variabile. Il vecchio `board.bin` -> `bdwlan.bin`
c'era già dall'inizio: `board-2.bin` ha la precedenza, e prima non lo sapevo.

- **Scansione.** `ip link set wlan0 up` e `iw dev wlan0 scan`: 4 reti, 2,4 e 5
  GHz (canale 104, DFS), da -42 a -88 dBm. L'associazione non è provata: servono
  le credenziali del proprietario, che non entrano nel repository. Il MAC è casuale
  a ogni avvio (nessun MAC in fabbrica letto: `xo-cal-data return -22` nel log).
- **Correzione nell'immagine.** `customize.sh` aggiunge a `/etc/pacman.conf`
  `NoExtract = usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin` (il file è di
  `linux-firmware-atheros`, quindi resisterebbe a un aggiornamento solo così);
  `gts4lv-firmware` avvisa nel log se il file torna. Sul tablet vivo il file è
  stato rinominato e `NoExtract` aggiunto.
- **`gts4lv-modem`** (script + `gts4lv-modem.service`, abilitata): scrive un
  marker prima di avviare il modem, scarica e ricarica ath10k (`wlan0` resta
  registrata anche a modem spento: la sua comparsa è un segnale valido solo se
  ath10k riparte pulito; il primo giro dell'unit lo ha mostrato: terminava in 0,1 s
  con il modem ancora `offline`), avvia `tqftpserv` e `rmtfs`, aspetta `wlan0` fino
  a 60 s e toglie il marker. Se all'avvio trova il marker, il tentativo precedente
  non è arrivato a `wlan0` e non avvia nulla. L'unit parte dopo `gts4lv-boot-ok`:
  un reset durante l'avvio del modem non blocca l'initramfs nella shell USB. Allo
  stop ferma `rmtfs` e il modem.
- **Prova a catena, senza nessuno.** `systemctl reboot` con il modem acceso:
  chiusura pulita, `ssh` di nuovo raggiungibile, dopo l'avvio `gts4lv-modem`
  «wlan0 is up after 5 s», `state=running`, 0 unità fallite, scansione di 4 reti.
- **`qrtr-ns.service` non va abilitato.** Il kernel ha il name service (in
  `dmesg`/journal: «nameserver already running, going dormant: Address already in
  use»): tolto da `customize.sh`.
- **pstore non serve.** `echo c > /proc/sysrq-trigger`: panic, il tablet si
  riavvia da solo, `/sys/fs/pstore` è vuoto (e `systemd-pstore` è disabilitato, quindi
  non è stato lui a svuotarlo). Il bootloader Samsung azzera la RAM; il `ramoops`
  del device tree funziona solo se dopo il reset parte qualcosa che non la
  cancella (il U-Boot di pulpoff).
- **`CONFIG_ATH10K_DEBUG=y`** resta nel frammento (solo moduli, `debug_mask` vale 0
  se non lo si imposta). `scripts/sync-modules.sh` ha copiato i moduli sul tablet;
  il kernel in esecuzione è quello di prima (`Image.gz` ricollegata, ma non
  riscritta nella recovery: nessun motivo).
- **`verify-rootfs.py`** ora segnala `board-2.bin`, `gts4lv-modem` non abilitata,
  `qrtr-ns` abilitata: sull'immagine v3 costruita ieri notte segnala tutti e tre.
  Nuova immagine (v4) in costruzione.

## 2026-11-05 pomeriggio: Bluetooth, codec, e il driver del tocco

- **Bluetooth.** `modprobe hci_uart` con il percorso del firmware già impostato:
  `hci0`, «QCA Downloading qca/crbtfw21.tlv» e `crnv21.bin`, «QCA setup on UART is
  completed» in 1,4 s. Con `bluez`, `btmgmt info`: controller acceso con l'indirizzo
  del device tree, scansione di 12 s: 6 dispositivi vicini.
  Nuova unit `gts4lv-bluetooth.service` (carica `hci_uart` dopo `gts4lv-firmware`),
  `bluetooth.service` abilitata, `bluez` e `bluez-utils` in `packages.txt`.
  Associazione e audio non provati.
- **Codec video.** `modprobe venus_core`: `venus_dec` e `venus_enc` si caricano senza
  errori, compaiono `/dev/video12` e `13`. Nessun flusso decodificato.
- **Tenuta del Wi-Fi.** Il tablet è rimasto acceso 5,3 ore di fila (stesso boot) con
  modem, `wlan0` e `hci0` attivi, dopo 13 minuti di scansioni ogni 20 s. Nel log solo
  `ath10k_snoc: chan info: invalid frequency 0 (idx 41 out of bounds)`, innocuo.
  L'unico problema era mio: `20-wlan0.network` rendeva `wlan0` un link da attendere
  e `systemd-networkd-wait-online` andava in timeout (`degraded`); ora
  `RequiredForOnline=no`.
- **Il tocco, passi 1 e 2 del piano.** Sul bus `i2c-6` (= `i2c9`), indirizzo 0x49:
  il comando 0x22 risponde `53 54 39 36`, cioè «ST» e gli `FTS_ID0/ID1` (0x39, 0x36)
  del sorgente Samsung; 0x24 risponde `00 11 00 06…`; 0x60 restituisce eventi da 8
  byte (il primo è un evento di stato «ready»: eid 1, stype 2, id 0).
- **Il driver** `device/gts4lvwifi/kernel/fts1ba90a/fts1ba90a.c` (GPL-2.0, scritto qui:
  i fatti del protocollo sono dal sorgente GPL di Samsung, lo scheletro da `stmfts.c`).
  Reset, attesa del «ready», controllo dell'ID, scansione, fino a 10 dita come slot MT
  sugli assi nativi (x 0-1599, y 0-2559), palmo come `MT_TOOL_PALM`. Parametri `poll_ms`
  e `debug`. Senza interrupt nel device tree ripiega sul polling.
- **Il polling uccide il tablet.** Con il client creato a mano (`new_device`, senza
  interrupt) e il driver in polling, il tablet si è resettato da solo, senza panic né
  log, in 3 prove su 4 (dopo ~5 s a 100 Hz, ~85 s a 10 Hz; la prima prova, 50 s, è
  sopravvissuta). Non è la batteria (100%, 4,36 V). Le sole letture non bastano:
  avviato il controller **senza mai leggere la coda** il tablet regge 150 s
  (prova A); letture da shell con `i2ctransfer` a ~15 Hz **senza scansione attiva** reggono
  190 s (prova C). Il sospetto è la combinazione scansione accesa + letture a tempo
  casuale mentre il controller è occupato; non è dimostrato.
- **Con l'interrupt regge.** Patch al kernel (nodo `touchscreen@49` su `&i2c9`,
  GPIO 123 a livello basso, `bias-disable` come in Samsung; Kconfig e Makefile) in
  `device/gts4lvwifi/kernel/patches/`, applicate da `scripts/apply-kernel-patches.sh`
  (chiamato da `build-kernel.sh`, idempotente). Con il sorgente modificato la
  versione diventa `7.2.13-gts4lvwifi-g36f309c07087-dirty` (stabile da build a build:
  i moduli stanno in `/usr/lib/modules/<release>`, e sono stati copiati prima del
  flash con `scripts/sync-modules.sh --stage`). Recovery `5d9a25f7…` scritta da SSH e riletta
  (backup della precedente in `out/prev/recovery-before-touch.img`). Dopo il riavvio:
  `state=running`, modem, `wlan0` e `hci0` su da soli, il driver si aggancia a 4,5 s con
  `irq 166`. Osservato 5 minuti, scansione accesa: nessun reset.
- **I tocchi del proprietario (14:40 circa).** Nei 3 minuti di registrazione che
  ho fatto io il contatore dell'interrupt è rimasto a 1: nessuno toccava. Poi il
  proprietario ha provato da solo (con `debug=1` attivo, che registra ogni evento
  non nullo) e ho ripreso i log dal tablet. Il tablet si era riavviato (arresto
  pulito, 520 s) e nel boot corrente l'interrupt è a **320**, con 628 eventi: 22
  press, 584 move, 22 release, tutti `eid` 0; `tid` 0, 1 e 2 (fino a tre dita
  insieme), x 739..1295 e y 820..1896 (dentro 0..1599 e 0..2559), pressione 3..26,
  tipo 0 (dito), `left_event` al massimo 2, nessun evento di errore, nessun reset.
  Press e release sono uguali: nessuno slot rimasto aperto. Quindi la decodifica
  degli eventi, l'interrupt e il multitouch funzionano a livello di driver.
  Non è provato: gli angoli (le coordinate osservate sono tutte al centro), i tocchi
  letti da `evtest` come eventi evdev (il test era sul log del driver), libinput e
  un compositor, scorrimento e gesture, rotazione, ripresa dopo lo spegnimento.
- **Errori miei di oggi.** Un file `localversion.config` messo nella cartella di
  output ha corrotto `kernel.release` (Kbuild legge ogni `localversion*` lì) e ha fatto
  fallire una compilazione: tolto, nessun danno al tablet. Un `evtest` lanciato senza
  `timeout` ha bloccato un comando per più di 200 s.
- **Foto.** La foto delle 13:44 è trascritta in `docs/CONSOLE-LOG.txt`: schermo acceso a
  ~80 s dall'avvio, `regulator: Not disabling unused regulators`, `ath10k: invalid MAC
  address; choosing random`, audio in deferred probe in attesa del pinctrl LPASS.

## 2026-11-05 pomeriggio, 14:08: il display, passi 2-4 del piano (da ssh)

Con il proprietario in zona ma senza ancora un suo resoconto di cosa mostra lo
schermo. Log in `out/display-*` (non in git). Dettagli e righe di log in
`docs/DISPLAY-PLAN.md`, in fondo.

- **Passo 2.** `modprobe panel_samsung_ana38401`: `rc=0`, nessun messaggio nuovo,
  `octa-vdd` resta acceso.
- **Passo 3.** `modprobe msm`: `rc=0`, il tablet resta su. `card1-DSI-1` connesso,
  modo 2560x1600 a 60 Hz, `renderD128`, un dispositivo backlight `ae94000.dsi.0`,
  `fb0` diventa `msmdrmfb`; il pannello riceve «panel re-initialised», «TCON
  ready=1», «display on (227 ms after reset)». Rumore del kernel: **`DSI PLL(0) lock
  failed` due volte** con warning del clock (`already disabled` / `already
  unprepared`), `qcom-llcc: Failed to get slice desc for uid: 11`, e
  **`fb0: sys_imageblit: framebuffer is not in virtual address space`** quando fbcon
  passa sul nuovo framebuffer.
- **Passo 4.** Barre di colore di `modetest` per 25 s: nessun errore DSI/DPU/vblank nel
  log, tablet su. Una prima prova durò un istante perché `modetest` esce subito senza
  terminale (`getchar()` vede EOF): la seconda ha tenuto lo stdin aperto con `sleep 25 |`.
- **Non so cosa si vedeva.** Che la console sia visibile dopo `msm`, e che le barre
  siano giuste su entrambe le metà, lo può dire solo chi guarda lo schermo.
- **Rootfs v5** (`3599b353…`) costruito con i moduli del kernel `-dirty` e verificato
  da `verify-rootfs.py`; non copiato sul tablet.

## 2026-11-05 sera (18:20): audio, M7.6 (da ssh, il proprietario presente e in ascolto)

Dettagli, ordine di avvio e la regola che ne segue in `docs/AUDIO-PLAN.md`.

- **Il tocco, dal proprietario.** Toccando vedeva i parametri del driver aggiornarsi
  sulla console, e al trascinamento ne comparivano di più perché arrivavano più
  eventi: coerente con i 628 eventi decodificati. (Quelle righe sono il `debug=1` del
  driver, che stampa sulla console; ora è a 0.)
- **ADSP.** `echo start > remoteproc0/state`: su in 0,4 s, servizi APR (q6core, q6afe,
  q6asm, q6adm, q6routing) e canale FastRPC. Poi `modprobe pinctrl_sdm670_lpass_lpi`:
  compare `card 0: S5e [Galaxy Tab S5e]` con MultiMedia1-3, `Speaker Playback`,
  `Headphone Playback`, `Mic Capture`; i codec PM8916, il jack delle cuffie come input.
  Lo stop (`gts4lv-dsp stop adsp`) è pulito: scheda sparita, tablet su.
- **Un mio errore.** Alle 18:24 ho riprodotto un tono con i quattro amplificatori a
  **0,00 dB e senza protezione DSP**, credendo di averli messi a -60 dB. `amixer sset
  "FL Digital PCM" -60dB` non funziona (`-60dB` è letto come l'opzione `-B`), l'errore era
  buttato in `/dev/null`, il riepilogo stampato mostrava `817 [0.00dB]` e lo stesso
  script ha continuato a suonare. Circa 5 s di 440 Hz da `speaker-test`; il proprietario
  ha «sentito un tono». Nel log del kernel non c'è nessuna riga in quell'intervallo. Se gli
  altoparlanti ne abbiano risentito non lo so. Regola adottata (in `AUDIO-PLAN.md`): ogni
  riproduzione imposta il volume, lo rilegge e si ferma se è sopra il limite, nello stesso
  comando.
- **Scala del volume.** `Digital PCM Volume` 1-913, da -102 a +12 dB, 0,125 dB per
  passo: 817 = 0 dB, 497 = -40 dB, 337 = -60 dB.
- **Protezione DSP.** Con i file Samsung visibili come `cirrus/cs35l41-dsp1-spk-prot.wmfw`
  e `.bin` e `DSP1 Preload Switch` acceso, su tutti e quattro gli amplificatori il
  firmware si carica («Firmware: 400a4 vendor: 0x2 v0.0.1, 1 algorithms», taratura
  «TAB_LV_S5e_PV2»). Senza il collegamento sotto `cirrus/` il driver avrebbe preso il
  `cirrus/` di linux-firmware, fatto per altre macchine: `gts4lv-firmware` ora crea i
  collegamenti a ogni avvio.
- **Secondo tono**, dopo il gate (volume riletto 497 = -40,00 dB su tutti e quattro,
  preload acceso): 3 s, nessun errore nel log, volumi riportati a -60 dB. Com'era il
  suono, non lo so ancora.
- **`scripts/run-with-log.sh`** (nuovo): esegue un comando sul tablet con il log del
  kernel in streaming sul PC e lo campiona; lo scratchpad era stato svuotato e con lui lo
  script con cui avevo fatto le prove di oggi.
- **Non fatto:** microfoni, i quattro canali separati, UCM, PipeWire, la calibrazione
  degli altoparlanti (Samsung tiene le resistenze misurate in `/efs`).

## 2026-11-05 sera, 19:00-19:35: l'audio che non usciva, e perché

- **Il silenzio non era il volume.** Dopo la prima riproduzione di un boot, tutte le
  successive fallivano all'accensione degli amplificatori (`Enable(1) failed: -110`, uno
  per amplificatore). Prima lo avevo letto come un problema del DSP di protezione: non
  lo era (succedeva anche senza DSP, e riagganciare i quattro driver non cambiava nulla).
- **La causa: i pin LPI.** I pin del TDM degli altoparlanti sono del controller LPASS
  LPI, i cui registri stanno nel dominio dell'ADSP e tornano ai default quando riparte.
  Il driver restava caricato e riteneva i pin ancora configurati: la scheda successiva non
  li riprogrammava, niente clock sul TDM, niente accensione. Per questo l'unico tono mai
  udito era il primo (0 dB, senza DSP). Prova: con l'ADSP spento, `modprobe -r
  pinctrl_sdm670_lpass_lpi` e un tono: nessun errore nuovo.
- **Correzione:** `gts4lv-dsp stop adsp` scarica il driver dei pin dopo aver fermato
  l'ADSP, e lo start lo ricarica (era già così). Tre toni di fila in modalità `dsp` a
  -24, -18, -12 dB: errori solo nel primo (l'accensione dopo un firmware appena caricato
  dura più di 100 ms: il DSP parte col primo flusso), nessuno nei due successivi.
- **Il proprietario ha sentito 2 di quei 3** (quali due, da confermare: il primo è quello
  con l'errore). Con la protezione caricata e nel percorso (`PCM Source` = DSP) il
  suono esce. Prima di ogni tono con DSP, `gts4lv-tone` ora riproduce un secondo di
  silenzio per far partire il DSP, e avvisa se un amplificatore non si accende.
- **Un altro mio errore, piccolo:** dopo il riavvio la numerazione dei remoteproc si è
  scambiata (`remoteproc0` modem, `remoteproc1` ADSP); lo script guardava `remoteproc0`,
  ha creduto l'ADSP già acceso e non l'ha fermato. Fermato a mano e script corretti
  (chiedono per nome tramite `gts4lv-dsp`). L'ADSP non parte da solo al boot: il mio
  «adsp=running» di quel boot era il modem.
- **Il volume al massimo, chiesto dal proprietario:** non l'ho fatto, per due motivi
  spiegati in `docs/AUDIO-PLAN.md`: il silenzio non dipendeva dal livello, e il massimo
  (+12 dB digitali, +20 dB analogici) su un'onda a piena scala è una forma d'onda tagliata a
  piena potenza, con la protezione per default fuori dal percorso.
- **Prova per altoparlante** (19:33, -12 dB, 1000 Hz, 3 s, DSP nel percorso, uno alla
  volta): FL 19:33:06, FR 19:33:23, RL 19:33:39, RR 19:33:55; nessun errore di
  accensione. Dove si sentiva ciascuno: da riferire.

## 2026-11-05 sera, 19:35-19:41: i microfoni fanno cadere l'ADSP

- **Risultato del proprietario sugli altoparlanti:** ha sentito il suono dall'altoparlante
  in alto e da quello in basso (e ha ricordato, giustamente, che non può sapere a che
  frequenza fossero i toni: 1000 Hz l'avevo scelta io). L'abbinamento dei quattro
  amplificatori FL, FR, RL, RR alle posizioni non è ancora noto.
- **Microfoni.** Cinque tentativi in quattro varianti (MultiMedia1 e MultiMedia3, `INP2` e
  `INP3`, con e senza la rotta delle cuffie, stereo 48 kHz e mono 16 kHz): a ogni apertura
  del flusso di cattura l'ADSP va in errore fatale e il remoteproc lo recupera (5 crash in
  tutto, il tablet non si è mai resettato). Il motivo, quando il kernel lo stampa:
  `fatal error received: ABT_dal.c:269:ABTimeout: AHB Bus hang is detected … addr0 =
  0x62…`. È un timeout del bus nella zona LPASS del codec digitale (`62ec0000`), all'avvio
  della porta AFE `0x1035` (MI2S TX interno). Gli altoparlanti non sono toccati (usano il
  TDM secondario). Cosa resta da provare è in `docs/AUDIO-PLAN.md`.
- **Coredump dell'ADSP:** con `coredump` su `enabled` il kernel tiene un ELF da 44 MB per
  cinque minuti; le stringhe sono del firmware e non nominano la causa. Il file è in
  `out/audio-mic/` (non in git), ma `coredump` è tornato su `disabled`.
- **Errore mio, ancora:** la scheda stavolta ha impiegato 16 s a comparire e il mio script
  aspettava 10 s: attesa portata a 30 s.

## 2026-11-05 sera, 19:00-19:10: il codec interno, ipotesi e smentita

- **Riprodurre silenzio verso il codec interno** (`hw:0,1`) manda in crash l'ADSP con lo
  stesso `AHB Bus hang` dei microfoni: non è la cattura, è ogni uso del codec digitale.
- **Ipotesi, provata e smentita:** in tutti gli alberi SDM670/710 il clock `ahbix-clk` del
  codec è un `fixed-clock` che non fa nulla; l'ho sostituito con il clock vero
  `LPASS_CLK_ID_INTERNAL_DIGITAL_CODEC_CORE` (patch al device tree, kernel ricompilato,
  recovery riscritta da ssh). Il firmware dell'ADSP rifiuta il comando (`error = 0x2`),
  il probe del codec fallisce e **la scheda audio non compare più**. Patch ritirata,
  recovery di prima riscritta e riletta (`6afcfc5e…`), scheda tornata in circa 1 s.
  Le immagini intermedie sono in `out/prev/` (non in git).
- **Altro errore mio:** il mio aiuto di spegnimento si fermava a metà del recupero
  dell'ADSP (`crashed`, `offline`, `running`) e lo lasciava acceso: l'ho trovato
  `running` prima di riavviare e l'ho fermato a mano; ora aspetto 8 secondi.

## 2026-11-05 sera, 20:00-20:50: il display si accende

- **Causa del nero: `handover` spento per default.** Il driver del pannello ricopre lo stato del
  bootloader solo con `handover=1`; senza, ogni caricamento stampava «panel re-initialised»
  (reset e reinizializzazione del pannello), e con questo host DSI il pannello resta nero.
  Il riferimento dava il parametro per acceso; nel codice di questo albero non lo è.
- **Poi serve un ciclo DPMS.** Con `handover=1` il pannello è «taken over», il proprietario vede
  un lampo bianco e poi nero; un ciclo di risparmio energia (spento, 1,5 s, acceso: è quello che
  fa `gts4lv-panel-kick` nel riferimento) rifà l'accensione, e le barre di colore compaiono.
- **Esito, dal proprietario:** foto delle barre SMPTE complete e nell'ordine giusto, girate di 90°,
  senza cucitura visibile fra le due metà DSI.
- **Smentite misurate:** caricare `msm` a 4,8 s invece che a 2000 s (il PLL dà lo stesso errore nel
  probe del PHY, che è rumore: in esercizio i clock sono giusti, VCO 1,88 GHz, pixel clock 156,9 MHz
  per metà); `frame_done_cnt` resta 0 anche con le immagini a schermo.
- **Fatto:** `device/gts4lvwifi/rootfs/overlay/etc/modprobe.d/gts4lv-display.conf` (`handover=1`) e
  `usr/local/sbin/gts4lv-display start|kick|bars`. Lo script ha girato intero (20:47:55, `rc=0`);
  cosa mostrava lo schermo in quella corsa non è riferito. Non si carica al boot.
- **Due errori miei:** un file `modules-load.d` per anticipare `msm` non funziona (rispetta la
  blacklist) e l'ho tolto; lo script usciva con 141 (SIGPIPE da `awk` con `pipefail`), corretto.

## 2026-11-05 sera, 20:05-20:12: il tocco visto da evdev

- **Il proprietario ha toccato** mentre sul tablet erano visibili le barre di colore (il segnale
  è stato dato sullo schermo, perché le istruzioni scritte fra un comando e l'altro non le legge:
  due registrazioni precedenti sono andate perse senza nessun tocco). `evtest` su `event3`: 19.153
  eventi, 173 contatti aperti e 173 chiusi (nessuno bloccato), `BTN_TOUCH` 98/98, slot 0-3, **fino a
  4 dita insieme**, pressione 2-30, x 122..1530 e y 148..2551.
- **Bordi:** in basso arriva a 2551 su 2559 e a destra a 1530 su 1599; a sinistra 122 e in alto 148,
  con quasi nessun campione vicino. Può essere come sono stati toccati gli angoli o un margine del
  sensore: non lo so. Uno strisciamento deciso sul bordo lo chiarisce.
- **`scripts/touch-summary.py`** riassume un log di `evtest`.
- **Come parlare con il proprietario:** istruzioni in grande, nel messaggio finale o sullo schermo
  del tablet, mai a metà di una serie di comandi; un segnale visibile sul tablet vale più di un
  conto alla rovescia scritto.

## 2026-11-05 sera, 20:55-21:00: luminosità e refresh del display

- **Luminosità:** 160, 100, 40, 255, 160 a intervalli di 8 s con le barre a schermo; ogni valore
  riletto uguale; il proprietario: «esecuzione perfetta di tutte le luminosità senza artefatti».
- **Refresh:** TE a circa 29 Hz a riposo, circa 63 Hz con i fotogrammi in arrivo (`modetest -v` 63,3
  flip/s). I 30 Hz misurati prima erano col pannello resettato e nero.
- **Lo sfarfallio visto durante la misura dei 60 Hz** era del test `modetest -v`, che alterna i
  fotogrammi per costruzione: provato dal proprietario con barre ferme (stabili) e poi con `-v`
  (sfarfalla). Il pannello non ha difetti noti; per giudicarlo si usa `gts4lv-display bars`, non `-v`.
- **Istruzioni al proprietario:** funzionano se sono scritte grandi nel messaggio e se il segnale
  arriva sullo schermo del tablet (le barre); un conto alla rovescia scritto fra i comandi non si legge.

## 2026-11-05 sera, 21:00-21:10: i quattro altoparlanti

- **Toni da un amplificatore alla volta** (1-4 beep, due ordini diversi) e **canale sinistro/destro**:
  risposte a orecchio incoerenti (RR «dal basso» e poi «in alto a sinistra»; con tutti e quattro accesi
  tutto sembra uscire dall'alto). Un test mirato ha dato il dato certo: i **due di sotto soli (RL, RR)
  si sentono dal basso**. Quindi tutti e quattro suonano.
- **Registri I2C durante il tono:** i quattro amplificatori hanno lo stesso stato (`PWR_CTRL1` 1,
  `PWR_CTRL2` `0x3721`, stessi flag), nessun errore di accensione nuovo.
- **Non provato:** quale indirizzo è quale altoparlante, e se sinistra è sinistra. Dettagli in
  `docs/AUDIO-PLAN.md`.
- **Script:** `gts4lv-tone` ha `beeps` e `channel`; il controllo del firmware contava `5-004x` e
  falliva col bus I2C 4 di questo boot (il numero del bus cambia): ora conta gli amplificatori per
  indirizzo. Un test che «rifiuta di suonare» è stato questo, e il rifiuto era corretto.

## 2026-11-05 sera, 21:10-21:25: il Wi-Fi si associa

- **Credenziali** date dal proprietario in chat; scritte **solo sul tablet** come hash
  (`wpa_passphrase`, riga in chiaro tolta), file 600. Verificato che né la password né il nome
  della rete compaiono nel repository (`git grep`) né nei file non tracciati.
- **Esito:** associato in circa 12 s su 5 GHz (canale 104), DHCP, rotta su `wlan0` con metrica 600
  senza toccare quella del cavo, DNS e HTTPS ok, ping 27 ms, download circa 60 Mbit/s a -72 dBm.
  `disconnect`/`reconnect` ok. NTP imposta l'ora: **il problema dell'orologio al 1977 è risolto
  finché c'è il Wi-Fi** (resta l'RTC non scrivibile).
- **Una regressione mia, trovata e corretta:** abilitando `wpa_supplicant@wlan0` al boot, la unit
  (ordinata prima di `network.target`, e in attesa di `wlan0`, che compare solo quando parte il
  modem, cioè dopo `sshd`, che aspetta `network.target`) teneva fermo tutto per 90 secondi: **ssh
  raggiungibile solo a 91 s** e il Wi-Fi non partiva (dipendenza fallita). Ora la unit non è
  abilitata, un drop-in toglie il `Before=network.target` e la condizione sulla config, e una regola
  udev la avvia quando `wlan0` compare. Dopo il riavvio: **ssh a 7 s, Wi-Fi con indirizzo a 25 s**,
  nessuna unit fallita. Nell'immagine: drop-in, regola udev e `systemd-timesyncd` abilitato
  (le credenziali no, e la unit non parte senza config).
- **Come è passata la password:** come stdin a `wpa_passphrase` sul tablet, non nella riga di
  comando di quel programma; è comunque nella cronologia di questa sessione di lavoro del proprietario.

## 2026-11-05 sera, 21:30-22:20: PipeWire, Bluetooth audio e il livello

- **Server audio:** PipeWire/WirePlumber installati; PipeWire rifiuta di girare come root
  (`ConditionUser=!root`) e gira per `alarm`, con sessione permanente e gruppi `audio`, `lp`, `video`.
  L'uscita Pro Audio della scheda ha 8 canali «aux» e un flusso stereo non trovava dove andare
  (due toni di prova senza suono): una regola di WirePlumber la presenta come stereo FL FR a 16 bit.
- **Bluetooth, accoppiamento:** il primo tentativo falliva («passkey o PIN errati» sul telefono): il tablet
  chiedeva `Confirm passkey (yes/no)` e nessuno rispondeva (il mio `agent NoInputNoOutput` non aveva
  sostituito l'agente). Un agente che risponde sì per una finestra breve ha accoppiato il telefono
  (un Pixel 10); dopo l'accoppiamento la finestra è chiusa.
- **Bluetooth, audio:** mancava il server audio (nessun «Audio Sink»); poi il monitor Bluetooth di
  WirePlumber non registrava gli endpoint A2DP perché `alarm` non ha una seat di logind (disattivato
  il controllo per il profilo main); poi il nodo non si creava (`failed to create node from factory
  'adapter'`) con il codec vendor di Google; limitati i codec a SBC, SBC-XQ e AAC. Dopo la
  riconnessione e un riavvio di WirePlumber la musica del telefono ha suonato dal tablet. Non so quale
  delle ultime due modifiche abbia sbloccato il nodo.
- **Altoparlanti:** all'inizio solo i due lato fotocamera; poco dopo, dopo i riavvii, tutti e quattro. Non so
  perché.
- **Livello:** quello di -18 dB con analogico al minimo era una mia scelta prudente e rendeva la musica
  molto più flebile di Android. Quattro fasi con la musica e la protezione nel percorso: la più chiara è
  digitale 0 dB / analogico 0; con analogico +6 suonava più piano (probabilmente la protezione che
  limita, non verificato). `gts4lv-audio` ora porta gli amplificatori a 0 dB / analogico 0, solo dopo aver
  confermato il firmware di protezione sui quattro, e mai sopra 0 dB.
- **Non fatto:** riconnessione del telefono dopo un riavvio del tablet; l'audio non parte al boot
  (`gts4lv-audio.service` esiste ma non è abilitata, per il rischio dell'ADSP acceso); microfoni.

## 2026-11-05 sera: l'immagine v6

- **Costruzione:** `scripts/build-rootfs.sh` in 4 minuti, `verify-rootfs.py` ok (controlla anche che
  `board-2.bin` non ci sia, che le unit giuste siano abilitate e che `qrtr-ns` no). Un primo tentativo è
  stato interrotto a metà (comando in primo piano ucciso, codice 137): rifatto in background; il tablet
  non era stato toccato.
- **Paracadute prima di sostituire:** copiate in `out/prev/` la recovery attuale (`6afcfc5e…`) e gli extent
  della v1; la recovery di Lineage originale ha ancora lo sha256 giusto (`81f4d19e…`); la vecchia
  immagine rinominata sul tablet in `rootfs-v1.img` (c'erano 21,5 GiB liberi). La configurazione Wi-Fi
  (solo hash) copiata in `out/wifi-wlan0.conf`; l'ADSP fermato prima di lasciare Arch.
- **Passaggio:** `boot-android` → Lineage in 42 s, adb ok, `rootfs-to-tablet.sh` (1 min 38 s,
  copia verificata per sha256, 80 extent che coprono i 6.442.450.944 byte), ramdisk ricostruita con gli
  extent nuovi (verificato che la ramdisk li contenga), `flash-recovery-adb.sh` (scritta e riletta,
  `a473ef0a…`), `adb reboot recovery`: Arch su e raggiungibile via ssh.
- **Esito:** `running`, 0 unità fallite, rootfs da 5,9 GB con 2,0 GB usati; credenziali Wi-Fi rimesse e
  Wi-Fi connesso in 11 s; NTP; modem, `hci0`, tocco (ora caricato al boot) e batteria ok; la unit di
  `wpa_supplicant` parte da udev e **dopo un riavvio**: ssh a 7 s, Wi-Fi con indirizzo a 20 s, ping 0 %
  di perdita, nessuna unità fallita. L'ora si sincronizza via NTP a circa 66 s dal boot.
- **Un difetto trovato sulla v6 e corretto:** su un sistema fresco la scheda audio non aveva un profilo
  scelto (WirePlumber non ne aveva uno ricordato): PipeWire mostrava solo un sink finto, il «Dummy Output». Ora la regola di WirePlumber avvia la scheda in `pro-audio` e dà priorità agli
  altoparlanti: senza interventi a mano l'uscita predefinita è `Tab S5e speakers`.
- **Audio sulla v6:** `gts4lv-audio start`, tono da PipeWire a 40 % di volume: **il proprietario lo sente
  da tutti e quattro gli altoparlanti**; nessun errore di accensione.
- **Non fatto sulla v6:** riaccoppiare il telefono (le chiavi stavano nella vecchia immagine) e riprovare
  la musica via Bluetooth; avviare l'audio al boot.

## 2026-11-05 sera: limite raggiunto, passaggio a Codex

- Il proprietario ha detto di fermarsi (98 % del limite settimanale con Claude) e di aggiornare tutti gli
  `.md`: fatto in questo commit (`PROGRESS.md`, `README.md`, `device/gts4lvwifi/NOTES.md`,
  `docs/HARDWARE-MATRIX.md`, `docs/PORTING-ROADMAP.md`, `docs/AUDIO-PLAN.md`, `docs/TOUCH-PLAN.md`,
  `docs/RECOVERY-RUNBOOK.md`, e un avviso di stato in `docs/ROOTFS-PLAN.md`, `docs/DISPLAY-PLAN.md`,
  `docs/OMARCHY-PLAN.md`).
- Nello stesso commit due modifiche all'immagine, già provate sul tablet vivo: la regola di
  WirePlumber che avvia la scheda audio in `pro-audio` e dà priorità agli altoparlanti, e il modulo del
  tocco tolto dalla blacklist. L'immagine costruita (`out/rootfs/rootfs.img`, `0a5c84c4…`) le contiene già.
- Controlli prima del commit: `shellcheck` sugli script, `tests/test-pack-recovery.py` ok, nessuna
  password, nome di rete, indirizzo o hash di chiave nelle righe aggiunte. `yamllint` in CI gira solo su
  `.github/workflows`: sull'intero albero fallisce per l'YAML del kernel in `src/`, che non è nostro.
- **Non è stato spinto niente.** I commit sono tutti locali (`git log 37703bd..HEAD`).
- Non iniziato: microfoni (ADSP in crash), riconnessione Bluetooth dopo il riavvio, abbinamento
  amplificatore-altoparlante, microSD, sensori, sospensione, fotocamere, GL/Vulkan, M8 e M9.
  L'elenco ordinato è nella sezione «Prossimi blocchi» in cima.

## Prossimo passo

Vale la sezione «Passaggio di consegne» in cima a questo file.

## 2026-11-06 mezzogiorno: sessione M8, touch e sensori sincronizzati

- SDDM avviato dopo `gts4lv-display`: Hyprland usa DSI-1 2560x1600 a scala 3,2 con MSM/FD615,
  Quickshell e squeekboard. Avviarlo prima del servizio display lo legava invece a simpledrm e
  llvmpipe; ora una dipendenza systemd ordina display prima di SDDM, che resta disabilitato al boot.
- Il touch è vivo anche nella sessione grafica: una cattura ha 5.077 righe, 4.193 eventi ABS e
  press/release corretti. Il controller è ruotato rispetto al pannello nativo landscape; la
  configurazione persistente usa DSI-1 e `transform=3`. Il debug evento-per-evento è stato spento.
- Omarchy bloccava dopo 60 s e spegneva subito lo schermo dietro il lock. Durante il bring-up è attivo
  Stay awake; la configurazione persistente porta il lock a 600 s, mantenendo il toggle rapido.
- SSC enumera LSM6DSM, VEML3328 e AK0991x. Le prime catture sembravano immobili perché movimento e
  campionamento non erano sincronizzati. Durante prove concordate col proprietario, 263 campioni
  accelerometro sono cambiati (X 6,364..7,185, Y -1,006..-0,239, Z 6,636..7,496 m/s²), il giroscopio
  diretto è cambiato su tutti gli assi e D-Bus ha emesso `normal`, `right-up`, `normal`. Il moto SSC è
  quindi reale. Le prove con registry in RAM scrivibile e `is_dri=0` erano inutili, sono state
  annullate e `persist` è di nuovo esposto `ro,norecovery`.
- Il record factory `placement` è tutto zero, mentre la configurazione Samsung dichiara `x=-y,
  y=-x, z=-z`: la regola udev ora passa questa matrice a `iio-sensor-proxy`. L'autorotazione specifica
  per il Tab S5e mantiene il touch a `(transform pannello + 3) mod 4` e usa il nome unità atteso dal
  toggle Omarchy. La prima prova ruotava il pannello nel verso opposto, lasciando l'immagine a 180°
  dalla posizione attesa dopo un quarto di giro. Scambiati i transform 1 e 3, il proprietario ha
  confermato immagine e touch «perfetti» nelle rotazioni vive; il servizio resta abilitato per `alarm`.

## 2026-11-05 notte: GPU passata e primo rootfs M8 costruito

- Sul tablet vivo, dopo `gts4lv-display start`, `scripts/gpu-smoke.sh` ha verificato OpenGL 4.6 / ES
  3.2 con Freedreno `FD615` e Vulkan 1.3 con Turnip `Adreno 615`; nessun `llvmpipe`, reset o errore.
  I tentativi separati con log continuo sono in `out/gpu-egl-first/` e `out/gpu-vulkan-first/`.
- M8 è iniziato sul PC. `scripts/build-omarchy-rootfs.sh` costruisce in `out/rootfs-omarchy/`, separato
  dalla v6. Il primo risultato contiene 631 pacchetti in un ext4 da 12 GiB: Omarchy 4.5.0,
  `omamobile-shell` 0.2.100, Hyprland mobile 0.57.0, Mesa e Turnip ALARM 26.2.6. SDDM è disabilitato.
- Trovato nel resolver reale: Omarchy stable porta ancora Aquamarine ABI 14, incompatibile con
  Hyprland mobile e `hyprtoolkit` correnti (ABI 15). I quattro componenti ABI vengono quindi da Arch
  `extra` e sono protetti insieme a Mesa contro una sostituzione dai repository Mali/stable.
- Keyring, sha256 e fingerprint sono fissati in `omarchy-repos.lock`. `e2fsck`, il verificatore base e
  quello M8 passano. Hash locali: immagine `d95c8eb2…`, tar `f55c6ff1…`, lista pacchetti `4ae51b6d…`.
- Il tablet non è stato scritto e continua a eseguire la v6. Il prossimo passo è copiare questa immagine
  da Lineage, ricostruire la recovery con i suoi extent, avviarla e solo dopo lanciare Hyprland a mano.

## 2026-11-06 mattina: M8 vivo e sensori SSC

- Il rootfs M8 da 12 GiB è sul tablet e si avvia. Installati anche i pacchetti della manifestazione
  ufficiale Omarchy disponibili per questa architettura: 930 pacchetti totali. Omarchy 4.5.0-3,
  Omarchy Mobile shell 0.2.100, Hyprland mobile 0.57 e Mesa/Turnip ALARM 26.2.6. Una sessione manuale
  ha mostrato DSI-1 a 2560x1600, scala 3,2, con Hyprland, Quickshell e squeekboard attivi.
- `hexagonrpc 0.5.0-2` contiene una patch riproducibile che restituisce al DSP gli errori RPC non
  supportati senza terminare il listener. La partizione `persist`, come `dsp` e `vendor`, è montata
  `ro,noload`; al DSP sono esposti sotto `/run` soltanto i 79 record di registry, i 18 JSON di
  configurazione, le librerie ADSP e i valori socinfo del dispositivo.
- `gts4lv-sensors-{prepare,root}.service` e `gts4lv-sensors.service` avviano ADSP, root-PD e sensors-PD;
  un'attesa di readiness impedisce a `iio-sensor-proxy` di partire prima che SSC pubblichi
  l'accelerometro. Dopo due reboot: quattro unità attive, zero fallite, `HasAccelerometer=true` e
  `HasAmbientLight=true`. Misure reali: accelerazione con gravità circa 9,89 m/s², luce 124-129 lux,
  magnetometro e bussola continui. `HasProximity=false`: SSC non offre quel sensore su questo modello.
- Il touch continua a fare probe come FTS1BA90A su `event3`, GPIO 123 level-low. In questo boot il
  contatore è rimasto a 1 perché non è ancora arrivata una prova fisica; il test evdev del giorno prima
  resta valido. Il logging passivo è stato attivato in attesa di 2-3 swipe del proprietario.
- Stato al passaggio: dopo il secondo reboot due processi `sshd-auth` sono entrati in spin al 99 % e
  non hanno risposto a SIGKILL. La rete e il kernel rispondono, ma il job di restart di sshd e poi lo
  stop dell'ADSP dalla console seriale sono rimasti bloccati. Serve Power + Volume-giù; al ritorno si
  verifica prima SSH/clock, poi il log touch. Nessuna partizione Android è stata scritta.
