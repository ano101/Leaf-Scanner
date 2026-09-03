import Foundation
import Testing
@testable import Leaf

/// Проверки, которые нельзя сделать глазами: ключей около сотни, и одна
/// опечатка показывает человеку сам ключ вместо текста.
@Suite("Локализация")
struct LocalizationTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")

    private static let catalogURL = sourceRoot
        .appendingPathComponent("Resources/Localizable.xcstrings")

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            let localizations: [String: Localization]
        }
        struct Localization: Decodable {
            let stringUnit: Unit?
            let variations: Variations?
        }
        struct Variations: Decodable {
            let plural: [String: Localization]?
        }
        struct Unit: Decodable {
            let value: String
        }

        let strings: [String: Entry]
    }

    private func loadCatalog() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: try Data(contentsOf: Self.catalogURL))
    }

    /// Ключ с подстановкой записывается в коде как `"export.ready \(вес)"`,
    /// а в каталоге лежит как `export.ready %@`. Для сверки подстановка
    /// отбрасывается, и остаётся сам ключ.
    private func keyPart(of literal: String) -> String {
        guard let range = literal.range(of: "\\(") else { return literal }
        return String(literal[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private func swiftSources() throws -> [(path: String, text: String)] {
        let enumerator = FileManager.default.enumerator(
            at: Self.sourceRoot,
            includingPropertiesForKeys: nil
        )
        var found: [(String, String)] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }

        return found
    }

    @Test("каждый ключ переведён на русский и английский")
    func everyKeyIsTranslatedIntoBothLanguages() throws {
        let catalog = try loadCatalog()

        #expect(catalog.strings.isEmpty == false)

        for (key, entry) in catalog.strings {
            for language in ["ru", "en"] {
                guard let localization = entry.localizations[language] else {
                    Issue.record("ключ \(key) не переведён на \(language)")
                    continue
                }

                let hasPlain = localization.stringUnit?.value.isEmpty == false
                let hasPlural = localization.variations?.plural?.values
                    .allSatisfy { $0.stringUnit?.value.isEmpty == false } == true
                #expect(hasPlain || hasPlural, "ключ \(key) на \(language) пуст")
            }
        }
    }

    @Test("в коде нет строк интерфейса — только ключи")
    func noInterfaceStringsInCode() throws {
        // Ключ отличается от текста тем, что состоит из латинских слов через
        // точку. Настоящая надпись такой формы иметь не может.
        let strictPattern = try Regex(#"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+( %(@|lld))?$"#)
        // Ключ, который дособирается подстановкой, оканчивается на точку:
        // «filter.» плюс значение перечисления.
        let namespacePattern = try Regex(#"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)*\.?$"#)
        let callPattern = try Regex(#"(?:Text|Label|LocalizedStringKey)\(\s*"([^"]+)""#)

        for (path, text) in try swiftSources() {
            for match in text.matches(of: callPattern) {
                let literal = String(match.output[1].substring ?? "")

                // Строка, помеченная verbatim, — это данные, а не надпись.
                guard text.contains("Text(verbatim: \"\(literal)\"") == false else { continue }

                let interpolated = literal.contains("\\(")
                let candidate = keyPart(of: literal)
                let matches = interpolated
                    ? candidate.contains(namespacePattern)
                    : candidate.contains(strictPattern)

                #expect(
                    matches,
                    "в \(path) надпись «\(literal)» записана текстом, а не ключом"
                )
            }
        }
    }

    @Test("каждый ключ из кода есть в каталоге")
    func everyKeyUsedInCodeExistsInCatalog() throws {
        let catalog = try loadCatalog()
        let known = Set(catalog.strings.keys)
        let callPattern = try Regex(#"(?:Text|Label|LocalizedStringKey)\(\s*"([^"]+)""#)
        let keyPattern = try Regex(#"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$"#)

        for (path, text) in try swiftSources() {
            for match in text.matches(of: callPattern) {
                let key = keyPart(of: String(match.output[1].substring ?? "")) 
                guard key.contains(keyPattern) || key.hasSuffix(".") else { continue }

                // Ключ с подстановкой лежит в каталоге вместе с ней,
                // а ключ-основа — вместе со своими значениями.
                let exists = known.contains(key)
                    || known.contains { $0.hasPrefix(key + " %") }
                    || (key.hasSuffix(".") && known.contains { $0.hasPrefix(key) })
                #expect(exists, "в \(path) ключа \(key) нет в каталоге")
            }
        }
    }

    @Test("ключи справочников и цветовых режимов описаны в каталоге")
    func referenceKeysAreDescribedInCatalog() throws {
        let known = Set(try loadCatalog().strings.keys)

        for preset in ExportPreset.all {
            #expect(known.contains(preset.titleKey), "нет перевода пресета \(preset.id)")
        }
        for mode in ColorMode.allCases {
            #expect(known.contains(mode.titleKey), "нет перевода режима \(mode.rawValue)")
        }
        for kind in SensitiveKind.allCases {
            #expect(known.contains(kind.titleKey), "нет перевода вида данных \(kind.rawValue)")
        }
        for filter in PageFilter.allCases {
            #expect(known.contains("filter.\(filter.rawValue)"), "нет перевода вида \(filter.rawValue)")
        }
    }
}
