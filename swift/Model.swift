import Foundation

enum Sev: Int, Comparable { case ok, info, warn, error
    static func < (a: Sev, b: Sev) -> Bool { a.rawValue < b.rawValue }
    var label: String { ["OK", "Nota", "Attenzione", "Problema"][rawValue] }
}
/// Correzione suggerita da una segnalazione (i numeri sono posizioni all'interno del proprio tipo: audio 0, 1…, sottotitoli 0, 1…).
enum FixHint { case defaultAudio(Int), defaultSub(Int?), setLang(String, Int), cleanSub(Int), dropSub(Int), trimStart(Double), trimEnd(Double), normalize(Int), boostCenter(Int) }
struct Finding: Identifiable { let id = UUID(); var sev: Sev; var area: String; var title: String; var detail: String; var time: Double?; var thumb: URL?; var fixes: [FixHint] = [] }
struct TrackInfo: Identifiable { var id: Int { ord }; var ord: Int; var lang: String; var title: String; var codec: String; var channels: Int; var isDefault: Bool; var forced: Bool; var image: Bool; var bitrate: Double }
struct KV: Identifiable { let id = UUID(); var k: String; var v: String }
struct Section: Identifiable { let id = UUID(); var title: String; var order: Int; var rows: [KV] }

struct Report {
    var file: URL; var duration = 0.0; var findings: [Finding] = []; var tech: [Section] = []; var seconds = 0.0; var audioTracks: [TrackInfo] = []; var subTracks: [TrackInfo] = []
    var worst: Sev { findings.map(\.sev).max() ?? .ok }
    var verdict: String { switch worst { case .error: return "Problemi da risolvere"; case .warn: return "Da controllare"; default: return "Pronto per la sala" } }
    var counts: (err: Int, warn: Int, info: Int) { (findings.filter { $0.sev == .error }.count, findings.filter { $0.sev == .warn }.count, findings.filter { $0.sev == .info }.count) }
    var text: String {
        var s = "MOVIE PREFLIGHT — \(file.lastPathComponent)\nEsito: \(verdict)  (\(counts.err) problemi, \(counts.warn) attenzioni, \(counts.info) note)\n\n"
        for f in findings.sorted(by: { $0.sev > $1.sev }) where f.sev > .ok {
            s += "[\(f.sev.label.uppercased())] \(f.area): \(f.title)" + (f.time.map { " (a \(hms($0)))" } ?? "") + "\n" + (f.detail.isEmpty ? "" : "    \(f.detail.replacingOccurrences(of: "\n", with: "\n    "))\n")
        }
        s += "\nDATI TECNICI\n"
        for sec in tech.sorted(by: { $0.order < $1.order }) { s += "\n\(sec.title)\n"; for r in sec.rows { s += "  \(r.k): \(r.v)\n" } }
        return s
    }
}

/// Raccoglie segnalazioni e dati dalle analisi che girano in parallelo.
final class Collector {
    private let lock = NSLock(); private var fs: [Finding] = []; private var secs: [String: Section] = [:]
    func add(_ sev: Sev, _ area: String, _ title: String, _ detail: String = "", time: Double? = nil, thumb: URL? = nil, fix: [FixHint] = []) {
        lock.lock(); fs.append(Finding(sev: sev, area: area, title: title, detail: detail, time: time, thumb: thumb, fixes: fix)); lock.unlock()
    }
    func rows(_ title: String, order: Int, _ kv: [(String, String)]) {
        lock.lock(); var s = secs[title] ?? Section(title: title, order: order, rows: []); s.rows += kv.map { KV(k: $0.0, v: $0.1) }; secs[title] = s; lock.unlock()
    }
    var findings: [Finding] { lock.lock(); defer { lock.unlock() }; return fs }
    var sections: [Section] { lock.lock(); defer { lock.unlock() }; return Array(secs.values) }
}
