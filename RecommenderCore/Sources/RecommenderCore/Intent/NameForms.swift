import Foundation

/// Puts a name typed after a preposition back into the form the site lists it by: «с Томом Харди» → «Том Харди»,
/// «фильмы Нолана» → «Нолан», «Андрея Тарковского» → «Андрей Тарковский». A heuristic for the common endings, not a
/// morphology engine: foreign indeclinable names («Ди Каприо», «Скарлетт Йоханссон») pass unchanged.
enum NameForms {
    enum Case {
        /// «с Томом Харди».
        case instrumental
        /// «фильмы Нолана», «от Финчера».
        case genitive
        /// «режиссёр Финчер».
        case nominative
    }

    static func nominative(_ name: String, from grammaticalCase: Case) -> String {
        guard grammaticalCase != .nominative else { return name }
        return name
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word in restore(String(word), grammaticalCase) }
            .joined(separator: " ")
    }

    /// Variants worth searching for a typed title or name: as typed, and with common case endings undone
    /// («Интерстеллара» → «Интерстеллар», «Игру престолов» → «Игра престолов»).
    static func searchVariants(_ query: String) -> [String] {
        var variants = [query]
        let words = query.split(separator: " ").map(String.init)
        guard let first = words.first else { return variants }
        let restoredFirst = [restore(first, .genitive), restoreAccusative(first)]
        for candidate in restoredFirst where candidate != first {
            let variant = ([candidate] + words.dropFirst()).joined(separator: " ")
            if !variants.contains(variant) { variants.append(variant) }
        }
        return variants
    }

    private static func restore(_ word: String, _ grammaticalCase: Case) -> String {
        // Short words, abbreviations and particles («Ди», «фон») stay; only Cyrillic names decline here.
        guard word.count >= 4, word.first?.isUppercase == true, word.unicodeScalars.contains(where: isCyrillic) else {
            return word
        }
        let lower = IntentText.normalize(word)
        func replace(_ suffix: String, with replacement: String) -> String {
            String(word.dropLast(suffix.count)) + replacement
        }
        switch grammaticalCase {
        case .instrumental:
            if lower.hasSuffix("ским") || lower.hasSuffix("цким") { return replace("им", with: "ий") }
            if lower.hasSuffix("ской") || lower.hasSuffix("цкой") { return replace("ой", with: "ая") }
            if lower.hasSuffix("ием") { return replace("ем", with: "й") }
            if lower.hasSuffix("ей"), let before = lower.dropLast(2).last {
                return "жшчщ".contains(before) ? replace("ей", with: "а") : replace("ей", with: "я")
            }
            if lower.hasSuffix("ем"), let before = lower.dropLast(2).last {
                return "аеиоуыэюя".contains(before) ? replace("ем", with: "й") : replace("ем", with: "ь")
            }
            if lower.hasSuffix("ым") || lower.hasSuffix("ом") { return String(word.dropLast(2)) }
            if lower.hasSuffix("ой") || lower.hasSuffix("ою") { return replace("ой", with: "а") }
            return word
        case .genitive:
            if lower.hasSuffix("ского") || lower.hasSuffix("цкого") { return replace("ого", with: "ий") }
            if lower.hasSuffix("ея") || lower.hasSuffix("ия") { return replace("я", with: "й") }
            if lower.hasSuffix("ии") { return replace("и", with: "я") }
            if lower.hasSuffix("ы") { return replace("ы", with: "а") }
            if lower.hasSuffix("я"), let before = lower.dropLast().last, !"аеиоуыэюя".contains(before) {
                return replace("я", with: "ь")
            }
            if lower.hasSuffix("а"), let before = lower.dropLast().last, !"аеиоуыэюя".contains(before) {
                return String(word.dropLast())
            }
            return word
        case .nominative:
            return word
        }
    }

    /// «Игру» → «Игра», «Матрицу» → «Матрица» (titles after «на»: «похоже на Игру престолов»).
    private static func restoreAccusative(_ word: String) -> String {
        let lower = IntentText.normalize(word)
        guard word.count >= 4 else { return word }
        if lower.hasSuffix("у"), let before = lower.dropLast().last, !"аеиоуыэюя".contains(before) {
            return String(word.dropLast()) + "а"
        }
        if lower.hasSuffix("ю"), let before = lower.dropLast().last, !"аеиоуыэюя".contains(before) {
            return String(word.dropLast()) + "я"
        }
        return word
    }

    private static func isCyrillic(_ scalar: Unicode.Scalar) -> Bool { (0x0400...0x04FF).contains(scalar.value) }
}
