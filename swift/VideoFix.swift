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
