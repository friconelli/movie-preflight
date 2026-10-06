import SwiftUI
import AppKit

/// Etichetta breve e chiara del pulsante per una correzione.
func fixLabel(_ h: FixHint) -> String {
    switch h {
    case .repairEncoding: return "Ripara gli accenti"
    case .cleanSub: return "Togli la pubblicità"
    case .defaultAudio: return "Imposta come predefinita"
    case .defaultSub: return "Spegni di default"
    case .setLang, .setLangTo: return "Imposta la lingua"
    case .setForced(_, let f): return f ? "Marca come forzati" : "Togli «forzati»"
    case .dropSub: return "Elimina la traccia"
    case .toDolby: return "Converti in Dolby"
    case .levelGain: return "Regola il volume"
    case .boostCenter: return "Alza i dialoghi"
    case .normalize: return "Compressione"
    case .trimStart, .trimEnd: return "Taglia"
    case .deinterlace: return "Deinterlaccia"
    case .tonemap: return "Converti in SDR"
    case .clearTitle: return "Togli il titolo"
    case .syncSubs: return "Risincronizza"
    case .rename: return "Rinomina il file"
    }
}
/// Operazioni che «Correggi tutto» non include: cancellano tracce o richiedono una ricodifica lunga.
func isHeavy(_ h: FixHint) -> Bool { switch h { case .dropSub, .deinterlace, .tonemap, .normalize: return true; default: return false } }

/// Una correzione proposta, con le segnalazioni che la richiedono raggruppate (es. 40 battute con pubblicità = una sola voce).
struct FixItem: Identifiable { let id: String; var sev: Sev; var title: String; var detail: String; var hints: [FixHint]; var count: Int; var thumb: URL? }
func fixItems(_ r: Report) -> [FixItem] {
    var out: [FixItem] = []; var idx: [String: Int] = [:]
    for f in r.findings.sorted(by: { $0.sev > $1.sev }) where !f.fixes.isEmpty && f.sev > .ok {
        let key = f.fixes.map { String(describing: $0) }.joined(separator: "|")
        if let i = idx[key] { out[i].count += 1; out[i].sev = max(out[i].sev, f.sev) }
        else { idx[key] = out.count; out.append(FixItem(id: key, sev: f.sev, title: f.title, detail: f.detail, hints: f.fixes, count: 1, thumb: f.thumb)) }
    }
    return out.sorted { $0.sev > $1.sev }
}

struct JobDetail: View {
    @ObservedObject var job: Job; let store: Store
    @State private var sheetPlan: FixPlan?; @State private var showNotes = false; @State private var showTech = false
    func plan(_ hints: [FixHint]) -> FixPlan { var p = FixPlan(); hints.forEach { p.merge($0) }; return p }
    var body: some View {
        if let r = job.report {
            let items = fixItems(r)
            let todo = r.findings.filter { $0.fixes.isEmpty && $0.sev >= .warn }.sorted { $0.sev > $1.sev }
            let notes = r.findings.filter { $0.fixes.isEmpty && $0.sev == .info }
            ScrollView { VStack(alignment: .leading, spacing: 22) {
                header(r)
                if let fr = job.fixResult { FixBanner(result: fr) { store.restore(job) } }
                if job.fixProgress != nil { HStack(spacing: 10) { ProgressView(value: job.fixProgress).frame(width: 220); Text(job.fixStage).font(.callout).foregroundStyle(.secondary) } }
                if items.isEmpty && todo.isEmpty { HStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3); Text("Tutto a posto: niente da sistemare.").font(.headline) } }
                if !items.isEmpty { fixSection(r, items) }
                if !todo.isEmpty { VStack(alignment: .leading, spacing: 8) {
                    Text("Da controllare a mano").font(.headline)
                    ForEach(todo) { f in HStack(alignment: .top, spacing: 10) { Image(systemName: f.sev.symbol).foregroundStyle(f.sev.color).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) { Text(f.title).font(.callout.weight(.medium)); if !f.detail.isEmpty { Text(f.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            if let t = f.thumb, let img = NSImage(contentsOf: t) { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 110).cornerRadius(5) } }
                        Spacer(minLength: 0); if let t = f.time { Text(hms(t)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) } } }
                } }
                if !notes.isEmpty { DisclosureGroup("Note (\(notes.count))", isExpanded: $showNotes) { VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes) { f in HStack(alignment: .top, spacing: 8) { Image(systemName: "info.circle").foregroundStyle(.secondary).frame(width: 18); VStack(alignment: .leading) { Text(f.title).font(.callout); if !f.detail.isEmpty { Text(f.detail).font(.caption).foregroundStyle(.secondary) } } } } }.padding(.top, 6) }.font(.headline) }
                DisclosureGroup("Dati tecnici", isExpanded: $showTech) { VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.tech.sorted { $0.order < $1.order }) { s in VStack(alignment: .leading, spacing: 3) { Text(s.title).font(.subheadline.weight(.semibold)).padding(.top, 4)
                        ForEach(s.rows) { row in HStack(alignment: .top) { Text(row.k).foregroundStyle(.secondary).frame(width: 190, alignment: .leading); Text(row.v).textSelection(.enabled) }.font(.callout) } } } }.padding(.top, 6) }.font(.headline)
            }.padding(24).frame(maxWidth: 760, alignment: .leading) }
            .sheet(isPresented: Binding(get: { sheetPlan != nil }, set: { if !$0 { sheetPlan = nil } })) { FixSheet(job: job, report: r, plan: sheetPlan ?? FixPlan(), store: store) }
            .onChange(of: job.fixProgress != nil) { running in if !running { sheetPlan = nil } }
            .onAppear { if ProcessInfo.processInfo.environment["MOVIEPREFLIGHT_SHEET"] != nil { var p = FixPlan(); r.findings.forEach { $0.fixes.forEach { p.merge($0) } }; sheetPlan = p } }   // solo per le prove a vista
        } else {
            VStack(spacing: 12) {
                Text(job.url.lastPathComponent).font(.headline).lineLimit(2)
                ProgressView(value: job.progress).frame(width: 320)
                Text(job.stage).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    func header(_ r: Report) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let m = r.meta, let u = m.posterURL { AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.12) }.frame(width: 96, height: 140).cornerRadius(6).shadow(radius: 2) }
            else { Image(systemName: "film").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary).frame(width: 96, height: 140).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10))) }
            VStack(alignment: .leading, spacing: 5) {
                Text(r.meta?.title ?? r.file.deletingPathExtension().lastPathComponent).font(.title2.weight(.semibold)).lineLimit(2)
                Text(subtitle(r)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) { Image(systemName: r.worst.symbol); Text(r.verdict).fontWeight(.medium) }.font(.callout).foregroundStyle(r.worst.color).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(r.worst.color.opacity(0.12)))
                if let s = r.meta?.summary { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(3).padding(.top, 2) }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Rianalizza") { store.startAnalysis(job) }
                Button("Correggi a mano…") { sheetPlan = FixPlan() }
                Divider()
                Button("Copia il rapporto") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.text, forType: .string) }
                Button("Salva il rapporto…") { save(r) }
                Divider()
                Button("Dati del film online…") { store.askOnline(force: true) }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).frame(width: 34).disabled(job.fixProgress != nil)
        }
    }
    func subtitle(_ r: Report) -> String {
        var p: [String] = []
        if let y = r.meta?.year { p.append("\(y)") }
        if let d = r.meta?.directors, !d.isEmpty { p.append(d.joined(separator: ", ")) }
        p.append(hmLabel(r.duration)); p.append(r.file.pathExtension.uppercased())
        return p.joined(separator: " · ")
    }
    func hmLabel(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }
    func fixSection(_ r: Report, _ items: [FixItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Da sistemare").font(.headline); Spacer()
                let safe = items.flatMap { $0.hints }.filter { !isHeavy($0) }
                if items.filter({ $0.hints.allSatisfy { !isHeavy($0) } }).count >= 2 { Button { store.confirmFix(job, plan(safe)) { sheetPlan = plan(safe) } } label: { Label("Correggi tutto", systemImage: "wand.and.stars") }.buttonStyle(.borderedProminent).disabled(job.fixProgress != nil) } }
            ForEach(items) { it in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: it.sev.symbol).foregroundStyle(it.sev.color).font(.system(size: 18)).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(it.title + (it.count > 1 ? " (+\(it.count - 1))" : "")).font(.callout.weight(.semibold))
                        if !it.detail.isEmpty { Text(it.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                        if let t = it.thumb, let img = NSImage(contentsOf: t) { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 100).cornerRadius(5).padding(.top, 2) }
                    }
                    Spacer(minLength: 8)
                    Button(fixLabel(it.hints[0])) { store.confirmFix(job, plan(it.hints)) { sheetPlan = plan(it.hints) } }.disabled(job.fixProgress != nil)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(it.sev.color.opacity(0.08))).overlay(RoundedRectangle(cornerRadius: 10).stroke(it.sev.color.opacity(0.25)))
            }
        }
    }
    func save(_ r: Report) {
        let p = NSSavePanel(); p.nameFieldStringValue = r.file.deletingPathExtension().lastPathComponent + " — preflight.txt"; p.allowedContentTypes = [.plainText]
        if p.runModal() == .OK, let u = p.url { try? r.text.write(to: u, atomically: true, encoding: .utf8) }
    }
}
