# Movie Preflight

App Mac (Swift/SwiftUI, come Dolly) che controlla un film prima della proiezione: si trascina un mp4/mkv/avi (o più file, o una cartella) e restituisce dati tecnici e segnalazioni su immagine, audio e sottotitoli.

## Cosa controlla
- **Contenitore**: estensione/contenuto, durata, titolo nei metadati con pubblicità, capitoli, file troncato.
- **Video**: risoluzione, bitrate per pixel, frame rate (variabile/insolito), interlacciamento (dichiarato e rilevato), HDR, colore non dichiarato, bande nere incorporate, neri iniziali/finali/centrali, fermi immagine, errori di decodifica, buchi nel flusso, keyframe.
- **Immagine**: OCR (Vision) sui primi 45 s e sugli ultimi 150 s per trovare scritte/crediti del torrent.
- **Audio** (per le prime 3 tracce; nei 5.1 anche **dialoghi contro musica**: confronto tra il canale centrale e il fronte sinistro/destro nei momenti con parlato): volume integrato, LRA, picchi, salti bruschi di volume, parti sommesse/forti rispetto al livello tipico, silenzi, buchi nei pacchetti, sincronia audio/video, lingua mancante, predefinite ambigue.
- **Sottotitoli**: lingua reale delle battute contro quella dichiarata (NaturalLanguage), crediti/pubblicità, battute sovrapposte o troppo veloci, caratteri rovinati, durata rispetto al film, predefiniti/forzati incoerenti, formato a immagine.

## Correzioni
Dalle segnalazioni (pulsante «Correggi…») o dal pulsante in alto si apre una finestra che mostra tutto quello che verrà fatto, da confermare:
- traccia **audio predefinita**, **sottotitoli predefiniti** (o nessuno), **lingua** delle tracce senza etichetta;
- **togliere pubblicità e crediti** dai sottotitoli, **eliminare** tracce audio/sottotitoli;
- **tagliare** l'inizio o la fine (crediti del torrent nell'immagine) senza ricodificare, sui fotogrammi chiave;
- **alzare i dialoghi** (canale centrale +4 dB con limitatore) nei 5.1 dove la musica li copre;
- **convertire in Dolby Digital (AC-3)** le tracce che non sono Dolby (fino a 5.1; 640 kb/s per il 5.1, 384 per lo stereo), con controllo che il volume non cambi;
- **portare il volume a un livello standard** (-24 LUFS) con un **guadagno fisso**: sale o scende tutto insieme, la dinamica non cambia;
- **deinterlacciare l'immagine** (`bwdif`, ricodifica x264/x265 ad alta qualità nello stesso codec e profondità colore);
- (avanzata, sconsigliata) **compressione dinamica** `dynaudnorm`+`alimiter`: può abbassare la musica sotto il parlato e rialzarla dove c'è solo musica.

**Principio: meglio non toccare un file che peggiorarlo.** Solo strumenti standard del settore (ffmpeg: `bwdif`, `loudnorm`-style gain fisso, `alimiter`, `libvmaf`; mkvtoolnix) e ogni correzione di audio/immagine viene misurata prima e dopo; se non migliora, viene annullata e il file resta com'è:
- audio: nessuna distorsione (picco ≤ 0 dBFS), livello obiettivo raggiunto, nei 5.1 la «musica sopra i dialoghi» non deve aumentare di oltre 1,5 punti, la dinamica non deve crescere con la compressione;
- immagine: l'interlacciamento deve sparire e il **VMAF** (Netflix) su 3 tratti deve restare ≥ 93 (minimo ≥ 88) rispetto al deinterlacciato ideale.
Non offerti perché con questo ffmpeg non sarebbero di livello professionale: conversione HDR→SDR (mancano `zscale`/`libplacebo`) e ingrandimento con IA (Topaz Video AI non installato).

Sicurezza: solo etichette in un mkv → modifica sul posto con mkvpropedit, senza riscrivere il film. Ogni altra correzione scrive un file temporaneo, lo **verifica** (numero di tracce, durata, buchi nell'audio rispetto all'originale) e solo allora sostituisce; l'originale resta come `<nome>.orig_backup.<ext>` e «Annulla la correzione» lo rimette. Da riga di comando: `dist/moviepreflight --fix film.mkv --audio-default 1 --sub-default none --lang s1=fra --clean-sub 0 --trim-start 4 --normalize 0` (numeri da 0).

## Uso
    ./build.sh                       # dist/Movie Preflight.app (+ dist/moviepreflight per la riga di comando)
    dist/moviepreflight --analyze film.mkv # rapporto testuale
    python3 tests/test_moviepreflight.py   # 45 controlli su film sintetici con difetti noti

ffmpeg e ffprobe vengono copiati dentro l'app dallo script `tools/bundle_ffmpeg.py` (con le loro librerie, percorsi riscritti: funziona anche senza Homebrew; `BUNDLE_FFMPEG=0 ./build.sh` per saltare e usare quelli di /opt/homebrew/bin). Per distribuire l'app pubblicamente tieni conto della licenza di ffmpeg (la build di Homebrew include componenti GPL). Solo Apple Silicon (arm64), macOS 13+. Non modifica mai i file analizzati.

## Soglie
Tarate su 9 film reali della libreria "Opere Prime" (nessun falso positivo su OCR/pubblicità/interlacciamento). Le soglie di dinamica audio (LRA, salti, sommesso/forte) sono volutamente larghe: i film reali normali hanno LRA 18-23 LU. Per i 5.1, la misura «musica sopra i dialoghi» (secondi con parlato in cui il fronte supera il centro di oltre 6 LU) vale 0-10% nei film normali della libreria, 15% in Ex Machina e 26% in Flow (colonna sonora invadente): nota sopra il 12%, attenzione sopra il 20%.

## Icona
`icon/generate_icon.py` (generata con Codex a partire dall'icona di Dolly) disegna `icon/MoviePreflight-1024.png`; `icon/MoviePreflight.icns` si costruisce con `sips` + `iconutil` (vedi lo script di build).
