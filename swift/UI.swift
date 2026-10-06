import SwiftUI
import UniformTypeIdentifiers
import AppKit

final class Job: ObservableObject, Identifiable {
    let id = UUID(); let url: URL
    @Published var progress = 0.0; @Published var stage = "In coda"; @Published var report: Report?
    @Published var fixProgress: Double?; @Published var fixStage = ""; @Published var fixResult: FixResult?
    init(_ u: URL) { url = u }
}
final class Store: ObservableObject {
    @Published var jobs: [Job] = []; @Published var selection: UUID?
    private let q = DispatchQueue(label: "analisi")   // un film alla volta: le analisi usano già tutti i core
    static let exts: Set<String> = ["mp4", "mkv", "avi", "m4v", "mov"]
    func add(_ urls: [URL]) {
        let files = urls.flatMap { u -> [URL] in
            var d: ObjCBool = false; FileManager.default.fileExists(atPath: u.path, isDirectory: &d)
            if d.boolValue { return ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path } }; return [u] }
            .filter { Store.exts.contains($0.pathExtension.lowercased()) }
        for u in files {
            let j = Job(u); jobs.append(j); selection = j.id
            q.async { [weak j] in
                guard let j = j else { return }
                let r = analyze(j.url) { p, s in DispatchQueue.main.async { j.progress = p; j.stage = s } }
                DispatchQueue.main.async { j.report = r; j.progress = 1 }
            }
        }
    }
    /// Applica una correzione (una per volta, dopo l'analisi in corso) e poi rianalizza il film per mostrare l'effetto.
    func fix(_ j: Job, _ plan: FixPlan) {
        j.fixProgress = 0; j.fixStage = "In attesa…"; j.fixResult = nil
        q.async {
            let r = applyFix(j.url, plan) { p, s in DispatchQueue.main.async { j.fixProgress = p; j.fixStage = s } }
            let rep = r.ok ? analyze(j.url) : nil
            DispatchQueue.main.async { j.fixResult = r; j.fixProgress = nil; if let rep = rep { j.report = rep } }
        }
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
        .toolbar { ToolbarItem { Button { store.open() } label: { Label("Aggiungi film", systemImage: "plus") } } }
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
                Text(job.url.deletingPathExtension().lastPathComponent).lineLimit(2).font(.callout)
                Text(job.report?.verdict ?? job.stage).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 2)
    }
}
struct JobDetail: View {
    @ObservedObject var job: Job; let store: Store; @State private var area = "Tutto"; @State private var sheetPlan: FixPlan?
    var body: some View {
        if let r = job.report {
            let areas = ["Tutto", "File", "Video", "Audio", "Sottotitoli"]
            let shown = r.findings.filter { area == "Tutto" || $0.area == area }.sorted { ($0.sev, $1.time ?? 0) > ($1.sev, $0.time ?? 0) }
            ScrollView { VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: r.worst.symbol).font(.system(size: 34)).foregroundStyle(r.worst.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.file.deletingPathExtension().lastPathComponent).font(.title3.weight(.semibold)).lineLimit(2)
                        Text(r.verdict).font(.headline).foregroundStyle(r.worst.color)
                        let c = r.counts; Text("\(c.err) problemi · \(c.warn) attenzioni · \(c.info) note — analisi in \(Int(r.seconds)) s").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { sheetPlan = FixPlan() } label: { Label("Correggi…", systemImage: "wand.and.stars") }.disabled(job.fixProgress != nil)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.text, forType: .string) } label: { Label("Copia", systemImage: "doc.on.doc") }
                    Button { save(r) } label: { Label("Salva…", systemImage: "square.and.arrow.down") }
                }
                if let fr = job.fixResult { FixBanner(result: fr) { store.restore(job) } }
                if job.fixProgress != nil { HStack { ProgressView(value: job.fixProgress).frame(width: 200); Text(job.fixStage).font(.callout).foregroundStyle(.secondary) } }
                Picker("", selection: $area) { ForEach(areas, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                ForEach(shown) { f in FindingCard(f: f) { var p = FixPlan(); f.fixes.forEach { p.merge($0) }; sheetPlan = p } }
                if shown.isEmpty { Text("Nessuna segnalazione in quest'area.").foregroundStyle(.secondary) }
                Divider().padding(.vertical, 4)
                Text("Dati tecnici").font(.headline)
                ForEach(r.tech.sorted { $0.order < $1.order }) { s in
                    DisclosureGroup(s.title) {
                        VStack(alignment: .leading, spacing: 4) { ForEach(s.rows) { row in HStack(alignment: .top) { Text(row.k).foregroundStyle(.secondary).frame(width: 190, alignment: .leading); Text(row.v).textSelection(.enabled) } }.font(.callout) }.padding(.top, 4)
                    }
                }
            }.padding(20) }
            .onAppear { if ProcessInfo.processInfo.environment["COLLAUDO_SHEET"] != nil { var p = FixPlan(); r.findings.forEach { $0.fixes.forEach { p.merge($0) } }; sheetPlan = p } }   // solo per le prove a vista
            .sheet(isPresented: Binding(get: { sheetPlan != nil }, set: { if !$0 { sheetPlan = nil } })) { FixSheet(job: job, report: r, plan: sheetPlan ?? FixPlan(), store: store).onChange(of: job.fixProgress == nil) { _ in } }
            .onChange(of: job.fixProgress != nil) { running in if running { /* resta aperta per mostrare l'avanzamento */ } else { sheetPlan = nil } }
        } else {
            VStack(spacing: 12) {
                Text(job.url.lastPathComponent).font(.headline).lineLimit(2)
                ProgressView(value: job.progress).frame(width: 320)
                Text(job.stage).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    func save(_ r: Report) {
        let p = NSSavePanel(); p.nameFieldStringValue = r.file.deletingPathExtension().lastPathComponent + " — collaudo.txt"; p.allowedContentTypes = [.plainText]
        if p.runModal() == .OK, let u = p.url { try? r.text.write(to: u, atomically: true, encoding: .utf8) }
    }
}
struct FindingCard: View {
    let f: Finding; var onFix: () -> Void = {}
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: f.sev.symbol).foregroundStyle(f.sev.color).font(.system(size: 17)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(f.title).font(.callout.weight(.semibold)).textSelection(.enabled)
                    Spacer(minLength: 8)
                    if let t = f.time { Text(hms(t)).font(.caption.monospacedDigit()).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.18))) }
                    Text(f.area).font(.caption).foregroundStyle(.secondary)
                }
                if !f.detail.isEmpty { Text(f.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if !f.fixes.isEmpty { Button { onFix() } label: { Label("Correggi…", systemImage: "wand.and.stars") }.controlSize(.small).padding(.top, 2) }
                if let t = f.thumb, let img = NSImage(contentsOf: t) { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 150).cornerRadius(5).padding(.top, 4) }
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(f.sev.color.opacity(0.09))).overlay(RoundedRectangle(cornerRadius: 8).stroke(f.sev.color.opacity(0.35)))
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
