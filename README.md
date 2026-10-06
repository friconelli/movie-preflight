# Collaudo (nome provvisorio)

App Mac (Swift/SwiftUI, come Dolly) che controlla un film prima della proiezione: si trascina un mp4/mkv/avi (o più file, o una cartella) e restituisce dati tecnici e segnalazioni su immagine, audio e sottotitoli.

## Cosa controlla
- **Contenitore**: estensione/contenuto, durata, titolo nei metadati con pubblicità, capitoli, file troncato.
- **Video**: risoluzione, bitrate per pixel, frame rate (variabile/insolito), interlacciamento (dichiarato e rilevato), HDR, colore non dichiarato, bande nere incorporate, neri iniziali/finali/centrali, fermi immagine, errori di decodifica, buchi nel flusso, keyframe.
- **Immagine**: OCR (Vision) sui primi 45 s e sugli ultimi 150 s per trovare scritte/crediti del torrent.
- **Audio** (per le prime 3 tracce): volume integrato, LRA, picchi, salti bruschi di volume, parti sommesse/forti rispetto al livello tipico, silenzi, buchi nei pacchetti, sincronia audio/video, lingua mancante, predefinite ambigue.
- **Sottotitoli**: lingua reale delle battute contro quella dichiarata (NaturalLanguage), crediti/pubblicità, battute sovrapposte o troppo veloci, caratteri rovinati, durata rispetto al film, predefiniti/forzati incoerenti, formato a immagine.

## Uso
    ./build.sh                       # dist/Collaudo.app (+ dist/collaudo per la riga di comando)
    dist/collaudo --analyze film.mkv # rapporto testuale
    python3 tests/test_collaudo.py   # 22 controlli su film sintetici con difetti noti

Serve ffmpeg/ffprobe (Homebrew in /opt/homebrew/bin, oppure dentro Contents/Resources). Non modifica mai i file analizzati.

## Soglie
Tarate su 9 film reali della libreria "Opere Prime" (nessun falso positivo su OCR/pubblicità/interlacciamento). Le soglie di dinamica audio (LRA, salti, sommesso/forte) sono volutamente larghe: i film reali normali hanno LRA 18-23 LU.
