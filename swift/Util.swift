import Foundation

/// Strumenti esterni: prima quelli dentro l'app, poi Homebrew.
let toolDirs: [String] = { (Bundle.main.resourcePath.map { [$0] } ?? []) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] }()
func tool(_ n: String) -> String? { toolDirs.map { $0 + "/" + n }.first { FileManager.default.isExecutableFile(atPath: $0) } }

struct Out { var out = Data(); var err = ""; var status: Int32 = -1; var text: String { String(decoding: out, as: UTF8.self) } }

/// Esegue un programma e attende la fine. `onErr` riceve lo stderr riga per riga mentre arriva (ffmpeg scrive lì i suoi log).
@discardableResult
func run(_ exe: String, _ args: [String], onErr: ((String) -> Void)? = nil) -> Out {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e; p.standardInput = FileHandle.nullDevice
    let lock = NSLock(); var outD = Data(), errD = Data(), pend = Data()
    func lines(_ d: Data, final: Bool = false) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pend.append(d); var r: [String] = []
        while let i = pend.firstIndex(where: { $0 == 10 || $0 == 13 }) { r.append(String(decoding: pend[pend.startIndex..<i], as: UTF8.self)); pend.removeSubrange(pend.startIndex...i) }
        if final && !pend.isEmpty { r.append(String(decoding: pend, as: UTF8.self)); pend = Data() }
        return r
    }
    o.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; lock.lock(); outD.append(d); lock.unlock() }
    e.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; lock.lock(); errD.append(d); lock.unlock(); if let cb = onErr { lines(d).forEach(cb) } }
    do { try p.run() } catch { return Out(err: "\(error)") }
    p.waitUntilExit()
    o.fileHandleForReading.readabilityHandler = nil; e.fileHandleForReading.readabilityHandler = nil
    let rest = o.fileHandleForReading.readDataToEndOfFile(); let rerr = e.fileHandleForReading.readDataToEndOfFile()
    lock.lock(); outD.append(rest); errD.append(rerr); lock.unlock()
    if let cb = onErr { lines(rerr, final: true).forEach(cb) }
    return Out(out: outD, err: String(decoding: errD, as: UTF8.self), status: p.terminationStatus)
}

func dbl(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }; if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }; return nil
}
/// "24000/1001" → 23.976
func ratio(_ s: Any?) -> Double? {
    guard let s = s as? String else { return dbl(s) }
    let p = s.split(separator: "/").compactMap { Double($0) }
    if p.count == 2 { return p[1] == 0 ? nil : p[0] / p[1] }; return p.first
}
func hms(_ s: Double) -> String {
    let t = max(0, Int(s.rounded())); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
func fmtBytes(_ b: Double) -> String { b >= 1e9 ? String(format: "%.2f GB", b / 1e9) : String(format: "%.0f MB", b / 1e6) }
func fmtRate(_ bps: Double) -> String { bps >= 1e6 ? String(format: "%.1f Mb/s", bps / 1e6) : String(format: "%.0f kb/s", bps / 1e3) }
/// "01:41:36.667000000" → secondi
func parseClock(_ s: String) -> Double? {
    let p = s.split(separator: ":").map { Double($0) }
    guard p.count == 3, let h = p[0], let m = p[1], let sec = p[2] else { return nil }; return h * 3600 + m * 60 + sec
}
extension String {
    func match(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options), let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: self).map { String(self[$0]) } ?? "" }
    }
    func has(_ pattern: String) -> Bool { range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
}
