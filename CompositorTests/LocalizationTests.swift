import Foundation
import Testing

/// Guards the Simplified Chinese localization.
///
/// A translation that drops, adds or retypes a format specifier crashes `String(format:)` at runtime, and one that is
/// missing entirely silently falls back to English. Both are invisible until someone runs the app in Chinese, so the
/// strings Xcode compiled from `Localizable.xcstrings` are checked here.
///
/// These tests read the compiled bundle rather than the catalog: the catalog is compiled into
/// `zh-Hans.lproj/Localizable.strings` and never copied, and a checkout path isn't reachable once the tests are
/// hosted by an installed app. English is the project's development language, so it ships as the source strings and
/// has no table of its own — which is what makes a Chinese table worth guarding.
struct LocalizationTests {
    /// The tests are hosted by the app, so this is the bundle holding the compiled localization.
    private static var appBundle: Bundle { Bundle.main }

    /// One compiled locale table, read the way the app looks it up at runtime.
    private static func compiledTable(_ language: String) -> [String: String] {
        guard let bundle = Bundle(path: appBundle.bundlePath + "/Contents/Resources/\(language).lproj"),
              let path = bundle.path(forResource: "Localizable", ofType: "strings"),
              let table = NSDictionary(contentsOfFile: path) as? [String: String]
        else { return [:] }
        return table
    }

    /// The format specifiers of `text`, as conversion kinds in order, so that a positional `%1$lld` compares equal
    /// to a plain `%lld` while `%lld` and `%@` still differ.
    private static func specifiers(of text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?([@dilsfuxX]|lld|ld|lu|llu|%)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let kind = Range(match.range(at: 2), in: text).map({ String(text[$0]) }) else { return nil }
            return kind == "%" ? nil : kind
        }
    }

    /// Names that stay as they are in every language: the app's own name, and the industry abbreviations the app's
    /// documentation already treats as fixed. A dithering pattern keeps `Bayer` and `ASCII`, and a channel picker
    /// keeps `RGB` and `HSL`.
    private static let untranslated = ["Compositor", "ASCII", "HSL", "RGB", "Bayer", "Floyd–Steinberg"]

    /// A key with actual words in it: symbols and format-only strings ("%lld × %lld px") carry nothing to translate.
    private static func hasWords(_ key: String) -> Bool {
        key.filter(\.isLetter).count >= 2 && !untranslated.contains(where: key.contains)
    }

    /// The app carries a Simplified Chinese table, so the rest of these tests are checking something real.
    @Test func theAppCarriesSimplifiedChinese() {
        #expect(!Self.compiledTable("zh-Hans").isEmpty, "the app should ship a zh-Hans localization")
    }

    /// Every translated string keeps its source's format specifiers, in the same order.
    @Test func simplifiedChineseKeepsFormatSpecifiers() throws {
        let table = Self.compiledTable("zh-Hans")
        try #require(!table.isEmpty)
        for (key, value) in table {
            #expect(Self.specifiers(of: value) == Self.specifiers(of: key),
                    "zh-Hans for \(key.debugDescription) is \(value.debugDescription)")
        }
    }

    /// Translated strings contain Chinese and are never left as the English source.
    @Test func simplifiedChineseIsTranslated() throws {
        let table = Self.compiledTable("zh-Hans")
        try #require(!table.isEmpty)
        for (key, value) in table where Self.hasWords(key) {
            #expect(value.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }),
                    "zh-Hans for \(key.debugDescription) has no Chinese in \(value.debugDescription)")
            #expect(value != key, "zh-Hans for \(key.debugDescription) is left as the English source")
        }
    }
}
