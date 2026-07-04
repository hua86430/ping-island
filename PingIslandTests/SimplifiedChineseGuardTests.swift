import XCTest

/// Regression guard for the full-app Traditional Chinese sweep
/// (docs/superpowers/specs/2026-07-04-full-app-traditional-chinese-sweep-design.md).
///
/// The KEY convention is deliberate: localization KEYS stay Simplified (they are
/// lookup identifiers, asserted by `SettingsWindowControllerTests`). VALUES must be
/// Traditional. This test enforces the VALUE side; `scripts/check-simplified-chinese.swift`
/// covers Swift source literals and is the fuller guard.
final class SimplifiedChineseGuardTests: XCTestCase {

    /// Whole-string context-aware Hans->Hant transform (mirrors the scanner script).
    /// A char-by-char transform would miss dual-valid characters (余→餘 in 剩余量,
    /// 志→誌 in 日志, 里→裡, 面→麵), which are legitimate standalone Traditional chars;
    /// transforming the whole value lets ICU pick the right form from context.
    private func simplifiedCharacters(in text: String) -> [Character] {
        let transform = StringTransform("Hans-Hant")
        guard let converted = text.applyingTransform(transform, reverse: false),
              converted != text else { return [] }
        var hits: [Character] = []
        for (a, b) in zip(text, converted) where a != b {
            if a.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
                hits.append(a)
            }
        }
        if hits.isEmpty {
            hits.append(contentsOf: text.filter { c in
                c.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
            }.prefix(1))
        }
        return hits
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testZhHantLocalizationValuesContainNoSimplifiedChinese() throws {
        let stringsURL = repoRoot()
            .appendingPathComponent("PingIsland/Resources/zh-Hant.lproj/Localizable.strings")
        let contents = try String(contentsOf: stringsURL, encoding: .utf8)

        // "key" = "value"; — check the VALUE only (keys are intentionally Simplified).
        let pattern = #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let ns = contents as NSString

        var offenders: [String] = []
        regex.enumerateMatches(in: contents, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let value = ns.substring(with: match.range(at: 2))
            let hits = self.simplifiedCharacters(in: value)
            if !hits.isEmpty {
                offenders.append("«\(value)» contains \(hits.map(String.init).joined(separator: ","))")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "zh-Hant values must be Traditional. Simplified survivors:\n" + offenders.joined(separator: "\n")
        )
    }

    func testGuardScannerScriptExists() {
        let scriptURL = repoRoot().appendingPathComponent("scripts/check-simplified-chinese.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "scripts/check-simplified-chinese.swift missing — the Swift-source Simplified guard must stay in the repo."
        )
    }
}
