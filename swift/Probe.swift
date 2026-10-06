import Foundation

/// Risultato di ffprobe, con qualche accesso comodo.
struct Probe {
    var fmt: [String: Any]; var streams: [[String: Any]]; var chapters: [[String: Any]]
    init?(_ path: String) {
        guard let fp = tool("ffprobe") else { return nil }
        let o = run(fp, ["-v", "error", "-show_format", "-show_streams", "-show_chapters", "-of", "json", path])
        guard let d = try? JSONSerialization.jsonObject(with: o.out) as? [String: Any], let f = d["format"] as? [String: Any] else { return nil }
        fmt = f; streams = d["streams"] as? [[String: Any]] ?? []; chapters = d["chapters"] as? [[String: Any]] ?? []
    }
    var duration: Double { dbl(fmt["duration"]) ?? 0 }
    var size: Double { dbl(fmt["size"]) ?? 0 }
    func of(_ type: String) -> [[String: Any]] { streams.filter { $0["codec_type"] as? String == type && disp($0, "attached_pic") == 0 } }
    var video: [String: Any]? { of("video").first }
    var audio: [[String: Any]] { of("audio") }
    var subs: [[String: Any]] { of("subtitle") }
}
func tags(_ s: [String: Any]) -> [String: String] {
    var r: [String: String] = [:]; for (k, v) in (s["tags"] as? [String: Any] ?? [:]) { r[k.lowercased()] = "\(v)" }; return r
}
func disp(_ s: [String: Any], _ k: String) -> Int { ((s["disposition"] as? [String: Any])?[k] as? Int) ?? 0 }
func lang(_ s: [String: Any]) -> String { let l = tags(s)["language"] ?? ""; return l == "und" ? "" : l }

let langNames: [String: (name: String, nl: String)] = [
    "ita": ("italiano", "it"), "eng": ("inglese", "en"), "fre": ("francese", "fr"), "fra": ("francese", "fr"), "spa": ("spagnolo", "es"), "ger": ("tedesco", "de"), "deu": ("tedesco", "de"),
    "por": ("portoghese", "pt"), "rus": ("russo", "ru"), "jpn": ("giapponese", "ja"), "chi": ("cinese", "zh"), "zho": ("cinese", "zh"), "dut": ("olandese", "nl"), "nld": ("olandese", "nl"),
    "swe": ("svedese", "sv"), "dan": ("danese", "da"), "nor": ("norvegese", "nb"), "pol": ("polacco", "pl"), "tur": ("turco", "tr"), "ara": ("arabo", "ar"), "kor": ("coreano", "ko"),
    "gre": ("greco", "el"), "ell": ("greco", "el"), "cze": ("ceco", "cs"), "ces": ("ceco", "cs"), "hun": ("ungherese", "hu"), "rum": ("rumeno", "ro"), "ron": ("rumeno", "ro"), "heb": ("ebraico", "he"), "hin": ("hindi", "hi")]
func langLabel(_ code: String) -> String { code.isEmpty ? "non indicata" : (langNames[code]?.name ?? code) }
