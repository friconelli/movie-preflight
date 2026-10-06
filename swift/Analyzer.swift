import Foundation

/// Avanzamento complessivo (0...1) come media delle fasi, che girano in parallelo.
final class Progress {
    private let lock = NSLock(); private var parts: [String: Double] = [:]; private var names: [String: String] = [:]
    let total: Int; let cb: (Double, String) -> Void
    init(total: Int, cb: @escaping (Double, String) -> Void) { self.total = total; self.cb = cb }
    func set(_ stage: String, _ frac: Double, _ label: String? = nil) {
        lock.lock(); parts[stage] = min(1, frac); if let l = label { names[stage] = l }
        let p = parts.values.reduce(0, +) / Double(total); let active = parts.filter { $0.value < 1 }.keys.sorted().compactMap { names[$0] }.first ?? "Fine"; lock.unlock()
        cb(p, active)
    }
}

/// Analizza un film: lancia le fasi in parallelo e restituisce il rapporto.
func analyze(_ url: URL, progress: @escaping (Double, String) -> Void = { _, _ in }) -> Report {
    let t0 = Date(); let path = url.path; let col = Collector()
    var rep = Report(file: url)
    guard tool("ffprobe") != nil, tool("ffmpeg") != nil else {
        col.add(.error, "File", "ffmpeg non trovato", "Servono ffmpeg e ffprobe (brew install ffmpeg).")
        rep.findings = col.findings; return rep
    }
    guard let pr = Probe(path), pr.duration > 0 || !pr.streams.isEmpty else {
        col.add(.error, "File", "File non leggibile", "ffprobe non riesce ad aprirlo: file danneggiato, incompleto o non è un video.")
        rep.findings = col.findings; rep.seconds = Date().timeIntervalSince(t0); return rep
    }
    rep.duration = pr.duration
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("collaudo-" + UUID().uuidString); try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let nAudio = min(pr.audio.count, 3)
    let prog = Progress(total: 5 + nAudio) { progress($0, $1) }
    prog.set("0probe", 1, "Lettura dei dati")
    checkContainer(pr, url, col); checkVideo(pr, col); checkAudioStreams(pr, col); checkSubStreams(pr, col)

    let g = DispatchGroup(); let q = DispatchQueue.global(qos: .userInitiated)
    func go(_ stage: String, _ label: String, _ work: @escaping () -> Void) {
        prog.set(stage, 0, label); g.enter(); q.async { work(); prog.set(stage, 1); g.leave() }
    }
    go("1pacchetti", "Controllo dei flussi") { scanPackets(pr, path, col) }
    go("2video", "Analisi dell'immagine") { scanVideoWindows(pr, path, col) { prog.set("2video", $0) } }
    go("3titoli", "Ricerca dei crediti nelle immagini") { scanCredits(pr, path, tmp, col) { prog.set("3titoli", $0) } }
    go("4sub", "Lettura dei sottotitoli") { scanSubtitles(pr, path, tmp, col) }
    for k in 0..<nAudio { go("5audio\(k)", "Misura dell'audio (traccia \(k + 1))") { scanAudio(pr, path, k, col) { prog.set("5audio\(k)", $0) } } }
    g.wait()

    rep.findings = col.findings; rep.tech = col.sections; rep.seconds = Date().timeIntervalSince(t0)
    if rep.findings.allSatisfy({ $0.sev <= .info }) { rep.findings.append(Finding(sev: .ok, area: "File", title: "Nessun problema rilevato", detail: "", time: nil, thumb: nil)) }
    return rep
}
