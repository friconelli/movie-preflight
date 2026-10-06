import Foundation

/// Che cosa fare ai sottotitoli predefiniti.
enum SubDefault: Equatable { case keep, none, track(Int) }

/// Un insieme di correzioni da applicare in un colpo solo. Le posizioni sono ordinali dentro il proprio tipo (audio 0, 1…; sottotitoli 0, 1…).
struct FixPlan {
    var audioDefault: Int?; var subDefault: SubDefault = .keep
    var lang: [String: String] = [:]                 // "a0" / "s1" → codice lingua a 3 lettere
    var cleanSubs: Set<Int> = [], dropSubs: Set<Int> = [], dropAudio: Set<Int> = [], normalize: Set<Int> = [], boostCenter: Set<Int> = []
    var trimStart: Double?, trimEnd: Double?          // taglia i primi N secondi / dal secondo N alla fine
    var changesContent: Bool { !cleanSubs.isEmpty || !dropSubs.isEmpty || !dropAudio.isEmpty || !normalize.isEmpty || !boostCenter.isEmpty || trimStart != nil || trimEnd != nil }
    var isEmpty: Bool { !changesContent && audioDefault == nil && subDefault == .keep && lang.isEmpty }
    mutating func merge(_ h: FixHint) {
        switch h {
        case .defaultAudio(let i): audioDefault = i
        case .defaultSub(let i): subDefault = i.map { .track($0) } ?? .none
        case .setLang(let k, let i): lang["\(k)\(i)"] = lang["\(k)\(i)"] ?? "ita"
        case .cleanSub(let i): cleanSubs.insert(i)
        case .dropSub(let i): dropSubs.insert(i)
        case .trimStart(let t): trimStart = t
        case .trimEnd(let t): trimEnd = t
        case .normalize(let i): normalize.insert(i)
        case .boostCenter(let i): boostCenter.insert(i)
        }
    }
}
struct FixResult { var ok: Bool; var message: String; var lines: [String] = []; var backup: URL? }

/// Filtro validato per "musica troppo forte, dialoghi troppo bassi" (vedi la libreria film): livella la dinamica e limita i picchi.
let dynamicsChain = "dynaudnorm=f=500:g=15:p=0.7:m=10,alimiter=limit=0.8:level=false"

/// Misura volume di una traccia audio: (integrato LUFS, LRA LU, picco dBFS).
func measureLoudness(_ path: String, _ ord: Int, progress: ((Double) -> Void)? = nil, duration: Double = 0) -> (Double, Double, Double)? {
    guard let ff = tool("ffmpeg") else { return nil }
    var i: Double?, l: Double?, p: Double?
    run(ff, ["-nostats", "-hide_banner", "-i", path, "-map", "0:a:\(ord)", "-vn", "-sn", "-af", "ebur128=peak=true", "-f", "null", "-"]) { line in
        if let m = line.match(#"^\s+I:\s+(-?[\d.]+) LUFS"#), i == nil { i = Double(m[1]) }
        else if let m = line.match(#"^\s+LRA:\s+([\d.]+) LU"#), l == nil { l = Double(m[1]) }
        else if let m = line.match(#"^\s+Peak:\s+(-?[\d.]+) dBFS"#), p == nil { p = Double(m[1]) }
    }
    guard let a = i, let b = l, let c = p else { return nil }; return (a, b, c)
}
private func lufs(_ m: (Double, Double, Double)) -> String { String(format: "%.1f LUFS · LRA %.1f LU · picco %+.1f dBFS", m.0, m.1, m.2) }
private func secs(_ s: Double) -> String { String(format: "%.3f", s) }

func backupURL(for url: URL) -> URL {
    let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
    var n = 1; var u = dir.appendingPathComponent("\(base).orig_backup.\(ext)")
    while FileManager.default.fileExists(atPath: u.path) { n += 1; u = dir.appendingPathComponent("\(base).orig_backup\(n).\(ext)") }
    return u
}

func applyFix(_ url: URL, _ plan: FixPlan, progress: @escaping (Double, String) -> Void) -> FixResult {
    guard let ff = tool("ffmpeg"), let fp = tool("ffprobe"), let pr = Probe(url.path) else { return FixResult(ok: false, message: "ffmpeg non trovato o file illeggibile.") }
    let ext = url.pathExtension.lowercased(), path = url.path
    let audio = pr.audio, subs = pr.subs; var lines: [String] = []
    // controlli di coerenza prima di toccare qualunque cosa
    if audio.count > 0 && plan.dropAudio.count >= audio.count { return FixResult(ok: false, message: "Non si possono eliminare tutte le tracce audio.") }
    if let d = plan.audioDefault, !audio.indices.contains(d) || plan.dropAudio.contains(d) { return FixResult(ok: false, message: "La traccia audio predefinita scelta non esiste o viene eliminata.") }
    if case .track(let k) = plan.subDefault, !subs.indices.contains(k) || plan.dropSubs.contains(k) { return FixResult(ok: false, message: "La traccia di sottotitoli predefinita scelta non esiste o viene eliminata.") }
    for k in plan.boostCenter { guard audio.indices.contains(k), (audio[k]["channels"] as? Int ?? 2) == 6 else { return FixResult(ok: false, message: "Il canale centrale si può alzare solo nelle tracce 5.1 (traccia \(k + 1)).") } }
    for k in plan.normalize { guard audio.indices.contains(k), (audio[k]["channels"] as? Int ?? 2) <= 6 else { return FixResult(ok: false, message: "La traccia audio \(k + 1) non può essere livellata (più di 6 canali).") } }
    if ext == "avi" && (!plan.cleanSubs.isEmpty || plan.subDefault != .keep) { return FixResult(ok: false, message: "Il formato AVI non può contenere sottotitoli.") }

    // 1) solo etichette in un mkv: si modifica l'intestazione sul posto, senza riscrivere il film
    if !plan.changesContent, ext == "mkv", let mp = tool("mkvpropedit") {
        progress(0.1, "Modifica delle etichette…")
        var a = [path]
        for (i, _) in audio.enumerated() {
            var sets: [String] = []
            if let d = plan.audioDefault { sets += ["flag-default=\(i == d ? 1 : 0)"] }
            if let l = plan.lang["a\(i)"] { sets += ["language=\(l)"] }
            for s in sets { a += ["--edit", "track:a\(i + 1)", "--set", s] }
        }
        for (i, _) in subs.enumerated() {
            var sets: [String] = []
            switch plan.subDefault { case .none: sets += ["flag-default=0"]; case .track(let k): sets += ["flag-default=\(i == k ? 1 : 0)"]; case .keep: break }
            if let l = plan.lang["s\(i)"] { sets += ["language=\(l)"] }
            for s in sets { a += ["--edit", "track:s\(i + 1)", "--set", s] }
        }
        let o = run(mp, a); if o.status > 1 { return FixResult(ok: false, message: "mkvpropedit non è riuscito: \(o.text.suffix(200))") }
        // verifica rileggendo il file
        guard let np = Probe(path) else { return FixResult(ok: false, message: "Dopo la modifica il file non è più leggibile: ripristinalo da una copia.") }
        if let d = plan.audioDefault { lines.append("Traccia audio predefinita: \(d + 1)"); if disp(np.audio[d], "default") != 1 { return FixResult(ok: false, message: "La modifica non risulta applicata.") } }
        switch plan.subDefault { case .none: lines.append("Nessun sottotitolo predefinito"); case .track(let k): lines.append("Sottotitoli predefiniti: traccia \(k + 1)"); case .keep: break }
        for (k, v) in plan.lang.sorted(by: { $0.key < $1.key }) { lines.append("Lingua \(k.hasPrefix("a") ? "audio" : "sottotitoli") \(Int(k.dropFirst())! + 1): \(langLabel(v))") }
        progress(1, "Fatto"); return FixResult(ok: true, message: "Etichette aggiornate sul posto (nessuna riscrittura del film).", lines: lines)
    }

    // 2) riscrittura con ffmpeg su un file temporaneo accanto all'originale
    let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
    if let free = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage, Double(free) < pr.size * 1.05 + 1e8 {
        return FixResult(ok: false, message: "Spazio insufficiente: servono almeno \(fmtBytes(pr.size * 1.05)) liberi.")
    }
    let tmp = dir.appendingPathComponent(".\(base).moviepreflight-tmp.\(ext)"); try? FileManager.default.removeItem(at: tmp)
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("moviepreflight-fix-" + UUID().uuidString); try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work); try? FileManager.default.removeItem(at: tmp) }

    // taglio: sempre sui keyframe, così nessun fotogramma resta a metà e non serve ricodificare
    var s0 = 0.0, e0 = pr.duration
    if plan.trimStart != nil || plan.trimEnd != nil {
        progress(0.02, "Ricerca dei punti di taglio…")
        let keys = packetTimes(fp, path, "v:0").keys
        if let t = plan.trimStart { guard let k = keys.first(where: { $0 >= t }) else { return FixResult(ok: false, message: "Nessun punto di taglio utile dopo \(hms(t)).") }; s0 = k; lines.append(String(format: "Tolti i primi %.1f s (taglio al fotogramma chiave a %.2f s)", s0, s0)) }
        if let t = plan.trimEnd { guard let k = keys.last(where: { $0 <= t }), k > s0 + 60 else { return FixResult(ok: false, message: "Nessun punto di taglio utile prima di \(hms(t)).") }; e0 = k; lines.append(String(format: "Tolto tutto dopo %.2f s (ultimo %.0f s)", e0, pr.duration - e0)) }
    }
    // sottotitoli ripuliti: si riscrive la traccia senza le battute con pubblicità/crediti
    var extra: [Int: Int] = [:]; var inputs: [String] = []
    for k in plan.cleanSubs.sorted() where subs.indices.contains(k) && !plan.dropSubs.contains(k) {
        let raw = work.appendingPathComponent("raw\(k).srt"); run(ff, ["-nostdin", "-y", "-v", "error", "-i", path, "-map", "0:s:\(k)", "-f", "srt", raw.path])
        guard let txt = try? String(contentsOf: raw, encoding: .utf8) else { return FixResult(ok: false, message: "Non riesco a leggere i sottotitoli \(k + 1).") }
        let all = parseSRT(txt); let keep = all.filter { !$0.t.has(adPattern) && $0.e > s0 && $0.s < e0 }
        func ts(_ x: Double) -> String { let v = max(0, x - s0); let ms = Int((v * 1000).rounded()); return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000) }
        let out = keep.enumerated().map { "\($0 + 1)\n\(ts($1.s)) --> \(ts($1.e))\n\($1.t)\n" }.joined(separator: "\n")
        let f = work.appendingPathComponent("clean\(k).srt"); try? out.write(to: f, atomically: true, encoding: .utf8)
        inputs += ["-i", f.path]; extra[k] = extra.count + 1
        lines.append("Sottotitoli \(k + 1): tolte \(all.count - keep.count) battute con pubblicità o crediti")
    }
    var a = ["-nostdin", "-y", "-v", "error", "-progress", "pipe:2", "-nostats"]
    if s0 > 0 { a += ["-ss", secs(s0)] }
    a += ["-i", path] + inputs
    if e0 < pr.duration { a += ["-t", secs(e0 - s0)] }
    a += ["-map_chapters", "0", "-map_metadata", "0", "-c", "copy"]   // base: tutto copiato; le opzioni per-traccia che seguono hanno la precedenza
    if ext == "mp4" || ext == "m4v" || ext == "mov" { a += ["-c:s", "mov_text", "-movflags", "+faststart"] }
    for s in pr.streams where s["codec_type"] as? String == "video" { a += ["-map", "0:\(s["index"] as? Int ?? 0)"] }
    var j = 0
    for (i, s) in audio.enumerated() where !plan.dropAudio.contains(i) {
        a += ["-map", "0:a:\(i)"]
        if let l = plan.lang["a\(i)"] { a += ["-metadata:s:a:\(j)", "language=\(l)"] }
        if let d = plan.audioDefault { a += ["-disposition:a:\(j)", i == d ? "default" : "0"] }
        if plan.normalize.contains(i) || plan.boostCenter.contains(i) {
            let br = min(dbl(s["bit_rate"]) ?? dbl(tags(s)["bps"]) ?? 448_000, 640_000)
            var chain: [String] = []
            if plan.boostCenter.contains(i) {   // +4 dB solo al canale centrale (i dialoghi), gli altri invariati; il limitatore evita il clipping
                let lay = (s["channel_layout"] as? String) ?? "5.1"
                chain.append("pan=\(lay)|c0=c0|c1=c1|c2=1.585*c2|c3=c3|c4=c4|c5=c5,alimiter=limit=0.9:level=false")
                lines.append("Audio \(i + 1): canale centrale (dialoghi) alzato di 4 dB")
            }
            if plan.normalize.contains(i) { chain.append(dynamicsChain); lines.append("Audio \(i + 1): dinamica livellata (\(dynamicsChain.split(separator: ",")[0]) + limitatore)") }
            a += ["-c:a:\(j)", "ac3", "-b:a:\(j)", "\(Int(max(br, 192_000)))", "-filter:a:\(j)", chain.joined(separator: ",")]
            lines.append("Audio \(i + 1): ricodificata in AC3")
        }
        j += 1
    }
    var m = 0
    for (i, s) in subs.enumerated() where !plan.dropSubs.contains(i) {
        if let x = extra[i] { a += ["-map", "\(x):0"]; let tg = tags(s); if !lang(s).isEmpty { a += ["-metadata:s:s:\(m)", "language=\(lang(s))"] }; if let t = tg["title"] { a += ["-metadata:s:s:\(m)", "title=\(t)"] } }
        else { a += ["-map", "0:s:\(i)"] }
        if let l = plan.lang["s\(i)"] { a += ["-metadata:s:s:\(m)", "language=\(l)"] }
        let forced = disp(s, "forced") == 1; var flags: [String] = []
        switch plan.subDefault { case .none: break; case .track(let k): if i == k { flags.append("default") }; case .keep: if disp(s, "default") == 1 { flags.append("default") } }
        if forced { flags.append("forced") }
        if plan.subDefault != .keep || extra[i] != nil { a += ["-disposition:s:\(m)", flags.isEmpty ? "0" : flags.joined(separator: "+")] }
        m += 1
    }
    if ext == "mkv" { a += ["-map", "0:t?"] }
    if ext == "avi" { a += ["-sn"] }
    let final = a + [tmp.path]
    let total = max(1, e0 - s0)
    progress(0.05, "Scrittura del nuovo file…")
    var errs: [String] = []
    let o = run(ff, final) { l in
        if let mm = l.match(#"out_time_us=(\d+)"#), let us = Double(mm[1]) { progress(0.05 + 0.75 * min(1, us / 1e6 / total), "Scrittura del nuovo file…") }
        else if !l.contains("=") && !l.isEmpty { errs.append(l) }
    }
    guard o.status == 0, FileManager.default.fileExists(atPath: tmp.path) else { return FixResult(ok: false, message: "ffmpeg non è riuscito: \(errs.suffix(2).joined(separator: " "))") }

    // verifica del risultato prima di sostituire qualunque cosa
    progress(0.82, "Verifica del nuovo file…")
    guard let np = Probe(tmp.path) else { return FixResult(ok: false, message: "Il nuovo file non è leggibile: l'originale non è stato toccato.") }
    let expA = audio.count - plan.dropAudio.count, expS = ext == "avi" ? 0 : subs.count - plan.dropSubs.count
    if np.audio.count != expA || np.subs.count != expS { return FixResult(ok: false, message: "Il nuovo file ha un numero di tracce diverso dal previsto (audio \(np.audio.count)/\(expA), sottotitoli \(np.subs.count)/\(expS)): l'originale non è stato toccato.") }
    if abs(np.duration - (e0 - s0)) > 3 { return FixResult(ok: false, message: String(format: "Durata del nuovo file %@ diversa dal previsto %@: l'originale non è stato toccato.", hms(np.duration), hms(e0 - s0))) }
    // l'audio non deve avere buchi in più rispetto all'originale (un buco può nascere in silenzio dopo una ricodifica o un taglio)
    func packetIssues(_ p: Probe, _ path: String) -> Int { let c = Collector(); scanPackets(p, path, c); return c.findings.filter { $0.sev >= .warn }.count }
    let before = packetIssues(pr, path), after = packetIssues(np, tmp.path)
    if after > before { return FixResult(ok: false, message: "Il controllo dei flussi ha trovato \(after - before) problemi di audio/video nel nuovo file: l'originale non è stato toccato.") }
    var warn = ""
    for k in plan.normalize.union(plan.boostCenter).sorted() {
        let outOrd = (0..<k).filter { !plan.dropAudio.contains($0) }.count
        progress(0.85 + 0.1 * Double(outOrd) / Double(max(1, plan.normalize.count)), "Misura del volume (traccia \(k + 1))…")
        if let b = measureLoudness(path, k), let af = measureLoudness(tmp.path, outOrd) {
            lines.append("Audio \(k + 1) prima: \(lufs(b))"); lines.append("Audio \(k + 1) dopo:  \(lufs(af))")
            if af.2 > -0.1 { warn = " Attenzione: il picco dopo la correzione è molto alto." }
        }
        if plan.boostCenter.contains(k), let b = dialogueStats(path, k), let af = dialogueStats(tmp.path, outOrd) {
            lines.append(String(format: "Audio %d musica sopra i dialoghi (>6 LU) prima: %.0f%% dei momenti con parlato — dopo: %.0f%%", k + 1, b.coveredPct, af.coveredPct))
        }
    }
    // sostituzione: l'originale diventa .orig_backup (se si è toccato il contenuto) oppure va nel Cestino (solo etichette)
    progress(0.97, "Sostituzione del file…")
    let old = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
    var bk: URL?
    do {
        if plan.changesContent { let b = backupURL(for: url); try FileManager.default.moveItem(at: url, to: b); bk = b }
        else { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        try FileManager.default.moveItem(at: tmp, to: url)
    } catch { if let b = bk { try? FileManager.default.moveItem(at: b, to: url) }; return FixResult(ok: false, message: "Sostituzione non riuscita: \(error.localizedDescription)") }
    if let d = old { try? FileManager.default.setAttributes([.modificationDate: d], ofItemAtPath: path) }
    progress(1, "Fatto")
    let msg = plan.changesContent ? "Fatto. L'originale è stato conservato come «\(bk!.lastPathComponent)».\(warn)" : "Fatto. Etichette aggiornate (la versione precedente è nel Cestino)."
    return FixResult(ok: true, message: msg, lines: lines, backup: bk)
}
