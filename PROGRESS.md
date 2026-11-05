# Progresso del port gts4lvwifi

Aggiornato il 2026-11-04, branch `feat/gts4lvwifi-mainline-bringup`,
commit `875c90e` (allineato a `origin`). Questo file è il racconto unico
di quello che è stato fatto su questo SM-T720. Le misure riga per riga
stanno in `device/gts4lvwifi/NOTES.md`. Il runbook di rollback sta in
`docs/RECOVERY-RUNBOOK.md`.

Alcune frasi più vecchie sono superate da quello che segue. L'apertura
di `PROCESS.md` dice ancora che nessuna partizione è stata scritta.
L'intestazione di `docs/AUDIT.md` dice ancora che il tablet è tornato su
Lineage. `device/gts4lvwifi/BRINGUP-M1.md` dice ancora che l'immagine
con simpledrm non è stata flashata. `README.md` dice ancora che il
packer non esiste. Vale questo file.

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

## Prossimo passo

Il proprietario conferma se lo schermo resta acceso oltre i 40 s. Poi, nell'ordine:
mettere sul tablet il rootfs v3 (console seriale, ownership corretta) con una
nuova immagine che fissa anche i MAC del gadget (evita che l'interfaccia
dell'host cambi nome a ogni avvio), poi il Wi-Fi con il modem avviato a mano.
