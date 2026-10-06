import SwiftUI
import UniformTypeIdentifiers
import AppKit

final class Job: ObservableObject, Identifiable {
    let id = UUID(); @Published var url: URL
    @Published var progress = 0.0; @Published var stage = "In coda"; @Published var report: Report?
    @Published var fixProgress: Double?; @Published var fixStage = ""; @Published var fixResult: FixResult?
    init(_ u: URL) { url = u }
}
final class Store: ObservableObject {
    @Published var jobs: [Job] = []; @Published var selection: UUID?; @Published var modelProgress: Double?
    private let q = DispatchQueue(label: "analisi")   // un film alla volta: le analisi usano già tutti i core
    static let exts: Set<String> = ["mp4", "mkv", "avi", "m4v", "mov"]
    func add(_ urls: [URL]) {
        let files = urls.flatMap { u -> [URL] in
            var d: ObjCBool = false; FileManager.default.fileExists(atPath: u.path, isDirectory: &d)
            if d.boolValue { return ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path } }; return [u] }
            .filter { Store.exts.contains($0.pathExtension.lowercased()) }
        if !files.isEmpty { askOnline() }
        if !files.isEmpty && whisperModelPath() == nil && tool("whisper-cli") != nil && !UserDefaults.standard.bool(forKey: "speechOfferAsked") && ProcessInfo.processInfo.environment["MOVIEPREFLIGHT_NOPROMPT"] == nil { UserDefaults.standard.set(true, forKey: "speechOfferAsked"); offerSpeechModel() }
        for u in files { let j = Job(u); jobs.append(j); selection = j.id; startAnalysis(j) }
    }
    func startAnalysis(_ j: Job) {
        j.report = nil; j.progress = 0; j.stage = "In coda"; j.fixResult = nil
        q.async { [weak j] in
            guard let j = j else { return }
            let r = analyze(j.url) { p, s in DispatchQueue.main.async { j.progress = p; j.stage = s } }
            DispatchQueue.main.async { j.report = r; j.progress = 1 }
        }
    }
    /// Chiede il consenso e scarica il modello vocale (whisper, open source, 148 MB) per i controlli sulla lingua parlata e sulla sincronia dei sottotitoli.
    func offerSpeechModel() {
        let a = NSAlert()
        if whisperModelPath() != nil { a.messageText = "Controlli sul parlato attivi"; a.informativeText = "Il modello vocale è già installato."; a.runModal(); return }
        a.messageText = "Controlli sul parlato"
        a.informativeText = "Per verificare la lingua realmente parlata nelle tracce audio e la sincronia dei sottotitoli serve un modello vocale open source (whisper, 148 MB, scaricato una sola volta). I film non vengono mai inviati da nessuna parte: l'analisi resta sul tuo Mac."
        a.addButton(withTitle: "Scarica"); a.addButton(withTitle: "Non ora")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        modelProgress = 0
        DispatchQueue.global().async { [weak self] in
            let ok = downloadWhisperModel { p in DispatchQueue.main.async { self?.modelProgress = p } }
            DispatchQueue.main.async {
                self?.modelProgress = nil
                if !ok { let e = NSAlert(); e.messageText = "Scaricamento non riuscito"; e.informativeText = "Controlla la connessione e riprova da File → Controlli sul parlato…"; e.runModal() }
                else { let e = NSAlert(); e.messageText = "Modello scaricato"; e.informativeText = "Premi «Rianalizza» sui film già analizzati per aggiungere i controlli sul parlato."; e.runModal() }
            }
        }
    }
    /// Applica una correzione (una per volta, dopo l'analisi in corso) e poi rianalizza il film per mostrare l'effetto.
    func fix(_ j: Job, _ plan: FixPlan) {
        var p = plan; let newBase = p.rename; p.rename = nil
        j.fixProgress = 0; j.fixStage = "In attesa…"; j.fixResult = nil
        q.async {
            var r = p.isEmpty ? FixResult(ok: true, message: "") : applyFix(j.url, p) { v, s in DispatchQueue.main.async { j.fixProgress = v; j.fixStage = s } }
            if r.ok, let nb = newBase { let rr = renameFile(j.url, to: nb); r = FixResult(ok: rr.ok, message: (r.message.isEmpty ? "" : r.message + " ") + rr.message, lines: r.lines, backup: r.backup, newURL: rr.newURL) }
            let target = r.newURL ?? j.url
            let rep = r.ok ? analyze(target) : nil
            DispatchQueue.main.async { if let u = r.newURL { j.url = u }; j.fixResult = r; j.fixProgress = nil; if let rep = rep { j.report = rep } }
        }
    }
    /// Mostra tutto quello che verrà fatto e applica solo dopo il consenso (Correggi / Altre opzioni… / Annulla).
    func confirmFix(_ j: Job, _ plan: FixPlan, more: @escaping () -> Void) {
        guard let rep = j.report else { return }
        let lines = plan.summary(rep); guard !lines.isEmpty else { return }
        let a = NSAlert(); a.messageText = lines.count == 1 ? "Correggere questo?" : "Correggere queste cose?"
        a.informativeText = lines.map { "• " + $0 }.joined(separator: "\n") + "\n\n" + (plan.changesContent ? "L'originale resta nella stessa cartella come «\(backupURL(for: j.url).lastPathComponent)» e potrai annullare." : "Cambiano solo etichette o nome del file: nessuna riscrittura del film.")
        a.addButton(withTitle: "Correggi"); a.addButton(withTitle: "Altre opzioni…"); a.addButton(withTitle: "Annulla")
        switch a.runModal() { case .alertFirstButtonReturn: fix(j, plan); case .alertSecondButtonReturn: more(); default: break }
    }
    /// Consenso alle ricerche online (solo il titolo ricavato dal nome del file viene inviato a Wikidata e Wikipedia).
    func askOnline(force: Bool = false) {
        if ProcessInfo.processInfo.environment["MOVIEPREFLIGHT_NOPROMPT"] != nil { onlineLookups = ProcessInfo.processInfo.environment["MOVIEPREFLIGHT_ONLINE"] != nil; return }   // solo per le prove a vista
        if !force && UserDefaults.standard.object(forKey: "metaConsent") != nil { return }
        let a = NSAlert(); a.messageText = "Cercare i dati del film online?"
        a.informativeText = "Movie Preflight può trovare titolo, anno, regista, durata, locandina e descrizione su Wikidata e Wikipedia (servizi liberi, nessuna chiave). Per farlo invia soltanto il titolo e l'anno ricavati dal nome del file: i film non vengono mai inviati. Servono per confrontare la durata, suggerire il nome del file e mostrare la scheda del film."
        a.addButton(withTitle: UserDefaults.standard.bool(forKey: "metaConsent") ? "Lascia attivo" : "Consenti"); a.addButton(withTitle: UserDefaults.standard.bool(forKey: "metaConsent") ? "Disattiva" : "Non ora")
        let yes = a.runModal() == .alertFirstButtonReturn; UserDefaults.standard.set(yes, forKey: "metaConsent"); onlineLookups = yes
    }
    /// Annulla l'ultima correzione: il file corrente va nel Cestino e torna l'originale conservato.
    func restore(_ j: Job) {
        guard let b = j.fixResult?.backup else { return }
        j.fixProgress = 0; j.fixStage = "Ripristino dell'originale…"
        q.async {
            var msg = FixResult(ok: true, message: "Originale ripristinato.")
            do { try FileManager.default.trashItem(at: j.url, resultingItemURL: nil); try FileManager.default.moveItem(at: b, to: j.url) } catch { msg = FixResult(ok: false, message: "Ripristino non riuscito: \(error.localizedDescription)") }
            let rep = analyze(j.url)
            DispatchQueue.main.async { j.fixResult = msg; j.fixProgress = nil; j.report = rep }
        }
    }
    init() { onlineLookups = UserDefaults.standard.bool(forKey: "metaConsent") }
    func open() { let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.message = "Scegli uno o più film"; if p.runModal() == .OK { add(p.urls) } }
}

extension Sev {
    var color: Color { switch self { case .ok: return .green; case .info: return .blue; case .warn: return .orange; case .error: return .red } }
    var symbol: String { ["checkmark.circle.fill", "info.circle.fill", "exclamationmark.triangle.fill", "xmark.octagon.fill"][rawValue] }
}

struct ContentView: View {
    @ObservedObject var store: Store; @State private var hover = false
    var body: some View {
        Group {
            if store.jobs.isEmpty { DropHint(store: store) }
            else { HStack(spacing: 0) {
                List(store.jobs, selection: $store.selection) { j in JobRow(job: j).tag(j.id) }.frame(width: 250).listStyle(.sidebar)
                Divider()
                if let j = store.jobs.first(where: { $0.id == store.selection }) { JobDetail(job: j, store: store).id(j.id) } else { Spacer() }
            } }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $hover) { ps in
            for p in ps { _ = p.loadObject(ofClass: URL.self) { u, _ in if let u = u { DispatchQueue.main.async { store.add([u]) } } } }; return true }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: hover ? 3 : 0).padding(6).allowsHitTesting(false))
        .toolbar {
            if let p = store.modelProgress { ToolbarItem { HStack { Text("Scarico il modello vocale…").font(.caption).foregroundStyle(.secondary); ProgressView(value: p).frame(width: 110) } } }
            ToolbarItem { Button { store.open() } label: { Label("Aggiungi film", systemImage: "plus") } }
        }
    }
}
struct DropHint: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack").font(.system(size: 54, weight: .thin)).foregroundStyle(.secondary)
            Text("Trascina qui un film").font(.title2.weight(.medium))
            Text("mp4, mkv, avi — anche più file o una cartella").foregroundStyle(.secondary)
            Text("Controllo di immagine, audio e sottotitoli: crediti del torrent, lingue, volume, sincronia, difetti tecnici.").font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Scegli un film…") { store.open() }.controlSize(.large)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct JobRow: View {
    @ObservedObject var job: Job
    var body: some View {
        HStack(spacing: 8) {
            if let r = job.report { Image(systemName: r.worst.symbol).foregroundStyle(r.worst.color) } else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 1) {
                Text(job.report?.meta?.title ?? job.url.deletingPathExtension().lastPathComponent).lineLimit(2).font(.callout)
                Text(job.report?.verdict ?? job.stage).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 2)
    }
}
struct FixBanner: View {
    let result: FixResult; let undo: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(result.ok ? Color.green : Color.red).font(.system(size: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(result.message).font(.callout.weight(.semibold)).textSelection(.enabled)
                ForEach(Array(result.lines.enumerated()), id: \.offset) { Text($0.element).font(.callout.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled) }
                if result.ok && result.backup != nil { Button("Annulla la correzione (torna l'originale)") { undo() }.controlSize(.small).padding(.top, 2) }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill((result.ok ? Color.green : Color.red).opacity(0.09)))
    }
}
