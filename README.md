# Collaudo (nome provvisorio)

App Mac (Swift/SwiftUI, come Dolly) che controlla un film prima della proiezione: si trascina un mp4/mkv/avi (o più file, o una cartella) e restituisce dati tecnici e segnalazioni su immagine, audio e sottotitoli.

## Cosa controlla
- **Contenitore**: estensione/contenuto, durata, titolo nei metadati con pubblicità, capitoli, file troncato.
- **Video**: risoluzione, bitrate per pixel, frame rate (variabile/insolito), interlacciamento (dichiarato e rilevato), HDR, colore non dichiarato, bande nere incorporate, neri iniziali/finali/centrali, fermi immagine, errori di decodifica, buchi nel flusso, keyframe.
- **Immagine**: OCR (Vision) sui primi 45 s e sugli ultimi 150 s per trovare scritte/crediti del torrent.
- **Audio** (per le prime 3 tracce): volume integrato, LRA, picchi, salti bruschi di volume, parti sommesse/forti rispetto al livello tipico, silenzi, buchi nei pacchetti, sincronia audio/video, lingua mancante, predefinite ambigue.
- **Sottotitoli**: lingua reale delle battute contro quella dichiarata (NaturalLanguage), crediti/pubblicità, battute sovrapposte o troppo veloci, caratteri rovinati, durata rispetto al film, predefiniti/forzati incoerenti, formato a immagine.

## Correzioni
Dalle segnalazioni (pulsante «Correggi…») o dal pulsante in alto si apre una finestra che mostra tutto quello che verrà fatto, da confermare:
- traccia **audio predefinita**, **sottotitoli predefiniti** (o nessuno), **lingua** delle tracce senza etichetta;
- **togliere pubblicità e crediti** dai sottotitoli, **eliminare** tracce audio/sottotitoli;
- **tagliare** l'inizio o la fine (crediti del torrent nell'immagine) senza ricodificare, sui fotogrammi chiave;
- **livellare la dinamica** di una traccia audio (`dynaudnorm` + `alimiter`, AC3), con misura prima/dopo.

Sicurezza: solo etichette in un mkv → modifica sul posto con mkvpropedit, senza riscrivere il film. Ogni altra correzione scrive un file temporaneo, lo **verifica** (numero di tracce, durata, buchi nell'audio rispetto all'originale) e solo allora sostituisce; l'originale resta come `<nome>.orig_backup.<ext>` e «Annulla la correzione» lo rimette. Da riga di comando: `dist/collaudo --fix film.mkv --audio-default 1 --sub-default none --lang s1=fra --clean-sub 0 --trim-start 4 --normalize 0` (numeri da 0).

## Uso
    ./build.sh                       # dist/Collaudo.app (+ dist/collaudo per la riga di comando)
    dist/collaudo --analyze film.mkv # rapporto testuale
    python3 tests/test_collaudo.py   # 35 controlli su film sintetici con difetti noti

Serve ffmpeg/ffprobe (Homebrew in /opt/homebrew/bin, oppure dentro Contents/Resources). Non modifica mai i file analizzati.

## Soglie
Tarate su 9 film reali della libreria "Opere Prime" (nessun falso positivo su OCR/pubblicità/interlacciamento). Le soglie di dinamica audio (LRA, salti, sommesso/forte) sono volutamente larghe: i film reali normali hanno LRA 18-23 LU.
