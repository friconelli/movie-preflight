#!/usr/bin/env python3
"""Prova Collaudo su film sintetici con difetti noti: ogni controllo deve scattare quando deve e non quando non deve.
Uso: python3 tests/test_collaudo.py   (usa dist/collaudo; serve ffmpeg)"""
import os, subprocess, sys, tempfile, shutil
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); BIN = os.path.join(ROOT, "dist", "collaudo")
T = tempfile.mkdtemp(prefix="collaudo-test-"); ok = bad = 0
def ff(*a): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *a], check=True)
def check(c, msg):
    global ok, bad
    if c: ok += 1; print("  ok  ", msg)
    else: bad += 1; print("  FAIL", msg)
def analyze(f): return subprocess.run([BIN, "--analyze", f], capture_output=True, text=True).stdout
def srt(path, cues):
    def t(s): return f"{int(s//3600):02d}:{int(s%3600//60):02d}:{int(s%60):02d},{int(s%1*1000):03d}"
    open(path, "w").write("\n".join(f"{i+1}\n{t(s)} --> {t(s+2.5)}\n{x}\n" for i, (s, x) in enumerate(cues)))
D = 140
IT = ["Questa è una frase abbastanza lunga in italiano numero %d" % i for i in range(40)]
EN = ["This is a fairly long sentence written in English number %d" % i for i in range(40)]
def video(name, vf="", extra=(), aud=True, af="sine=f=300:d=%d" % D, subs=None, size="640x360", fps=25, meta=()):
    out = os.path.join(T, name); a = ["-f", "lavfi", "-i", f"testsrc2=s={size}:r={fps}:d={D}"]
    if aud: a += ["-f", "lavfi", "-i", af]
    si = 2 if aud else 1
    for s in (subs or []): a += ["-i", s[0]]
    a += ["-map", "0:v"] + (["-map", "1:a"] if aud else [])
    for i, s in enumerate(subs or []): a += ["-map", str(si + i), f"-metadata:s:s:{i}", f"language={s[1]}"] + ([f"-disposition:s:{i}", s[2]] if len(s) > 2 else [])
    if vf: a += ["-vf", vf]
    a += ["-c:v", "libx264", "-preset", "ultrafast", "-b:v", "1500k", "-pix_fmt", "yuv420p"] + (["-c:a", "aac", "-metadata:s:a:0", "language=ita"] if aud else []) + (["-c:s", "srt"] if subs else []) + list(extra)
    for m in meta: a += ["-metadata", m]
    ff(*a, out); return out
try:
    print("== film pulito"); 
    srt(os.path.join(T, "it.srt"), [(i * 3 + 1, x) for i, x in enumerate(IT)])
    f = video("pulito.mkv", subs=[(os.path.join(T, "it.srt"), "ita")], af="sine=f=300:d=%d,volume=0.2" % D); o = analyze(f)
    check("Nessun problema rilevato" in o or "[PROBLEMA]" not in o, "film pulito: nessun problema")
    check("Risoluzione: 640×360" in o and "Codec: H264" in o, "dati tecnici presenti")
    check("[ATTENZIONE] Sottotitoli" not in o and "[PROBLEMA] Sottotitoli" not in o, "film pulito: sottotitoli italiani non segnalati")

    print("== crediti nell'immagine")
    subprocess.run(["swiftc", "-o", os.path.join(T, "card"), os.path.join(ROOT, "tests", "card.swift")], check=True, capture_output=True)
    subprocess.run([os.path.join(T, "card"), os.path.join(T, "card.png"), "www.YTS.mx"], check=True)
    out = os.path.join(T, "ad.mkv")
    ff("-f", "lavfi", "-i", f"testsrc2=s=640x360:r=25:d={D}", "-i", os.path.join(T, "card.png"), "-f", "lavfi", "-i", "sine=f=300:d=%d" % D, "-filter_complex", "[1]scale=640:360[c];[0][c]overlay=enable='between(t,2,7)'[v]", "-map", "[v]", "-map", "2:a", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", out)
    o = analyze(out); check("[PROBLEMA] Video: Scritta pubblicitaria" in o and "yts" in o.lower(), "scritta www.YTS.mx nei primi secondi rilevata dall'OCR")

    print("== sottotitoli")
    cues = [(i * 3 + 1, x) for i, x in enumerate(IT[:25])] + [(i * 3 + 80, x) for i, x in enumerate(EN[:12])] + [(5, "Subtitles by www.opensubtitles.org")]
    srt(os.path.join(T, "mix.srt"), sorted(cues)); srt(os.path.join(T, "en.srt"), [(i * 3 + 1, x) for i, x in enumerate(EN)])
    o = analyze(video("sub.mkv", subs=[(os.path.join(T, "mix.srt"), "ita", "default")]))
    check("Crediti o pubblicità nei sottotitoli" in o, "pubblicità nei sottotitoli")
    check("Parte dei sottotitoli non è in italiano" in o, "battute in inglese in una traccia dichiarata italiana")
    check("Sottotitoli attivi di default" in o, "sottotitoli predefiniti segnalati")
    o = analyze(video("sub2.mkv", subs=[(os.path.join(T, "en.srt"), "ita")])); check("Lingua dei sottotitoli diversa da quella dichiarata" in o, "traccia inglese etichettata italiano")
    o = analyze(video("sub3.mkv", subs=[(os.path.join(T, "it.srt"), "und")])); check("Lingua non indicata — sottotitoli 1" in o, "sottotitoli senza lingua")

    print("== audio")
    af = "sine=f=300:d=%d,volume='if(between(t,60,90),1,0.02)':eval=frame" % D
    o = analyze(video("loud.mkv", af=af)); check("salti bruschi di volume" in o or "più forti del parlato" in o or "Dinamica molto ampia" in o, "musica forte dopo parlato sommesso")
    o = analyze(video("silent.mkv", af="anullsrc=r=48000:d=%d" % D)); check("Audio quasi muto" in o, "traccia muta")
    o = analyze(video("noaudio.mkv", aud=False)); check("Nessuna traccia audio" in o, "niente audio")
    o = analyze(video("clip.mkv", af="sine=f=300:d=%d,volume=40,alimiter=limit=1:level=0" % D)); check("Picchi a 0 dB" in o or "Audio molto alto" in o, "audio saturo")

    print("== video e file")
    o = analyze(video("low.mkv", size="320x180")); check("Risoluzione bassa" in o, "risoluzione bassa")
    o = analyze(video("hdr.mkv", extra=["-x264-params", "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc"])); check("HDR (PQ)" in o, "HDR segnalato")
    o = analyze(video("lbx.mkv", vf="crop=640:272,pad=640:360:0:44")); check("Bande nere incorporate" in o, "bande nere incorporate")
    o = analyze(video("title.mkv", meta=["title=www.torrent-site.com - Film"])); check("titolo nei metadati contiene pubblicità" in o, "titolo con pubblicità")
    o = analyze(video("blk.mkv", vf="fade=in:st=0:d=0.1,drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill:enable='between(t,0,15)'")); check("Nero iniziale lungo" in o, "nero iniziale")
    o = analyze(video("il.mkv", vf="interlace=scan=tff", extra=["-flags", "+ilme+ildct"])); check("interlacciat" in o.lower(), "video interlacciato")
    avi = os.path.join(T, "film.avi"); ff("-f", "lavfi", "-i", f"testsrc2=s=640x360:r=25:d={D}", "-f", "lavfi", "-i", "sine=d=%d" % D, "-c:v", "mpeg4", "-c:a", "mp3", avi)
    o = analyze(avi); check("Codec: MPEG4" in o and "Contenitore: AVI" in o, "file avi analizzato")
    full = video("trunc_src.mkv"); tr = os.path.join(T, "trunc.mkv"); data = open(full, "rb").read(); open(tr, "wb").write(data[: len(data) // 2])
    o = analyze(tr); check("[PROBLEMA]" in o or "troncato" in o or "non leggibile" in o or "prima del previsto" in o, "file troncato")
    open(os.path.join(T, "junk.mkv"), "w").write("non è un video"); o = analyze(os.path.join(T, "junk.mkv")); check("File non leggibile" in o, "file non video")
finally:
    shutil.rmtree(T, ignore_errors=True)
print(f"\n{ok} controlli ok, {bad} falliti"); sys.exit(1 if bad else 0)
