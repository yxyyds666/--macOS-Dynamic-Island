import Foundation

/// One time-synced lyric line: the text and the playback time (seconds) at which
/// it becomes the active line.
struct LyricLine: Equatable, Identifiable, Sendable {
    let id = UUID()
    let time: TimeInterval
    let text: String

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time == rhs.time && lhs.text == rhs.text
    }
}

/// Parses an LRC-format lyrics blob (lines like `[01:23.45] some words`) into
/// time-sorted `LyricLine`s. A single line may carry multiple timestamps; each
/// produces its own entry. Blank lines and metadata-only tags are skipped.
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        // [mm:ss.xx] or [mm:ss] timestamp tags.
        let tagPattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return [] }

        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            // Text is whatever follows the final timestamp tag.
            let lastTagEnd = matches.map { $0.range.location + $0.range.length }.max() ?? 0
            let text = ns.substring(from: lastTagEnd).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                let fracRange = m.range(at: 3)
                if fracRange.location != NSNotFound {
                    let fs = ns.substring(with: fracRange)
                    frac = (Double(fs) ?? 0) / pow(10, Double(fs.count))
                }
                lines.append(LyricLine(time: mm * 60 + ss + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
