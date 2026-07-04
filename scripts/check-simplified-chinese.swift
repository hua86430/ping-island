#!/usr/bin/env swift
// Guard scanner: fail if any user-visible Simplified Chinese survives in the app.
//
// Rules (see docs/superpowers/specs/2026-07-04-full-app-traditional-chinese-sweep-design.md):
//   - zh-Hant.lproj VALUES must be Traditional. KEYS may stay Simplified (identifiers).
//   - Swift string literals in PingIsland/ that are Simplified are violations UNLESS
//     the literal is a resolved zh-Hant key (then its Traditional value drives display,
//     and that value is validated by the .strings value scan).
//   - Simplified matcher literals that compare against incoming (Simplified) agent text
//     are allowed, but MUST be wrapped in:
//         // i18n:simplified-matcher-start
//         ...
//         // i18n:simplified-matcher-end
//     so the intent is explicit and drift-proof (no line-number whitelist).
//
// Exit non-zero if any non-whitelisted Simplified survives.

import Foundation

let repoRoot: String = {
    // Script lives in <repo>/scripts/, run from anywhere.
    let scriptPath = CommandLine.arguments[0]
    let scriptURL = URL(fileURLWithPath: scriptPath).resolvingSymlinksInPath()
    return scriptURL.deletingLastPathComponent().deletingLastPathComponent().path
}()

let appDir = repoRoot + "/PingIsland"
let zhHantStrings = appDir + "/Resources/zh-Hant.lproj/Localizable.strings"

let hansHant = StringTransform("Hans-Hant")

/// Returns the Simplified characters inside `s`. Uses a WHOLE-STRING context-aware
/// Hans->Hant transform (not char-by-char): ICU picks the right Traditional form from
/// context, so dual-valid characters like 余→餘 (in 剩余量), 里→裡, 面→麵, 系→係/繫,
/// 松→鬆, 只→隻, 台→臺 are caught. A char-by-char transform leaves those unchanged
/// because each is also a legitimate standalone Traditional character.
func simplifiedChars(_ s: String) -> [Character] {
    guard let conv = s.applyingTransform(hansHant, reverse: false), conv != s else { return [] }
    // Report the characters that the transform changed (best-effort, position-aligned).
    var hits: [Character] = []
    for (a, b) in zip(s, conv) where a != b {
        if a.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
            hits.append(a)
        }
    }
    // Length changed (rare) or no aligned diff found: still a real violation.
    if hits.isEmpty { hits.append(contentsOf: s.filter { c in
        c.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }.prefix(1)) }
    return hits
}

struct Violation {
    let kind: String   // "VALUE" or "SWIFT"
    let file: String
    let line: Int
    let literal: String
    let chars: [Character]
}

var violations: [Violation] = []

// ---- 1. Parse zh-Hant.lproj: collect KEY set, flag Simplified VALUES ----------

var zhHantKeys = Set<String>()

func rel(_ path: String) -> String {
    path.hasPrefix(repoRoot + "/") ? String(path.dropFirst(repoRoot.count + 1)) : path
}

if let content = try? String(contentsOfFile: zhHantStrings, encoding: .utf8) {
    // "key" = "value"; on a single line (this project's .strings are single-line entries).
    let entry = try! NSRegularExpression(
        pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#)
    let lines = content.components(separatedBy: "\n")
    for (idx, line) in lines.enumerated() {
        let ns = line as NSString
        guard let m = entry.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        else { continue }
        let key = ns.substring(with: m.range(at: 1))
        let value = ns.substring(with: m.range(at: 2))
        zhHantKeys.insert(key)
        let hits = simplifiedChars(value)
        if !hits.isEmpty {
            violations.append(Violation(kind: "VALUE", file: rel(zhHantStrings),
                                        line: idx + 1, literal: value, chars: hits))
        }
    }
} else {
    FileHandle.standardError.write("cannot read \(zhHantStrings)\n".data(using: .utf8)!)
    exit(2)
}

// ---- 2. Walk PingIsland/**/*.swift, flag Simplified literals not in keySet ------

/// Extract string literals from one Swift line, honoring an in-string state and
/// stopping at `//` line comments. Returns literal contents (without the quotes).
func stringLiterals(in line: String, inBlockComment: inout Bool) -> [String] {
    var out: [String] = []
    var buf = ""
    var inString = false
    var escape = false
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if inBlockComment {
            if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                inBlockComment = false
                i += 2
                continue
            }
            i += 1
            continue
        }
        if inString {
            if escape { escape = false; buf.append(c); i += 1; continue }
            if c == "\\" { escape = true; buf.append(c); i += 1; continue }
            if c == "\"" { inString = false; out.append(buf); buf = ""; i += 1; continue }
            buf.append(c); i += 1; continue
        }
        // not in string, not in block comment
        if c == "/", i + 1 < chars.count, chars[i + 1] == "/" { break }        // line comment
        if c == "/", i + 1 < chars.count, chars[i + 1] == "*" { inBlockComment = true; i += 2; continue }
        if c == "\"" { inString = true; i += 1; continue }
        i += 1
    }
    return out
}

/// Only a literal passed DIRECTLY to a localizing API resolves through the .strings
/// table (so a Simplified key -> Traditional value). Every other render path
/// (`Text(stringVar)`, `Text(verbatim:)`, interpolation, `.tag`, AppKit titles set from
/// a String) shows the literal verbatim, so a Simplified literal there is a real bug even
/// if it happens to exist as a zh-Hant key. Checking the literal's line plus the previous
/// non-blank line covers multi-line calls like `Text(appLocalized:\n  "…")`.
func lineIsLocalizingCall(_ s: String) -> Bool {
    s.contains("appLocalized") || s.contains("AppLocalization.string") || s.contains("AppLocalization.format")
}

func scanSwift(_ path: String) {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    let lines = content.components(separatedBy: "\n")
    var inBlockComment = false
    var inWhitelist = false
    var prevNonBlank = ""
    for (idx, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("i18n:simplified-matcher-start") { inWhitelist = true }
        if trimmed.contains("i18n:simplified-matcher-end") { inWhitelist = false }
        let literals = stringLiterals(in: line, inBlockComment: &inBlockComment)
        let localizedArg = lineIsLocalizingCall(line) || lineIsLocalizingCall(prevNonBlank)
        if !trimmed.isEmpty { prevNonBlank = line }
        if inWhitelist { continue }
        for lit in literals {
            let hits = simplifiedChars(lit)
            guard !hits.isEmpty else { continue }
            // A Simplified literal is safe only if it resolves through the .strings table:
            // either it is an inline argument to a localizing call, or it is a zh-Hant KEY
            // whose (Traditional) value drives display. NOTE: this cannot detect a zh-Hant
            // key rendered through a NON-localizing path (`Text(stringVar)`, verbatim,
            // interpolation) — that class must be fixed at the render site and is audited
            // separately, not by this scanner.
            if localizedArg || zhHantKeys.contains(lit) { continue }
            violations.append(Violation(kind: "SWIFT", file: rel(path),
                                        line: idx + 1, literal: lit, chars: hits))
        }
    }
}

let fm = FileManager.default
if let en = fm.enumerator(atPath: appDir) {
    for case let sub as String in en where sub.hasSuffix(".swift") {
        scanSwift(appDir + "/" + sub)
    }
}

// ---- 3. Report ------------------------------------------------------------------

if violations.isEmpty {
    print("check-simplified-chinese: OK — no user-visible Simplified Chinese found.")
    exit(0)
}

let valueHits = violations.filter { $0.kind == "VALUE" }
let swiftHits = violations.filter { $0.kind == "SWIFT" }
for v in violations.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
    let chars = String(v.chars).map(String.init).joined(separator: ",")
    print("\(v.kind)  \(v.file):\(v.line)  [\(chars)]  «\(v.literal)»")
}
print("---")
print("check-simplified-chinese: \(violations.count) violation(s) — \(valueHits.count) .strings value, \(swiftHits.count) swift literal.")
exit(1)
