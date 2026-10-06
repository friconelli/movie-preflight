import SwiftUI

private let commonLangs: [(String, String)] = [("ita", "italiano"), ("eng", "inglese"), ("fre", "francese"), ("spa", "spagnolo"), ("ger", "tedesco"), ("por", "portoghese"), ("rus", "russo"), ("jpn", "giapponese"), ("chi", "cinese"), ("kor", "coreano"), ("dut", "olandese"), ("pol", "polacco")]

/// Finestra di conferma: mostra tutto quello che verrà fatto al file e lo applica solo dopo il consenso.
struct FixSheet: View {
    @ObservedObject var job: Job; let report: Report; @State var plan: FixPlan; let store: Store; @Environment(\.dismiss) private var dismiss
    @State private var trimS = false
    @State private var trimE = false
    @State private var sText = ""
    @State private var eText = ""
    var url: URL { job.url }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Correggi il film").font(.title3.weight(.semibold)).padding([.horizontal, .top], 20)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 20).padding(.bottom, 8)
            if let p = job.fixProgress { running(p) } else { form }
        }.frame(width: 640, height: 640)
    }
    func running(_ p: Double) -> some View {
        VStack(spacing: 12) { Spacer(); ProgressView(value: p).frame(width: 360); Text(job.fixStage).foregroundStyle(.secondary); Text("Non chiudere l'app: il file originale non viene toccato finché la verifica non è finita.").font(.caption).foregroundStyle(.tertiary); Spacer() }.frame(maxWidth: .infinity)
    }
    var form: some View {
        VStack(spacing: 0) {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                if !report.audioTracks.isEmpty { group("Audio") {
                    HStack { Text("Traccia predefinita").frame(width: 150, alignment: .leading)
                        Picker("", selection: Binding(get: { plan.audioDefault ?? -1 }, set: { plan.audioDefault = $0 < 0 ? nil : $0 })) { Text("Invariata").tag(-1); ForEach(report.audioTracks) { Text(label($0)).tag($0.ord) } }.labelsHidden() }
                    ForEach(report.audioTracks) { t in trackRow(t, kind: "a") {
                        Toggle("Livella la dinamica (musica più bassa rispetto ai dialoghi)", isOn: Binding(get: { plan.normalize.contains(t.ord) }, set: { if $0 { plan.normalize.insert(t.ord) } else { plan.normalize.remove(t.ord) } })).disabled(plan.dropAudio.contains(t.ord) || t.channels > 6)
                        Toggle("Elimina questa traccia", isOn: Binding(get: { plan.dropAudio.contains(t.ord) }, set: { if $0 { plan.dropAudio.insert(t.ord); plan.normalize.remove(t.ord) } else { plan.dropAudio.remove(t.ord) } })).disabled(report.audioTracks.count < 2)
                    } } } }
                if !report.subTracks.isEmpty { group("Sottotitoli") {
                    HStack { Text("Predefiniti").frame(width: 150, alignment: .leading)
                        Picker("", selection: Binding(get: { switch plan.subDefault { case .keep: return -2; case .none: return -1; case .track(let k): return k } }, set: { plan.subDefault = $0 == -2 ? .keep : $0 == -1 ? .none : .track($0) })) {
                            Text("Invariati").tag(-2); Text("Nessuno (partono spenti)").tag(-1); ForEach(report.subTracks) { Text(label($0)).tag($0.ord) } }.labelsHidden() }
                    ForEach(report.subTracks) { t in trackRow(t, kind: "s") {
                        Toggle("Togli le battute con pubblicità e crediti", isOn: Binding(get: { plan.cleanSubs.contains(t.ord) }, set: { if $0 { plan.cleanSubs.insert(t.ord) } else { plan.cleanSubs.remove(t.ord) } })).disabled(t.image || plan.dropSubs.contains(t.ord))
                        Toggle("Elimina questa traccia", isOn: Binding(get: { plan.dropSubs.contains(t.ord) }, set: { if $0 { plan.dropSubs.insert(t.ord); plan.cleanSubs.remove(t.ord) } else { plan.dropSubs.remove(t.ord) } }))
                    } } } }
                group("Taglio (senza ricodificare l'immagine)") {
                    HStack { Toggle("Togli l'inizio fino a", isOn: $trimS); TextField("secondi", text: $sText).frame(width: 80).textFieldStyle(.roundedBorder).disabled(!trimS); Text("s") }
                    HStack { Toggle("Togli la fine a partire da", isOn: $trimE); TextField("secondi", text: $eText).frame(width: 80).textFieldStyle(.roundedBorder).disabled(!trimE); Text("s (il film dura \(Int(report.duration)) s)") }
                    Text("Il taglio cade sul fotogramma chiave più vicino verso l'interno, quindi può togliere qualche secondo in più.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                let p = effective
                if p.isEmpty { Text("Scegli qualcosa da correggere.").foregroundStyle(.secondary) }
                else {
                    Text(p.changesContent ? "L'originale verrà conservato come «\(backupURL(for: url).lastPathComponent)» nella stessa cartella." : (url.pathExtension.lowercased() == "mkv" ? "Si modificano solo le etichette, direttamente nel file: il film non viene riscritto." : "Si modificano solo le etichette: il file viene riscritto senza ricodifica e la versione precedente va nel Cestino.")).font(.callout)
                    if p.changesContent { Text("Dopo la scrittura il nuovo file viene controllato (tracce, durata, buchi nell'audio); se qualcosa non torna l'originale non viene toccato.").font(.caption).foregroundStyle(.secondary) }
                }
                HStack { Spacer(); Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Applica") { let p = effective; store.fix(job, p); } .keyboardShortcut(.defaultAction).disabled(p.isEmpty) }
            }.padding(16)
        }
    }
    var effective: FixPlan {
        var p = plan
        p.trimStart = trimS ? Double(sText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } : nil
        p.trimEnd = trimE ? Double(eText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 60 ? $0 : nil } : nil
        return p
    }
    func label(_ t: TrackInfo) -> String { "\(t.ord + 1) · \(langLabel(t.lang))\(t.forced ? " (forzati)" : "") · \(t.codec.uppercased())\(t.channels > 0 ? " \(t.channels)ch" : "")" + (t.title.isEmpty ? "" : " · \(t.title)") }
    func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); c() }
    }
    func trackRow<C: View>(_ t: TrackInfo, kind: String, @ViewBuilder _ extra: () -> C) -> some View {
        let key = "\(kind)\(t.ord)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label(t)).font(.callout.weight(.medium)).lineLimit(1); Spacer()
                Text("Lingua").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { plan.lang[key] ?? "" }, set: { plan.lang[key] = $0.isEmpty ? nil : $0 })) {
                    Text(t.lang.isEmpty ? "Non indicata" : "Invariata (\(langLabel(t.lang)))").tag(""); ForEach(commonLangs, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(width: 190) }
            extra()
        }.padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}
