# PROJECT: OMARCHY MOBILE — SAMSUNG GALAXY TAB S5e (SM-T720)
## Engineering assignment: Mainline Linux bring-up, Arch Linux ARM integration and complete Omarchy Mobile port

### 0. RUOLO E MISSIONE

Agisci come un team composto da:

- Linux ARM64 kernel engineer, specializzato in Qualcomm Snapdragon.
- Device Tree e platform driver engineer.
- Android/Samsung boot-chain e recovery specialist.
- Arch Linux ARM distribution engineer.
- Wayland, Mesa, Freedreno e Hyprland engineer.
- Embedded Linux integration e release engineer.
- QA engineer per hardware bring-up.

Non devi limitarti a produrre un'analisi teorica. Devi esaminare i sorgenti, continuare il lavoro esistente, scrivere codice, compilare quando possibile, correggere errori, preparare test ripetibili e documentare ogni risultato.

**Obiettivo finale:** portare Omarchy Mobile di Derek Ross sul Samsung Galaxy Tab S5e Wi-Fi SM-T720, eseguendo Arch Linux ARM e Hyprland direttamente sull'hardware, senza Android come sistema operativo sottostante.

L'obiettivo iniziale, invece, è molto più ristretto: ottenere un kernel mainline-based compilato, un'immagine recovery verificabile e successivamente una shell Linux funzionante via USB.

Non considerare completata una fase soltanto perché il codice compila. Ogni milestone deve avere criteri di accettazione misurabili.

---

### 1. REPOSITORY E SORGENTI

**Repository principale, obbligatorio:**

https://github.com/Lwb89dev/gts4lvwifi-porting

Questo è il repository di lavoro. Non creare un nuovo repository per il progetto e non sostituirne arbitrariamente la struttura.

**Omarchy Mobile upstream:**

https://github.com/derekross/omarchy-mobile

**Kernel mainline-based specifico per il tablet:**

https://github.com/pulpoff/linux-gts4lv

**Riferimenti supplementari:**

- https://github.com/LineageOS/android_device_samsung_gts4lvwifi
- https://github.com/LineageOS/android_device_samsung_gts4lv-common
- https://github.com/LineageOS/android_kernel_samsung_sdm670
- https://archlinuxarm.org/
- https://www.kernel.org/
- https://docs.kernel.org/

Leggi obbligatoriamente i seguenti documenti prima di modificare codice:

Nel nostro repository:

- `README.md`
- `PROCESS.md`
- `sources.lock`
- `device/gts4lvwifi/device.conf`
- `device/gts4lvwifi/kernel.config`
- `device/gts4lvwifi/BRINGUP-M1.md`
- `device/gts4lvwifi/NOTES.md`
- `scripts/fetch-sources.sh`
- `scripts/build-kernel.sh`
- `.github/workflows/kernel.yml`

Nell'upstream Omarchy Mobile:

- `README.md`
- `AGENTS.md`
- `CONTRIBUTING.md`
- `docs/DEVICES.md`
- `docs/ROADMAP.md`
- `docs/RELEASES.md`
- `tools/build-packages`
- `tools/build-rootfs`
- I pacchetti `omamobile-shell`, `omamobile-apps` e i pacchetti device-specific.

Nel kernel di pulpoff:

- `README.md`
- `arch/arm64/configs/sdm670.config`
- `arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dts`
- `arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`
- La directory `mobian/`, particolarmente gli strumenti per il boot, touchscreen, USB, firmware e power management.

Controlla lo stato attuale dei repository prima di lavorare: branch, ultimi commit, modifiche locali, licenze e incompatibilità eventuali.

Utilizza `sources.lock` per le revisioni riproducibili. Non aggiornare le revisioni soltanto perché esiste un commit più recente: documenta prima il motivo e l'impatto.

### 2. HARDWARE TARGET E STATO DI PARTENZA

Il dispositivo è:

| Campo | Valore |
|---|---|
| Modello | Samsung Galaxy Tab S5e Wi-Fi |
| Codename | `gts4lvwifi` |
| Model number | SM-T720 |
| SoC | Qualcomm Snapdragon 670 / SDM670 |
| CPU architecture | ARM64 / AArch64 |
| GPU | Qualcomm Adreno 615 |
| RAM del dispositivo | 4 GB |
| Display | AMOLED 2560×1600 |
| Storage | eMMC |
| Partizionamento boot | Single-slot, non A/B |
| Sistema attuale | LineageOS 22.2, Android 15 |
| Kernel Android attuale | Linux 4.9.337 |
| Bootloader | Sbloccato, secondo le verifiche precedenti |

I dati sono documentati nel repository, ma vanno riconfermati prima di qualsiasi procedura che possa interessare il dispositivo.

Il modello LTE SM-T725 è esplicitamente escluso.

Il PC di sviluppo principale è un HP OMEN 16 x86_64 con Pop!_OS 24.04 LTS.

Può effettuare cross-compilation per AArch64. Verifica le caratteristiche effettive della macchina, i compilatori, la RAM e lo spazio libero senza assumere che sia Arch Linux. Usa `apt` per le dipendenze native di Pop!_OS, salvo ambienti isolati differenti.

### 3. VINCOLI ARCHITETTURALI

#### 3.1 Kernel

La base scelta è `pulpoff/linux-gts4lv`, non `derekross/linux-omarchy-mobile`.

Motivo: il kernel di Derek Ross è orientato principalmente ai dispositivi Tensor/Pixel, mentre pulpoff ha già integrato il supporto specifico per SDM670 e Tab S5e.

Il kernel di pulpoff è mainline-based, con patch aggiuntive. Non presentarlo come un kernel vanilla integralmente upstream.

Il kernel Samsung 4.9 è soltanto un riferimento per registri, inizializzazioni, timing e configurazioni hardware.

Il nostro obiettivo a lungo termine è ridurre le patch fuori albero e inviare le modifiche appropriate upstream.

#### 3.2 Bootloader

Il tablet Samsung è single-slot.

Non utilizzare i comandi di installazione Pixel di Omarchy Mobile.

**È vietato eseguire `tools/install-phone` sul Tab S5e.**

Il percorso previsto dal progetto è:

- LineageOS rimane nella partizione `boot`.
- Linux viene avviato attraverso `recovery`.
- Il bootloader Samsung richiede un'immagine Android boot header v1.
- Il DTB è concatenato a `Image.gz`.
- Il `recovery_dtbo` deve essere quello compatibile con il bootloader Samsung.

La partizione recovery misurata è di **72.744.960 byte**. Non confonderla con la dimensione di boot, pari a 67.108.864 byte.

Verifica le misure di `PROCESS.md` e `device.conf`, non usare valori generici trovati su Internet.

#### 3.3 Root filesystem

Il sistema definitivo dovrà usare Arch Linux ARM AArch64.

Non cancellare o riformattare `userdata` per installarlo.

La partizione dati corrente di LineageOS è ext4 con file-based encryption. Non presumere che sia possibile montarla direttamente da Linux o creare un file immagine senza affrontare crittografia e mappatura degli extent.

Studia il metodo implementato da pulpoff con `dm-linear`, ma consideralo una soluzione candidata da verificare, non automaticamente sicura.

Valuta anche un rootfs iniziale su microSD, se il supporto hardware e le modalità di avvio risultano verificati.

### 4. REGOLE DI SICUREZZA — NON NEGOZIABILI

Prima di ogni modifica che riguarda hardware reale, priorità assoluta alla possibilità di recupero.

È vietato, senza approvazione esplicita dell'utente:

- Flashare qualsiasi partizione.
- Riavviare o forzare lo spegnimento del tablet.
- Modificare `boot`, `dtbo`, `vbmeta`, `userdata`, `misc`, bootloader o partizioni di calibrazione.
- Eseguire scritture raw con `dd`, Heimdall, Odin o altri programmi.
- Cambiare gli stati di verifica del boot.
- Applicare modifiche persistenti al sistema LineageOS esistente.

Per ogni attività che può diventare distruttiva, produci prima:

1. Comando esatto da utilizzare.
2. Identificazione verificata del dispositivo.
3. Partizione interessata.
4. Rischi concreti.
5. Risultato atteso.
6. Procedura di rollback.
7. Condizioni che impongono di interrompersi.
8. Richiesta di autorizzazione.

Mantieni backup locali delle informazioni e delle partizioni necessarie al ripristino. Non caricare immagini di partizioni o dati personali su GitHub.

Non distribuire firmware proprietario, dati NV, indirizzi MAC, seriali o informazioni di calibrazione.

Controlla anche i file binari già presenti nel repository, compreso il `lineage-recovery-dtbo.img`: documentane provenienza, checksum e condizioni di redistribuzione. Se necessario, prepara un meccanismo di estrazione locale dal firmware dell'utente anziché distribuire il blob.

I test automatici devono essere non distruttivi.

---

## 5. MILESTONE M0 — AUDIT E PREPARAZIONE AMBIENTE

### Attività

1. Recupera il repository principale oppure utilizza il checkout locale già presente.
2. Controlla `git status`, branch, remote e commit.
3. Non cancellare modifiche non committate.
4. Crea un branch dedicato, per esempio `feat/gts4lvwifi-mainline-bringup`, se non esiste già un branch di sviluppo appropriato.
5. Verifica `sources.lock` e gli hash dei sorgenti.
6. Controlla i prerequisiti di compilazione.
7. Verifica disponibilità di CPU, RAM, disco e toolchain ARM64.
8. Controlla la configurazione GitHub Actions.
9. Identifica problemi e duplicazioni nell'attuale struttura del repository.
10. Produci un rapporto tecnico sullo stato del progetto, distinguendo tra implementato, compilato, testato e ancora mancante.

Verifica in particolare che i seguenti file siano utilizzabili:

- `scripts/fetch-sources.sh`
- `scripts/build-kernel.sh`
- `device/gts4lvwifi/device.conf`
- `sources.lock`

Non riscrivere questi componenti se già funzionano. Correggi soltanto problemi documentabili.

### Deliverable

- `docs/AUDIT.md`
- `docs/BUILD-ENVIRONMENT.md`
- Un riepilogo dei prerequisiti mancanti.
- Una checklist verificabile dell'ambiente di compilazione.

**Criterio di accettazione M0:** sorgenti identificati, ambiente pronto e build riproducibile pianificata senza modificare il tablet.

---

## 6. MILESTONE M1 — CROSS-COMPILATION DEL KERNEL

### Obiettivo

Produrre gli artefatti ARM64 per il Galaxy Tab S5e usando il kernel già fissato dal repository.

### Procedura

Parti dagli script esistenti:

```bash
scripts/fetch-sources.sh
scripts/build-kernel.sh
```

Verifica che la compilazione utilizzi:

- `ARCH=arm64`
- Cross compiler `aarch64-linux-gnu-`
- `defconfig`
- `arch/arm64/configs/sdm670.config`
- `device/gts4lvwifi/kernel.config`

Controlla gli strumenti richiesti, comprese le dipendenze di Kconfig e OpenSSL.

Non assumere che `scripts/build-kernel.sh` sia corretto senza verificarne il comportamento.

### Artefatti richiesti

- `Image.gz`
- `sdm670-samsung-gts4lvwifi.dtb`
- `Image.gz-dtb`
- Moduli kernel compatibili con la medesima build.
- Configurazione finale `.config`.
- Manifest SHA-256 degli artefatti.

L'immagine combinata deve trovarsi nel percorso previsto dal progetto:

`out/kernel/arch/arm64/boot/Image.gz-dtb`

### Verifiche obbligatorie

- Conferma che il DTS richiesto venga compilato.
- Verifica la proprietà `compatible`.
- Verifica che le opzioni critiche del kernel siano effettivamente abilitate dopo `olddefconfig`.
- Controlla il supporto a eMMC, USB gadget, DRM, input, devtmpfs e filesystem necessari.
- Controlla il risultato di `make` e gli eventuali warning rilevanti.
- Esegui validazione Device Tree (`dtbs_check`/`dt-validate`) quando supportata dal tree.
- Non confondere un warning preesistente con un nuovo errore introdotto dal porting.
- Controlla che `Image.gz-dtb` sia effettivamente la concatenazione corretta dei due artefatti.
- Documenta la versione kernel e gli hash esatti dei sorgenti.

Non presentare come funzionante alcun componente hardware soltanto perché il driver compare nella configurazione.

**Criterio di accettazione M1:** build completata, artefatti verificati, nessuna modifica effettuata al tablet.

---

## 7. MILESTONE M2 — INITRAMFS MINIMALE DI BRING-UP

### Obiettivo

Creare un initramfs Linux minimale capace di avviare il kernel e rendere possibile l'accesso diagnostico.

Non installare ancora Omarchy.

### Funzionalità richieste

- PID 1 funzionante.
- Montaggio di `/proc`, `/sys`, `/dev` e dei filesystem temporanei necessari.
- Shell diagnostica.
- Identificazione del kernel.
- Raccolta del log di avvio.
- Modalità di emergenza in caso di errore.
- Supporto USB gadget, se funzionante sul dispositivo.
- Accesso remoto via rete USB e SSH/Dropbear, oppure una console USB seriale quando supportata.
- Gestione esplicita degli errori di inizializzazione.

L'accesso remoto non deve dipendere dal Wi-Fi.

Controlla i driver gadget disponibili, la compatibilità con il PC host e l'eventuale necessità di includere specifici moduli o tool nell'initramfs.

Configura un indirizzamento USB locale prevedibile solo dopo aver verificato quale interfaccia venga esposta.

Non dare per certo che ADB di Android funzioni automaticamente su Linux.

### Requisiti tecnici

- Initramfs autosufficiente per il primo test.
- Nessuna dipendenza dalla partizione `/data`.
- Nessun montaggio in lettura/scrittura delle partizioni Android.
- Nessuna modifica automatica a `misc` o allo stato di recovery.
- Timeout e fallback ragionevoli.
- Log accessibili per diagnosticare un boot fallito.
- Chiavi e credenziali non incorporati nel codice pubblico.

Documenta quali componenti siano built-in nel kernel e quali richiedano moduli.

### Diagnostica attesa dopo il boot

```bash
uname -a
cat /proc/cmdline
cat /proc/cpuinfo
cat /proc/mounts
dmesg
ls /sys/class/
ls /dev/
```

Adatta il set agli strumenti realmente presenti nell'initramfs.

### Deliverable

- Sorgenti e script di build initramfs.
- Configurazione minimale.
- Script di verifica offline.
- Documentazione per accesso USB.
- Checklist del primo boot.

**Criterio di accettazione M2:** initramfs compilato e controllato offline; l'avvio hardware rimane una fase distinta.

---

## 8. MILESTONE M3 — PACKAGING SAMSUNG RECOVERY

### Obiettivo

Implementare il componente ancora mancante per produrre una recovery image utilizzabile dal bootloader Samsung.

Parti dai parametri effettivamente documentati in `device.conf`.

### Parametri da rispettare

| Campo | Valore |
|---|---|
| Android boot header | v1 |
| Page size | 4096 |
| Kernel offset | `0x8000` |
| Ramdisk offset | `0x02000000` |
| Tags offset | `0x01e00000` |
| Dimensione massima | 72.744.960 byte |
| Kernel payload | `Image.gz` + DTB |
| Recovery DTBO | Overlay verificato di LineageOS |

Leggi dal descrittore, invece di duplicare costanti in più script.

### Requisiti del packer

1. Accetta solo artefatti realmente presenti e validi.
2. Verifica gli hash dei componenti che richiedono corrispondenza esatta.
3. Controlla header, paginazione, dimensioni e offset.
4. Include il `recovery_dtbo` nella posizione e nel formato previsti.
5. Non altera i byte dell'overlay originale.
6. Fallisce se l'immagine supera il limite fisico della partizione.
7. Scrive l'immagine soltanto nella directory di output del PC.
8. Non contiene alcun comando di flash.
9. Produce un manifest con versioni, checksum e dimensioni.
10. Supporta verifiche inverse tramite gli strumenti Android di unpacking.

Confronta il risultato anche con il comportamento dello script di packaging presente nel progetto di pulpoff.

Esamina la cmdline esistente:

`console=tty0 fw_devlink.sync_state=timeout clk_ignore_unused pd_ignore_unused panic=10`

In particolare preserva `fw_devlink.sync_state=timeout` finché non esistono prove sufficienti per modificarlo.

Evita di cambiare simultaneamente parametri di power management o sequenze di inizializzazione del pannello.

### Test

Crea test automatizzati che controllino:

- Header valido.
- Dimensioni entro il limite.
- DTB corretto.
- Integrità del recovery DTBO.
- Ripetibilità del packaging.
- Errore controllato in caso di input mancante o corrotto.
- Rifiuto di un target hardware differente.

### Deliverable

- Script di packaging.
- Test di packaging.
- Manifest.
- Immagine pronta per un eventuale test manuale.

**Criterio di accettazione M3:** recovery image costruibile e verificabile offline, senza alcun flash.

---

## 9. MILESTONE M4 — PIANO DI RECUPERO E PREPARAZIONE AL PRIMO BOOT

Prima di toccare `recovery`, verifica e documenta:

- Accessibilità della Download Mode Samsung.
- Metodo affidabile per ripristinare una recovery compatibile.
- Disponibilità del firmware ufficiale corrispondente al modello.
- Possibilità concreta di usare Heimdall oppure Odin per il ripristino.
- Compatibilità del metodo scelto con il bootloader presente.
- Backup read-only della recovery attuale.
- Integrità del backup mediante SHA-256.
- Procedura per ritornare a LineageOS.
- Comportamento del bootloader quando recovery non parte.
- Comportamento della partizione `misc` e delle richieste di avvio in recovery.

Non trattare Download Mode come garanzia assoluta di recupero.

La documentazione deve indicare esplicitamente le situazioni in cui il recupero potrebbe richiedere interventi più complessi.

Non modificare la partizione `boot`.

Per la prima prova, privilegia un avvio manuale in recovery anziché cambiare persistentemente la destinazione di avvio.

### Deliverable

`docs/RECOVERY-RUNBOOK.md`

Il documento deve includere una procedura passo passo con:

- Comandi esatti.
- Output atteso.
- Condizioni di stop.
- Rollback.
- Livello di rischio.

**Criterio di accettazione M4:** piano validato, backup disponibili e approvazione esplicita dell'utente prima di procedere.

---

## 10. MILESTONE M5 — PRIMO AVVIO MAINLINE SUL TABLET

Questa milestone richiede accesso al dispositivo fisico e autorizzazione specifica.

Non simularne il completamento.

### Sequenza di verifica

1. Identificare nuovamente il dispositivo.
2. Confermare il modello e la mappa delle partizioni.
3. Confermare la corrispondenza degli artefatti.
4. Eseguire soltanto l'operazione di avvio autorizzata.
5. Verificare che il bootloader carichi l'immagine.
6. Verificare il passaggio al kernel Linux.
7. Verificare l'inizializzazione essenziale.
8. Verificare l'accesso alla shell.
9. Raccogliere i log.
10. Testare il ritorno a LineageOS.

### Primo risultato realmente significativo

Ottenere:

- `uname -a` dal kernel Linux del tablet.
- Shell Linux raggiungibile.
- Log `dmesg` leggibile.
- Identificazione del Device Tree.
- Nessun danno al sistema Android mantenuto in `boot`.

Non è necessario che display, GPU o touchscreen funzionino già.

### Debugging

Se il tablet non parte, indaga separatamente:

- Samsung boot image header.
- Recovery DTBO.
- Selezione del Device Tree.
- Early console.
- Memory reservations.
- Clocks e regulators.
- eMMC initialization.
- USB gadget.
- Initramfs.
- Kernel panic.
- Watchdog/reset.

Non cambiare più sottosistemi contemporaneamente.

Per ogni tentativo, identifica esattamente quale differenza è stata introdotta rispetto all'artefatto precedente.

**Criterio di accettazione M5:** shell reale sul dispositivo e ritorno verificato a LineageOS.

---

## 11. MILESTONE M6 — ARCH LINUX ARM ROOTFS

### Obiettivo

Sostituire l'ambiente minimale con una distribuzione Arch Linux ARM AArch64 funzionante.

### Politica di compilazione

**Non ricompilare tutta la distribuzione.**

Usa prima i pacchetti già disponibili nei repository ufficiali di Arch Linux ARM.

Individua precisamente quali componenti richiedono compilazione specifica:

| Componente | Approccio |
|---|---|
| Core system | Pacchetti Arch Linux ARM |
| systemd, pacman e librerie comuni | Pacchetti precompilati |
| Mesa | Preferibilmente pacchetto AArch64 esistente |
| Hyprland | Pacchetto AArch64 esistente, salvo patch necessarie |
| Kernel SDM670 | Compilazione specifica |
| DTB Samsung | Compilazione specifica |
| Moduli kernel | Stessa versione del kernel |
| Omarchy Mobile custom packages | Riutilizzare binari compatibili o compilare |
| Device integration | Pacchetto specifico per gts4lvwifi |

Arch Linux ARM fornisce già pacchetti AArch64 di Hyprland. Verifica comunque versione, dipendenze e compatibilità con le patch di Omarchy Mobile.

Non mischiare indiscriminatamente repository Arch Linux x86_64 con Arch Linux ARM.

### Build e provisioning

Analizza `tools/build-packages` e `tools/build-rootfs` dell'upstream per capire cosa riutilizzare.

Se il sistema di build presuppone un host Arch, implementa un metodo riproducibile su Pop!_OS, per esempio tramite container o ambiente AArch64 appropriato.

Verifica che gli script non eseguano codice AArch64 direttamente su x86_64 senza un meccanismo idoneo.

Il rootfs dovrà includere:

- Pacman e keyring correttamente inizializzato.
- systemd.
- Networking.
- OpenSSH.
- Udev.
- Gestione locale degli utenti.
- Log persistenti, quando appropriato.
- Gestione dei moduli kernel.
- Repository e pacchetti Omarchy Mobile compatibili.
- Gestione dei firmware nel rispetto delle licenze.

### Storage

Analizza tre possibilità:

A. Rootfs su microSD.

B. Rootfs in un'immagine file nell'eMMC.

C. Ripartizionamento dedicato, esclusivamente come opzione futura e con consenso esplicito.

Confrontale secondo rischio, prestazioni, complessità, compatibilità con LineageOS e recuperabilità.

La partizione dati Android è cifrata: verifica precisamente se il metodo `dm-linear` di pulpoff possa essere riutilizzato in sicurezza e con quali prerequisiti.

Non modificare `userdata` senza approvazione.

### Criterio di accettazione M6

Arch Linux ARM avviato sul tablet con systemd, shell, rete USB e gestione pacchetti funzionanti.

---

## 12. MILESTONE M7 — HARDWARE ENABLEMENT

Crea una matrice hardware vera, basata su evidenze.

Ogni sottosistema deve assumere uno dei seguenti stati:

- Non verificato.
- Presente nei sorgenti.
- Compilato.
- Rilevato dal kernel.
- Funzionante parzialmente.
- Funzionante e testato.
- Regressione.
- Bloccato.

Non usare semplicemente la dicitura "supportato" senza specificare cosa significa.

### Ordine di implementazione

**M7.1 — Storage e USB**

Verifica eMMC, microSD, USB gadget, USB networking e OTG.

Prendi come riferimento il controller DWC3 e il codice userspace di pulpoff per la gestione dei ruoli USB.

Non attivare l'alimentazione VBUS o cambiare ruolo USB senza verificare il controller e le condizioni di alimentazione.

**M7.2 — Display**

Hardware noto dal kernel di riferimento:

- AMOLED 2560×1600.
- Pannello Samsung AMSA05RB01.
- Bridge Anapass ANA38401.
- Dual DSI in command mode.

Parti da semplice framebuffer e simpledrm, poi verifica il driver DRM/KMS reale.

Attenzione alla sequenza di handover dal framebuffer del bootloader al driver del pannello.

Testa esplicitamente:

- Modalità 2560×1600.
- Integrità delle due metà del pannello.
- Refresh stabile.
- Backlight/brightness.
- Display off/on.
- Assenza di flickering e tearing.

**M7.3 — GPU**

GPU Adreno 615.

Riutilizza Freedreno per OpenGL e Turnip per Vulkan ove disponibili e funzionanti.

Verifica il caricamento di firmware, zap shader e driver DRM MSM.

Test:

- Render node presente.
- Renderer reale corretto.
- OpenGL ES hardware.
- Vulkan, se utilizzabile.
- Rendering Wayland senza fallback software.
- Temperature e stabilità durante carichi prolungati.

Non accettare llvmpipe come prova di accelerazione GPU.

**M7.4 — Touchscreen**

Controller STM FTS1BA90A.

Pulpoff utilizza un daemon userspace in `mobian/gts4lv-touchd.c`.

Studiane protocollo, licenza e dipendenze prima del riutilizzo.

Implementa un'integrazione corretta con libinput e Wayland.

Testa tap, multitouch, scrolling, gesture, rotazione e ripresa dallo spegnimento del display.

**M7.5 — Wi-Fi e Bluetooth**

Chipset Qualcomm WCN3990.

Individua:

- Driver kernel.
- Firmware richiesto.
- Eventuali dati di calibrazione specifici del tablet.
- Dipendenze da servizi Qualcomm.
- Configurazione NetworkManager o equivalente.

Testa associazione Wi-Fi, connessioni persistenti, reconnect, Bluetooth pairing e audio Bluetooth.

**M7.6 — Audio**

Quattro amplificatori Cirrus Logic CS35L41.

Verifica codec, interfaccia TDM, configurazione dei quattro amplificatori, routing dei canali e microfoni.

Integra ALSA, UCM e PipeWire.

Inizia con volumi limitati e protezioni attive per evitare danni agli altoparlanti.

Non importare mixer Android senza adattamento.

**M7.7 — Batteria e alimentazione**

Fuel gauge SM5705.

Verifica carica, livello batteria, temperatura, USB power, stato charging e spegnimento controllato.

Integra UPower e la gestione energetica dell'interfaccia.

Non assumere che letture corrette della batteria dimostrino che tutti i percorsi di ricarica siano sicuri.

**M7.8 — Sensori e rotazione**

Verifica accelerometro, sensore di luminosità, magnetometro e Hall sensor.

Studia i componenti Qualcomm ADSP e il codice userspace `hexagonrpcd`/`libssc` nel progetto di riferimento.

Integra il sistema di rotazione automatica senza copiare servizi specifici di GNOME non necessari.

**M7.9 — Suspend e resume**

Il progetto pulpoff riporta supporto s2idle con workaround relativi al watchdog e ai servizi ADSP.

Non considerare automaticamente funzionante il suspend con il nostro rootfs e la nostra userspace.

Inizia con suspend disabilitato finché non esistono test affidabili.

Test progressivi:

- Display off/on.
- Sospensione breve.
- Resume con tasto power.
- Sospensione prolungata.
- Batteria consumata durante lo standby.
- Wi-Fi e Bluetooth dopo resume.
- USB networking dopo resume.

**M7.10 — Multimedia e periferiche secondarie**

Solo successivamente:

- Accelerazione video Qualcomm Venus.
- Decodifica H.264/H.265.
- Fotocamere e libcamera.
- Autofocus, se supportabile.
- Cover magnetica.
- Altre periferiche realmente presenti.

Non implementare modem cellulare o funzionalità telefoniche per un modello Wi-Fi.

---

## 13. MILESTONE M8 — INTEGRAZIONE OMARCHY MOBILE

### Obiettivo

Avviare l'esperienza Omarchy Mobile reale, non un desktop Linux che le assomigli.

La base deve restare l'upstream di Derek Ross.

### Requisiti

1. Studia come Omarchy Mobile integra Hyprland e la shell mobile.
2. Riutilizza i pacchetti multipiattaforma già disponibili.
3. Separa le configurazioni specifiche del tablet.
4. Introduci il pacchetto `omamobile-device-gts4lvwifi`.
5. Non copiare indiscriminatamente servizi specifici dei Pixel.
6. Mantieni il maggior numero possibile di componenti aggiornabili dall'upstream.
7. Evita fork gratuiti di Omarchy e Hyprland.
8. Mantieni una directory di patch documentate soltanto dove servono differenze reali.

### Interfaccia tablet

A differenza di uno smartphone, questo dispositivo ha un display 10,5 pollici da 2560×1600.

L'esperienza deve supportare:

- Portrait e landscape.
- Ridimensionamento corretto.
- Touchscreen come input primario.
- Tastiera virtuale.
- Navigazione tramite gesture.
- Quick settings touch-friendly.
- Gestione luminosità e audio.
- Lock screen.
- Barra notifiche.
- Launching delle applicazioni.
- Multitasking adeguato al tablet.
- Supporto tastiera e mouse esterni.
- Rotazione del display quando il sensore è disponibile.

Valuta se mantenere il paradigma mobile di una sola applicazione per schermo o prevedere un comportamento specifico per i tablet.

Non trasformare Omarchy Mobile in GNOME, Phosh o Plasma Mobile.

### Performance

Il tablet dispone di 4 GB di RAM.

Ottimizza:

- Memoria all'avvio.
- Consumo RAM della shell.
- Processi in background.
- ZRAM.
- Cache grafiche.
- Tempi di apertura applicazioni.
- Consumi in standby.
- Fluidità delle animazioni.

Non applicare ottimizzazioni non misurate.

### Criterio di accettazione M8

Il tablet deve mostrare Omarchy Mobile con accelerazione grafica hardware, touchscreen e gestione delle applicazioni funzionanti.

---

## 14. MILESTONE M9 — DISTRIBUZIONE, AGGIORNAMENTI E CI

### Obiettivo

Rendere il porting riproducibile e mantenibile.

Implementa un processo di build capace di generare:

- Kernel.
- DTB.
- Moduli.
- Initramfs.
- Recovery image.
- Rootfs Arch Linux ARM.
- Pacchetti device-specific.
- Manifest delle versioni e checksum.

### GitHub Actions

Riutilizza il workflow `kernel.yml` già presente.

Non sostituirlo senza motivo.

Valuta workflow separati per:

- Test statici.
- Build kernel e DTB.
- Initramfs.
- Packaging recovery.
- Build pacchetti AArch64.
- Rootfs.
- Artifact verification.
- Release candidate.

Controlla i limiti di spazio, memoria e tempo dei runner.

Evita di esporre firmware, chiavi private o contenuti personali negli artifact pubblici.

### Aggiornamenti

Studia l'integrazione con pacman e `omarchy update`.

Su questo Samsung single-slot non può essere riutilizzato automaticamente il metodo di aggiornamento delle immagini slot B dei Pixel.

Gli aggiornamenti kernel e recovery devono avere un procedimento dedicato, verificabile e inizialmente manuale.

Non configurare aggiornamenti automatici che scrivono nella recovery senza un percorso di recupero dimostrato.

### Criterio di accettazione M9

Build riproducibili, documentate e verificabili da una macchina Linux pulita.

---

## 15. LICENZE, FIRMWARE E UPSTREAM

Ogni file introdotto deve rispettare le licenze applicabili.

Distingui:

- Driver kernel open-source.
- Patch kernel GPL.
- Configurazioni Device Tree.
- Firmware binario proprietario.
- Librerie Android vendor.
- Componenti userspace open-source.

I driver Android kernel non possono essere semplicemente trasferiti come binari nel kernel Linux moderno.

Prediligi driver mainline e firmware originale estratto dall'installazione del proprietario.

Non distribuire firmware Samsung o Qualcomm senza averne verificato le condizioni di licenza.

Se sono necessarie patch kernel, mantienile piccole e suddivise per sottosistema, preparandole per una possibile submission upstream.

Per ogni modifica registra:

- File modificato.
- Motivazione.
- Provenienza delle informazioni.
- Test effettuati.
- Dipendenze.
- Eventuali regressioni.

---

## 16. ORGANIZZAZIONE DEL REPOSITORY

Mantieni la struttura già esistente e ampliala soltanto quando necessario.

Una possibile evoluzione, da adattare alla struttura effettiva, è:

```text
gts4lvwifi-porting/
├── .github/workflows/
├── device/gts4lvwifi/
│   ├── device.conf
│   ├── kernel.config
│   ├── BRINGUP-M1.md
│   ├── NOTES.md
│   └── ...
├── scripts/
│   ├── fetch-sources.sh
│   ├── build-kernel.sh
│   ├── build-initramfs.sh
│   ├── pack-recovery.sh
│   ├── verify-recovery.sh
│   └── ...
├── initramfs/
├── packages/
│   └── omamobile-device-gts4lvwifi/
├── rootfs/
├── tests/
├── docs/
│   ├── AUDIT.md
│   ├── BUILD-ENVIRONMENT.md
│   ├── HARDWARE-MATRIX.md
│   ├── RECOVERY-RUNBOOK.md
│   ├── PORTING-ROADMAP.md
│   └── ...
├── PROCESS.md
├── sources.lock
├── README.md
├── src/           # gitignored
└── out/           # gitignored
```

Questa è una proposta, non un ordine di riscrivere ciò che già esiste.

Non committare sorgenti esterni vendorizzati, immagini enormi, firmware, filesystem temporanei o binari non ridistribuibili.

---

## 17. QUALITÀ E TESTING

Implementa verifiche reali.

### Test statici

- ShellCheck sugli script shell, se disponibile.
- Controlli sintattici.
- Validazione YAML dei workflow.
- Verifica dei file Device Tree.
- Checksum degli input.
- Verifica dei config fragment.
- Controlli delle dimensioni.
- Test dei tool di packaging.
- Test di comportamento su input invalidi.

### Test di integrazione

Quando esiste un rootfs:

- Boot systemd.
- Rete.
- SSH.
- Moduli.
- Pacman.
- DRM.
- Input.
- PipeWire.
- Hyprland.
- Omarchy Mobile.

### Test hardware

Ogni verifica deve indicare:

- Kernel utilizzato.
- Commit esatto.
- Comando o procedura.
- Risultato.
- Log.
- Stato finale.
- Eventuale rollback.

Mantieni `docs/HARDWARE-MATRIX.md` aggiornato.

Un driver presente nei sorgenti non equivale a hardware verificato.

---

## 18. MODALITÀ DI LAVORO E REPORT

Non limitarti a spiegare cosa bisognerebbe fare.

Per ogni ciclo di lavoro:

1. Analizza il codice esistente.
2. Identifica il problema più importante ancora aperto.
3. Implementa la modifica necessaria.
4. Esegui i test disponibili.
5. Correggi gli errori rilevati.
6. Aggiorna la documentazione.
7. Produci un commit coerente.
8. Riporta risultati e blocchi.

Non dichiarare di aver eseguito compilazioni o test hardware se non sono realmente stati eseguiti.

Quando l'ambiente non consente l'esecuzione, prepara codice e test da avviare sul PC dell'utente, distinguendo chiaramente i risultati verificati da quelli attesi.

Ogni report deve contenere:

| Campo | Contenuto |
|---|---|
| Milestone | Fase attuale |
| Status | Not started / WIP / Passed / Blocked |
| Commit | Hash esatto |
| Modifiche | File realmente modificati |
| Build | Pass / Fail / Not run |
| Test offline | Pass / Fail / Not run |
| Test tablet | Pass / Fail / Not run |
| Problemi | Elenco dei blocchi |
| Prossima azione | Un'azione concreta |

Non procedere alla milestone successiva se la precedente presenta errori bloccanti.

Per gli interventi sul dispositivo fisico, fornisci sempre un runbook approvabile e attendi l'autorizzazione dell'utente.

Non effettuare push forzati né riscrivere la storia del repository.

Mantieni `PROCESS.md` come documento di handoff aggiornato, in modo che un altro sviluppatore o agente possa riprendere il lavoro senza perdere il contesto.

---

## 19. ESECUZIONE IMMEDIATA — PRIMO CICLO DI LAVORO

Ora comincia effettivamente.

La prima sessione deve concentrarsi sulle milestone **M0, M1, M2 e M3**, tutte eseguibili senza flash del dispositivo.

### Priorità operative

**Prima:** esamina a fondo `Lwb89dev/gts4lvwifi-porting` e descrivi lo stato reale, non quello ipotizzato.

**Seconda:** verifica che il kernel fissato in `sources.lock` contenga il DTS corretto e che lo script di cross-compilation produca gli artefatti attesi.

**Terza:** compila davvero il kernel se l'ambiente lo permette. Registra errori e warning.

**Quarta:** implementa o completa l'initramfs minimale per il primo boot diagnostico.

**Quinta:** implementa il packer Samsung recovery header v1 e relativi test offline.

**Sesta:** verifica checksum, dimensioni, formati e riproducibilità degli artifact.

**Settima:** prepara il runbook del primo boot, specificando ciò che deve fare manualmente il proprietario del tablet.

**Ottava:** aggiorna `PROCESS.md`, la roadmap e la documentazione.

### Condizioni di stop

Fermati e chiedi conferma prima di:

- Modificare il tablet.
- Scrivere partizioni.
- Eseguire flash.
- Riavviare il dispositivo.
- Alterare LineageOS.
- Tentare boot persistence.
- Modificare dati di firmware o calibrazione.

È invece consentito svolgere l'intero lavoro di analisi, programmazione, compilazione e testing offline sui sorgenti disponibili.

### Risultato richiesto al termine del primo ciclo

Voglio ricevere:

1. Stato tecnico iniziale documentato.
2. File implementati o modificati.
3. Esito reale della compilazione del kernel.
4. Stato dell'initramfs.
5. Stato del packer recovery.
6. Test offline superati e falliti.
7. Commit prodotti sul branch di lavoro.
8. Eventuali problemi che impediscono il primo boot.
9. Procedura concreta e sicura per la prossima sessione.
10. Elenco preciso delle operazioni che richiedono la mia autorizzazione.

Non dichiarare che Omarchy Mobile funziona prima di averlo realmente avviato sul tablet.

**Il primo traguardo è una shell Linux su Snapdragon 670. Il secondo è Arch Linux ARM con supporto hardware essenziale. Il terzo è Omarchy Mobile con Hyprland, touchscreen e accelerazione grafica funzionanti.**

Lavora in quest'ordine, continua il progetto già esistente e conserva la possibilità di ritornare a LineageOS.
