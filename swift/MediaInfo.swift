import Foundation

/// MediaInfo (BSD, standard nelle emittenti): dettagli che ffprobe non dà: profilo Dolby Vision/HDR10+, nome commerciale dell'audio, libreria di codifica, sigla del gruppo di rilascio.
func scanMediaInfo(_ pr: Probe, _ path: String, _ c: Collector) {
    guard let mi = tool("mediainfo") else { return }
    let o = run(mi, ["--Output=JSON", path])
    guard let d = try? JSONSerialization.jsonObject(with: o.out) as? [String: Any], let m = d["media"] as? [String: Any], let tr = m["track"] as? [[String: Any]] else { return }
    func str(_ t: [String: Any], _ k: String) -> String? { (t[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    let general = tr.first { ($0["@type"] as? String) == "General" } ?? [:]
    let video = tr.filter { ($0["@type"] as? String) == "Video" }, audio = tr.filter { ($0["@type"] as? String) == "Audio" }
    // sigla del gruppo di rilascio nel titolo, per esempio «Film [HD4ME]»
    if let t = str(general, "Title") ?? str(general, "Movie"), t.match(#"\[[A-Za-z0-9._-]{3,14}\]"#) != nil || t.match(#"[-.]\s?(YIFY|YTS|RARBG|ETRG|FGT|NTb|SPARKS|GECKOS|CMRG|EVO|HDCLUB|HD4ME|ION10|TiGOLE|QxR)\b"#, options: .caseInsensitive) != nil {
        c.add(.warn, "File", "Il titolo nei metadati contiene la sigla di un gruppo di rilascio", "«\(t)»: compare nei lettori e nelle librerie. Si può togliere dal titolo del contenitore.", fix: [.clearTitle])
    }
    if let v = video.first {
        var rows: [(String, String)] = []
        if let lib = str(v, "Encoded_Library_Name") { rows.append(("Codificato con", lib + (str(v, "Encoded_Library_Version").map { " " + $0 } ?? ""))) }
        if let s = str(v, "Encoded_Library_Settings") { rows.append(("Impostazioni di codifica", String(s.prefix(160)) + (s.count > 160 ? "…" : ""))) }
        if let h = str(v, "HDR_Format") { rows.append(("HDR (MediaInfo)", h + (str(v, "HDR_Format_Compatibility").map { " · compatibile \($0)" } ?? ""))) }
        if let br = str(v, "BitRate_Mode") { rows.append(("Modalità bitrate", br == "VBR" ? "variabile (VBR)" : br == "CBR" ? "costante (CBR)" : br)) }
        if !rows.isEmpty { c.rows("Video", order: 1, rows) }
        let hdr = str(v, "HDR_Format") ?? ""
        if hdr.contains("Dolby Vision") {
            let prof = str(v, "HDR_Format_Profile") ?? ""
            if prof.contains("05") || prof.lowercased().contains("dvhe.05") || hdr.contains("Profile 5") {
                c.add(.warn, "Video", "Dolby Vision profilo 5", "Questo profilo non ha un livello base compatibile: senza un lettore e uno schermo Dolby Vision i colori appaiono viola e verdi. Va riconvertito da un'altra sorgente.")
            } else {
                c.add(.info, "Video", "Contiene Dolby Vision (\(prof.isEmpty ? "profilo non indicato" : prof))", "Lo strato base è " + (str(v, "HDR_Format_Compatibility") ?? "HDR10") + ": su un proiettore senza Dolby Vision si vede quello.")
            }
        }
        if hdr.contains("SMPTE ST 2094") { c.add(.info, "Video", "Contiene metadati HDR10+", "Su un proiettore che non li legge si usa solo l'HDR10 di base.") }
    }
    for (i, a) in audio.enumerated() {
        var rows: [(String, String)] = []
        if let n = str(a, "Format_Commercial_IfAny") { rows.append(("Nome commerciale", n)) }
        if let comp = str(a, "Compression_Mode") { rows.append(("Compressione", comp == "Lossless" ? "senza perdita" : "con perdita")) }
        if let l = str(a, "ChannelLayout") { rows.append(("Canali (ordine)", l)) }
        if let br = str(a, "BitRate_Mode") { rows.append(("Modalità bitrate", br == "VBR" ? "variabile (VBR)" : br == "CBR" ? "costante (CBR)" : br)) }
        if !rows.isEmpty { c.rows("Audio \(i + 1)", order: 10 + i, rows) }
        if let n = str(a, "Format_Commercial_IfAny"), n.contains("DTS:X") || n.contains("Atmos") && !n.contains("Dolby Digital Plus") {
            c.add(.info, "Audio", "Audio a oggetti (\(n)) — traccia audio \(i + 1)", "Convertendolo in Dolby Digital o stereo si perdono gli oggetti: tienila com'è se l'impianto li riproduce.")
        }
    }
}
