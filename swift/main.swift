import Foundation

func arg(_ n: String) -> [String] { CommandLine.arguments.enumerated().filter { $0.element == n && $0.offset + 1 < CommandLine.arguments.count }.map { CommandLine.arguments[$0.offset + 1] } }

if let f = arg("--analyze").first {
    let r = analyze(URL(fileURLWithPath: f)) { p, s in FileHandle.standardError.write(Data(String(format: "\r%3.0f%% %@                    ", p * 100, s).utf8)) }
    FileHandle.standardError.write(Data("\n".utf8)); print(r.text); print(String(format: "(analisi in %.0f s)", r.seconds)); exit(0)
}
// Correzioni da riga di comando (per i test): --fix FILE [--audio-default N] [--sub-default none|N] [--lang a0=ita,s1=eng] [--clean-sub N] [--drop-sub N] [--drop-audio N] [--trim-start S] [--trim-end S] [--normalize N]   (N parte da 0)
if let f = arg("--fix").first {
    var p = FixPlan()
    p.audioDefault = arg("--audio-default").first.flatMap { Int($0) }
    if let s = arg("--sub-default").first { p.subDefault = s == "none" ? .none : Int(s).map { .track($0) } ?? .keep }
    for l in arg("--lang") { for kv in l.split(separator: ",") { let x = kv.split(separator: "="); if x.count == 2 { p.lang[String(x[0])] = String(x[1]) } } }
    arg("--clean-sub").compactMap { Int($0) }.forEach { p.cleanSubs.insert($0) }; arg("--drop-sub").compactMap { Int($0) }.forEach { p.dropSubs.insert($0) }
    arg("--drop-audio").compactMap { Int($0) }.forEach { p.dropAudio.insert($0) }; arg("--normalize").compactMap { Int($0) }.forEach { p.normalize.insert($0) }
    p.trimStart = arg("--trim-start").first.flatMap { Double($0) }; p.trimEnd = arg("--trim-end").first.flatMap { Double($0) }
    let r = applyFix(URL(fileURLWithPath: f), p) { v, s in FileHandle.standardError.write(Data(String(format: "\r%3.0f%% %@                    ", v * 100, s).utf8)) }
    FileHandle.standardError.write(Data("\n".utf8)); print((r.ok ? "OK: " : "ERRORE: ") + r.message); r.lines.forEach { print("  " + $0) }; exit(r.ok ? 0 : 1)
}
CollaudoApp.main()
