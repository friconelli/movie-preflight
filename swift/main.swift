import Foundation

if let i = CommandLine.arguments.firstIndex(of: "--analyze"), CommandLine.arguments.count > i + 1 {
    let r = analyze(URL(fileURLWithPath: CommandLine.arguments[i + 1])) { p, s in FileHandle.standardError.write(Data(String(format: "\r%3.0f%% %@                    ", p * 100, s).utf8)) }
    FileHandle.standardError.write(Data("\n".utf8)); print(r.text); print(String(format: "(analisi in %.0f s)", r.seconds)); exit(0)
}
CollaudoApp.main()
