# Movie Preflight

App Mac (Swift/SwiftUI, come Dolly) che controlla un film prima della proiezione: si trascina un mp4/mkv/avi (o più file, o una cartella) e restituisce dati tecnici e segnalazioni su immagine, audio e sottotitoli.

## Cosa controlla
- **Contenitore**: estensione/contenuto, durata, titolo nei metadati con pubblicità, capitoli, file troncato.
- **Video**: risoluzione, bitrate per pixel, frame rate (variabile/insolito), interlacciamento (dichiarato e rilevato), HDR, colore non dichiarato, bande nere incorporate, neri iniziali/finali/centrali, fermi immagine, errori di decodifica, buchi nel flusso, keyframe.
- **Immagine**: OCR (Vision) sui primi 45 s e sugli ultimi 150 s per trovare scritte/crediti del torrent.
- **Audio** (per le prime 3 tracce; nei 5.1 anche **dialoghi contro musica**: confronto tra il canale centrale e il fronte sinistro/destro nei momenti con parlato): volume integrato, LRA, picchi, salti bruschi di volume, parti sommesse/forti rispetto al livello tipico, silenzi, buchi nei pacchetti, sincronia audio/video, lingua mancante, predefinite ambigue.
- **Sottotitoli**: lingua reale delle battute contro quella dichiarata (NaturalLanguage), crediti/pubblicità, battute sovrapposte o troppo veloci, caratteri rovinati, durata rispetto al film, predefiniti/forzati incoerenti, formato a immagine.

## Strumenti open source inclusi
Tutto dentro l'app, senza Homebrew (vedi `THIRD_PARTY_NOTICES.md` e `LICENSE`, GPL-3.0):
- **ffmpeg/ffprobe 9.0.2** compilato da `tools/build_ffmpeg.sh` con x264, x265, dav1d, SVT-AV1, **libvmaf** e **zimg** (filtro `zscale`: conversione HDR→SDR);
- **MediaInfo**: dettagli di codifica, profili Dolby Vision/HDR10+, nome commerciale dell'audio, sigla del gruppo di rilascio nel titolo;
- **whisper.cpp** (modello «base» da 148 MB, scaricato solo dopo il consenso dell'utente da File → Controlli sul parlato…): lingua realmente parlata di ogni traccia e sincronia dei sottotitoli. Tempi fini = zone di parlato di whisper ∩ energia nella banda della voce; sfasamenti misurati con correlazione di Pearson su 3 tratti del film (spostamento fisso o deriva da frame rate diverso: 25↔23,976 ecc.).
`tools/bundle_tools.py` copia gli eseguibili e le librerie in `Contents/Resources` riscrivendo i percorsi: verificato eseguendoli in un sandbox che vieta la lettura di `/opt/homebrew`.

## Correzioni
Dalle segnalazioni (pulsante «Correggi…») o dal pulsante in alto si apre una finestra che mostra tutto quello che verrà fatto, da confermare:
- traccia **audio predefinita**, **sottotitoli predefiniti** (o nessuno), **lingua** delle tracce senza etichetta;
- **togliere pubblicità e crediti** dai sottotitoli, **eliminare** tracce audio/sottotitoli;
- **tagliare** l'inizio o la fine (crediti del torrent nell'immagine) senza ricodificare, sui fotogrammi chiave;
- **alzare i dialoghi** (canale centrale +4 dB con limitatore) nei 5.1 dove la musica li copre;
- **risincronizzare i sottotitoli** (spostamento fisso o allungamento per frame rate diverso), **correggere la lingua** di una traccia audio dopo il riconoscimento del parlato, **togliere il titolo** dal contenitore (sigle di gruppi di rilascio);
- **convertire HDR in SDR** (`zscale` + tone mapping Hable, solo se non è Dolby Vision profilo 5), con controllo di luminanza e tag BT.709;
- **convertire in Dolby Digital (AC-3)** le tracce che non sono Dolby (fino a 5.1; 640 kb/s per il 5.1, 384 per lo stereo), con controllo che il volume non cambi;
- **portare il volume a un livello standard** (-24 LUFS) con un **guadagno fisso**: sale o scende tutto insieme, la dinamica non cambia;
- **deinterlacciare l'immagine** (`bwdif`, ricodifica x264/x265 ad alta qualità nello stesso codec e profondità colore);
- (avanzata, sconsigliata) **compressione dinamica** `dynaudnorm`+`alimiter`: può abbassare la musica sotto il parlato e rialzarla dove c'è solo musica.

**Principio: meglio non toccare un file che peggiorarlo.** Solo strumenti standard del settore (ffmpeg: `bwdif`, `loudnorm`-style gain fisso, `alimiter`, `libvmaf`; mkvtoolnix) e ogni correzione di audio/immagine viene misurata prima e dopo; se non migliora, viene annullata e il file resta com'è:
- audio: nessuna distorsione (picco ≤ 0 dBFS), livello obiettivo raggiunto, nei 5.1 la «musica sopra i dialoghi» non deve aumentare di oltre 1,5 punti, la dinamica non deve crescere con la compressione;
- immagine: l'interlacciamento deve sparire e il **VMAF** (Netflix) su 3 tratti deve restare ≥ 93 (minimo ≥ 88) rispetto al deinterlacciato ideale.
Non inclusi: ingrandimento con IA (Real-ESRGAN è troppo lento per un film intero), separazione voce/musica con Demucs (PyTorch, centinaia di MB), OCR dei sottotitoli a immagine, encoder ufficiali Dolby/DTS (non esistono open source).

Sicurezza: solo etichette in un mkv → modifica sul posto con mkvpropedit, senza riscrivere il film. Ogni altra correzione scrive un file temporaneo, lo **verifica** (numero di tracce, durata, buchi nell'audio rispetto all'originale) e solo allora sostituisce; l'originale resta come `<nome>.orig_backup.<ext>` e «Annulla la correzione» lo rimette. Da riga di comando: `dist/moviepreflight --fix film.mkv --audio-default 1 --sub-default none --lang s1=fra --clean-sub 0 --trim-start 4 --normalize 0` (numeri da 0).

## Uso
    ./build.sh                       # dist/Movie Preflight.app (+ dist/moviepreflight per la riga di comando)
    dist/moviepreflight --analyze film.mkv # rapporto testuale
    python3 tests/test_moviepreflight.py   # 56 controlli su film sintetici con difetti noti

Gli strumenti vengono copiati dentro l'app da `tools/bundle_tools.py` (`BUNDLE_FFMPEG=0 ./build.sh` per saltare e usare quelli di /opt/homebrew/bin). Per distribuire l'app pubblicamente tieni conto della licenza di ffmpeg (la build di Homebrew include componenti GPL). Solo Apple Silicon (arm64), macOS 13+. Non modifica mai i file analizzati.

## Soglie
Tarate su 9 film reali della libreria "Opere Prime" (nessun falso positivo su OCR/pubblicità/interlacciamento). Le soglie di dinamica audio (LRA, salti, sommesso/forte) sono volutamente larghe: i film reali normali hanno LRA 18-23 LU. Per i 5.1, la misura «musica sopra i dialoghi» (secondi con parlato in cui il fronte supera il centro di oltre 6 LU) vale 0-10% nei film normali della libreria, 15% in Ex Machina e 26% in Flow (colonna sonora invadente): nota sopra il 12%, attenzione sopra il 20%.

## Icona
`icon/generate_icon.py` (generata con Codex a partire dall'icona di Dolly) disegna `icon/MoviePreflight-1024.png`; `icon/MoviePreflight.icns` si costruisce con `sips` + `iconutil` (vedi lo script di build).
