#!/usr/bin/env python3
"""Prova Movie Preflight su film sintetici con difetti noti: ogni controllo deve scattare quando deve e non quando non deve.
Uso: python3 tests/test_moviepreflight.py   (usa dist/moviepreflight; serve ffmpeg)"""
import os, re, subprocess, sys, tempfile, shutil
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); BIN = os.path.join(ROOT, "dist", "moviepreflight")
T = tempfile.mkdtemp(prefix="moviepreflight-test-"); ok = bad = 0
def ff(*a): subprocess.run(["ffmpeg", "-y", "-nostdin", "-loglevel", "error", *a], check=True, stdin=subprocess.DEVNULL)
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
    print("== correzioni")
    def fix(f, *a): r = subprocess.run([BIN, "--fix", f, *a], capture_output=True, text=True); return r.returncode, r.stdout
    def probe(f):
        import json; return json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", f], capture_output=True, text=True).stdout)
    def tracks(f, t): return [s for s in probe(f)["streams"] if s["codec_type"] == t]
    adsrt = os.path.join(T, "ads.srt"); srt(adsrt, [(1, "Subtitles by www.opensubtitles.org")] + [(i * 3 + 10, x) for i, x in enumerate(IT[:20])])
    def two(name):
        out = os.path.join(T, name)
        ff("-f", "lavfi", "-i", f"testsrc2=s=640x360:r=25:d={D}", "-f", "lavfi", "-i", "sine=f=300:d=%d" % D, "-f", "lavfi", "-i", "sine=f=500:d=%d" % D, "-i", adsrt, "-i", os.path.join(T, "en.srt"),
           "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3", "-map", "4", "-c:v", "libx264", "-preset", "ultrafast", "-g", "25", "-c:a", "aac", "-c:s", "srt",
           "-metadata:s:a:0", "language=ita", "-metadata:s:a:1", "language=eng", "-metadata:s:s:0", "language=ita", "-metadata:s:s:1", "language=eng", "-disposition:a:0", "default", "-disposition:s:0", "default", out)
        return out
    f = two("fix1.mkv"); before = os.path.getsize(f)
    rc, o = fix(f, "--audio-default", "1", "--sub-default", "none", "--lang", "s1=fra")
    a, ss = tracks(f, "audio"), tracks(f, "subtitle")
    check(rc == 0 and a[1]["disposition"]["default"] == 1 and a[0]["disposition"]["default"] == 0, "audio predefinito cambiato (etichette sul posto)")
    check(all(x["disposition"]["default"] == 0 for x in ss) and ss[1]["tags"]["language"] == "fre", "nessun sottotitolo predefinito e lingua impostata")
    check(not os.path.exists(f.replace(".mkv", ".orig_backup.mkv")), "solo etichette: nessuna copia di backup")
    f = two("fix2.mkv"); full = float(probe(f)["format"]["duration"])
    rc, o = fix(f, "--clean-sub", "0", "--trim-start", "4", "--trim-end", "120", "--normalize", "0")
    bk = f.replace(".mkv", ".orig_backup.mkv"); np = probe(f)
    check(rc == 0 and os.path.exists(bk), "correzione di contenuto: l'originale resta come .orig_backup")
    check(float(np["format"]["duration"]) < full - 14 and float(np["format"]["duration"]) > 100, f"taglio ai fotogrammi chiave (durata {float(np['format']['duration']):.0f} s su {full:.0f})")
    check([x["codec_name"] for x in tracks(f, "audio")][0] == "ac3" and tracks(f, "audio")[1]["codec_name"] == "aac", "solo la traccia scelta è ricodificata")
    cues = subprocess.run(["ffmpeg", "-v", "error", "-i", f, "-map", "0:s:0", "-f", "srt", "-"], capture_output=True, text=True).stdout
    check("opensubtitles" not in cues and "Questa è una frase" in cues, "pubblicità tolta dai sottotitoli, il resto resta")
    check("prima:" in o and "dopo:" in o, "misura prima/dopo del volume riportata")
    check(os.path.getsize(bk) > 0 and float(probe(bk)["format"]["duration"]) > full - 1, "l'originale di backup è intatto")
    f = two("fix3.mkv"); rc, o = fix(f, "--drop-sub", "1", "--drop-audio", "1")
    check(rc == 0 and len(tracks(f, "audio")) == 1 and len(tracks(f, "subtitle")) == 1, "tracce eliminate")
    f = two("fix4.mkv"); rc, o = fix(f, "--drop-audio", "0", "--drop-audio", "1"); check(rc != 0 and len(tracks(f, "audio")) == 2, "non si eliminano tutte le tracce audio")
    rc, o = fix(f, "--audio-default", "5"); check(rc != 0, "traccia predefinita inesistente rifiutata")
    rc, o = fix(f, "--trim-start", "100000"); check(rc != 0 and not os.path.exists(f.replace(".mkv", ".orig_backup.mkv")), "taglio impossibile: nessuna modifica")
    print("== Dolby")
    ac = video("aac.mkv", af="sine=f=300:d=%d,volume=0.2" % D); o = analyze(ac)
    check("Audio non Dolby (AAC)" in o and "Dolby: no (AAC)" in o, "traccia AAC segnalata come non Dolby")
    rc, o = fix(ac, "--dolby", "0"); m = re.search(r"prima:\s+(-?[\d.]+) LUFS.*\n.*dopo:\s+(-?[\d.]+) LUFS", o)
    check(rc == 0 and tracks(ac, "audio")[0]["codec_name"] == "ac3" and m is not None and abs(float(m.group(1)) - float(m.group(2))) < 1.0, f"conversione in AC-3 senza cambiare il volume ({m.group(1) if m else '?'} → {m.group(2) if m else '?'} LUFS)")
    o = analyze(ac); check("non Dolby" not in o and "Dolby: sì — Dolby Digital (AC-3)" in o, "dopo la conversione la traccia risulta Dolby")
    print("== deinterlacciamento")
    il = os.path.join(T, "interl.mkv")
    ff("-f", "lavfi", "-i", "mandelbrot=s=640x360:r=25", "-f", "lavfi", "-i", "sine=d=200", "-t", "200", "-map", "0:v", "-map", "1:a", "-vf", "interlace=scan=tff", "-c:v", "libx264", "-preset", "ultrafast", "-flags", "+ilme+ildct", "-b:v", "6M", "-c:a", "aac", il)
    rc, o = fix(il, "--deinterlace"); np = probe(il) if rc == 0 else {}
    check(rc == 0 and "VMAF" in o and os.path.exists(il.replace(".mkv", ".orig_backup.mkv")), "deinterlacciamento riuscito con controllo VMAF e backup")
    check(rc == 0 and tracks(il, "video")[0]["codec_name"] == "h264" and tracks(il, "audio")[0]["codec_name"] == "aac", "audio copiato, video ricodificato nello stesso codec")
    print("== dialoghi 5.1")
    f51 = os.path.join(T, "surround.mkv")
    ff("-f", "lavfi", "-i", f"testsrc2=s=640x360:r=25:d={D}", "-f", "lavfi", "-i", f"sine=f=300:d={D}", "-filter_complex", "[1]pan=5.1|FL=2.0*c0|FR=2.0*c0|FC=0.8*c0|LFE=0*c0|BL=0*c0|BR=0*c0[a]",
       "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "ac3", "-metadata:s:a:0", "language=ita", f51)   # fronte più forte del centro di ~8 dB (niente join: ffmpeg a volte si blocca)
    o = analyze(f51); check("Musica ed effetti coprono i dialoghi" in o, "musica sopra i dialoghi in un 5.1 rilevata")
    rc, o = fix(f51, "--boost-center", "0"); import re
    m = re.search(r"prima: (\d+)% .* dopo: (\d+)%", o)
    check(rc == 0 and m is not None and int(m.group(1)) > 80 and int(m.group(2)) < int(m.group(1)) - 50, f"canale centrale alzato: musica sopra i dialoghi {m.group(1) if m else '?'}% → {m.group(2) if m else '?'}%")
    rc, o = fix(os.path.join(T, "pulito.mkv"), "--boost-center", "0"); check(rc != 0, "alzare il centro su una traccia non 5.1 è rifiutato")
    print("== controllo di non-peggioramento")
    fb = os.path.join(T, "surround_ok.mkv")   # centro e fronte vicini (~4 dB): abbassare il centro lo farebbe coprire dalla musica
    ff("-f", "lavfi", "-i", f"testsrc2=s=640x360:r=25:d={D}", "-f", "lavfi", "-i", f"sine=f=300:d={D}", "-filter_complex", "[1]pan=5.1|FL=2.0*c0|FR=2.0*c0|FC=1.3*c0|LFE=0*c0|BL=0*c0|BR=0*c0[a]",
       "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "ac3", fb)
    before_size = os.path.getsize(fb); rc, o = fix(fb, "--boost-center", "0", "--boost-db", "-6")
    check(rc != 0 and "annullata" in o and os.path.getsize(fb) == before_size and not os.path.exists(fb.replace(".mkv", ".orig_backup.mkv")), "correzione che peggiora i dialoghi: annullata, file intatto, nessun backup")
    pl = os.path.join(T, "pulito.mkv"); rc, o = fix(pl, "--level", "0"); m = re.search(r"dopo:\s+(-?[\d.]+) LUFS", o)
    check(rc == 0 and m is not None and abs(float(m.group(1)) + 24) < 2.5 and "guadagno fisso" in o, f"volume portato a -24 LUFS con guadagno fisso ({m.group(1) if m else '?'} LUFS)")
finally:
    shutil.rmtree(T, ignore_errors=True)
print(f"\n{ok} controlli ok, {bad} falliti"); sys.exit(1 if bad else 0)
