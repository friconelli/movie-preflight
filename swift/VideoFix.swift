import Foundation

/// Deinterlacciamento: bwdif (filtro di qualità broadcast di ffmpeg), solo sui fotogrammi marcati o rilevati come interlacciati, senza cambiare il frame rate.
let deinterlaceFilter = "bwdif=mode=send_frame:parity=auto:deint=interlaced"

/// Opzioni di codifica ad alta qualità che conservano la famiglia del codec e la profondità colore dell'originale.
func videoEncodeArgs(_ v: [String: Any], outIndex: Int) -> [String] {
    let codec = (v["codec_name"] as? String) ?? "h264"; let pix = (v["pix_fmt"] as? String) ?? "yuv420p"
    if codec == "hevc" { return ["-c:v:\(outIndex)", "libx265", "-crf", "16", "-preset", "fast", "-x265-params", "log-level=error", "-pix_fmt", pix, "-tag:v:\(outIndex)", "hvc1"] }
    return ["-c:v:\(outIndex)", "libx264", "-crf", "14", "-preset", "slow", "-pix_fmt", pix]
}

/// Percentuale di fotogrammi interlacciati in una finestra del file (idet).
func interlacedPct(_ path: String, _ start: Double, _ len: Double) -> Double? {
    guard let ff = tool("ffmpeg") else { return nil }; var i = 0, p = 0
    run(ff, ["-nostdin", "-nostats", "-hide_banner", "-ss", String(start), "-t", String(len), "-i", path, "-map", "0:v:0", "-an", "-sn", "-vf", "idet", "-f", "null", "-"]) { l in
        if let m = l.match(#"Multi frame detection: TFF:\s*(\d+) BFF:\s*(\d+) Progressive:\s*(\d+)"#) { i += (Int(m[1]) ?? 0) + (Int(m[2]) ?? 0); p += Int(m[3]) ?? 0 }
    }
    return i + p > 50 ? Double(i) / Double(i + p) * 100 : nil
}
/// VMAF (la metrica di qualità video di Netflix) del file nuovo contro l'originale, passato nello stesso filtro, su una finestra.
func vmaf(new: String, source: String, start: Double, len: Double) -> Double? {
    guard let ff = tool("ffmpeg") else { return nil }; var score: Double?
    let g = "[0:v]format=yuv420p[d];[1:v]\(deinterlaceFilter),format=yuv420p[r];[d][r]libvmaf=n_threads=4"
    run(ff, ["-nostdin", "-nostats", "-hide_banner", "-ss", String(start), "-t", String(len), "-i", new, "-ss", String(start), "-t", String(len), "-i", source, "-lavfi", g, "-f", "null", "-"]) { l in
        if let m = l.match(#"VMAF score:\s*([\d.]+)"#) { score = Double(m[1]) }
    }
    return score
}
/// Controllo di qualità dopo il deinterlacciamento: l'interlacciamento deve essere sparito e la codifica non deve aver degradato l'immagine.
/// Restituisce nil se tutto torna, altrimenti il motivo del rifiuto.
func deinterlaceQC(source: String, new: String, duration: Double, lines: inout [String], progress: (Double) -> Void) -> String? {
    guard duration > 90 else { return nil }
    let wins = [0.12, 0.5, 0.85].map { max(0, min($0 * duration, duration - 25)) }
    var scores: [Double] = []
    for (n, s) in wins.enumerated() {
        progress(Double(n) / 3)
        guard let before = interlacedPct(source, s, 20), let after = interlacedPct(new, s, 20) else { continue }
        if after > max(5, before * 0.25) { return String(format: "l'interlacciamento non è sparito a %@ (prima %.0f%%, dopo %.0f%% dei fotogrammi)", hms(s), before, after) }
        guard let v = vmaf(new: new, source: source, start: s, len: 20) else { return "non riesco a misurare la qualità dell'immagine (VMAF)" }
        scores.append(v)
    }
    guard !scores.isEmpty else { return "non riesco a misurare la qualità dell'immagine dopo il deinterlacciamento" }
    let mean = scores.reduce(0, +) / Double(scores.count)
    lines.append(String(format: "Qualità dell'immagine (VMAF su %d tratti, 100 = identica al deinterlacciato ideale): media %.1f, minimo %.1f", scores.count, mean, scores.min()!))
    if mean < 93 || scores.min()! < 88 { return String(format: "la codifica avrebbe degradato l'immagine (VMAF %.1f, minimo accettato 93)", mean) }
    return nil
}

/// HDR (PQ o HLG) → SDR BT.709 con zimg (zscale) e tone mapping Hable: la catena usata in post-produzione e nei server multimediali.
func tonemapFilter(_ v: [String: Any]) -> String {
    let tin = (v["color_transfer"] as? String) == "arib-std-b67" ? "arib-std-b67" : "smpte2084"
    let min = (v["color_space"] as? String).flatMap { $0 == "unknown" ? nil : $0 } ?? "bt2020nc", pin = (v["color_primaries"] as? String).flatMap { $0 == "unknown" ? nil : $0 } ?? "bt2020"
    return "zscale=tin=\(tin):min=\(min):pin=\(pin):rin=tv:t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
}
/// Dopo la conversione: tag SDR corretti e immagine né nera né bruciata (luminanza media e pixel illegali).
func tonemapQC(new: String, duration: Double, lines: inout [String]) -> String? {
    guard let fp = tool("ffprobe"), let ff = tool("ffmpeg") else { return "strumenti mancanti" }
    let o = run(fp, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=color_transfer,color_primaries,pix_fmt", "-of", "csv=p=0", new]).text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !o.contains("bt709") || o.contains("smpte2084") { return "il file risultante non è marcato come SDR BT.709 (\(o))" }
    var yavg: [Double] = [], brng: [Double] = []
    for s in [0.2, 0.5, 0.8] {
        let t = max(0, min(s * duration, duration - 15))
        let r = run(ff, ["-nostdin", "-nostats", "-v", "error", "-ss", String(t), "-t", "10", "-i", new, "-map", "0:v:0", "-an", "-vf", "signalstats=stat=brng,metadata=mode=print:file=-", "-f", "null", "-"])
        for l in r.text.split(separator: "\n") { if l.hasPrefix("lavfi.signalstats.YAVG=") { yavg.append(Double(l.dropFirst(23)) ?? 0) } else if l.hasPrefix("lavfi.signalstats.BRNG=") { brng.append(Double(l.dropFirst(23)) ?? 0) } }
    }
    guard yavg.count > 30 else { return "non riesco a misurare l'immagine convertita" }
    let y = yavg.reduce(0, +) / Double(yavg.count), b = brng.reduce(0, +) / Double(max(1, brng.count))
    lines.append(String(format: "Immagine SDR: luminanza media %.0f/255, pixel fuori standard %.2f%%", y, b * 100))
    if y < 15 || y > 190 { return String(format: "la luminanza media dell'immagine convertita (%.0f/255) è fuori misura", y) }
    if b > 0.5 { return String(format: "oltre la metà dei pixel è fuori standard dopo la conversione (%.0f%%)", b * 100) }
    return nil
}
