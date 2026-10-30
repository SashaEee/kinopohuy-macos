import Foundation

/// Text normalisation shared by the parser, the lexicon and the picker's genre/country matching: lowercase, «ё» → «е»,
/// so «Лёгкое», «легкое» and «ЛЁГКОЕ» are one word.
enum IntentText {
    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// The words of a normalised name («Корея Южная» → ["корея", "южная"]), for stem matching.
    static func words(_ text: String) -> [String] {
        normalize(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// A rough Russian stem («войну» → «войн», «насилия» → «насил», «зомби» → «зомб»): enough to find a theme the user
    /// wants to avoid in genres and names without a morphology dictionary.
    static func stem(_ word: String) -> String {
        let word = normalize(word)
        guard word.count > 4 else { return word.count > 3 ? String(word.dropLast()) : word }
        for ending in stemEndings where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            return String(word.dropLast(ending.count))
        }
        return word
    }

    private static let stemEndings = [
        "иями", "ями", "ами", "ого", "его", "ому", "ему", "ыми", "ими", "иях", "ах", "ях", "ов", "ев", "ей", "ий",
        "ый", "ой", "ая", "яя", "ое", "ее", "ые", "ие", "ую", "юю", "ом", "ем", "ам", "ям", "ия", "а", "я", "ы", "и",
        "у", "ю", "е", "о", "ь", "й",
    ]
}

/// One word of a request, with what the parser needs to know about where it stands.
struct IntentToken: Sendable, Hashable {
    /// As typed («Ди», «Каприо»).
    var raw: String
    /// Lowercased, «ё» → «е».
    var norm: String
    /// For «7», «7,5», «90-х», «8+».
    var number: Double?
    /// What follows a number after a hyphen or directly («х» in «90-х», «е» in «90-е»).
    var numberSuffix: String?
    /// «7+».
    var plus: Bool = false
    /// «80 %».
    var percent: Bool = false
    /// The quoted span the word is in («Мост» in «как «Мост»»), numbered from 0.
    var quote: Int?
    /// Clauses are split by punctuation (, . ; : ! ? —), so «без ужасов, комедию» doesn't negate the comedy.
    var clause: Int
    /// The first word of a sentence: capitalised by grammar, not because it's a name.
    var sentenceStart: Bool
    /// Where the word starts in the original text (for the leftover text).
    var offset: Int

    var isNumber: Bool { number != nil }

    /// Starts with an uppercase letter (a name or a title, unless it begins a sentence).
    var isCapitalized: Bool {
        guard let first = raw.first else { return false }
        return first.isUppercase
    }

    /// «КП», «США», «HBO»: all caps and short, an abbreviation rather than a name.
    var isAbbreviation: Bool {
        raw.count <= 4 && raw.count >= 2 && raw.allSatisfy { $0.isUppercase || !$0.isLetter }
    }
}

/// Splits a request into tokens: words (with inner hyphens: «что-то», «мини-сериал»), numbers («7,5», «90-х», «8+»),
/// quoted spans and clause boundaries.
enum IntentTokenizer {
    static func tokenize(_ text: String) -> [IntentToken] {
        var tokens: [IntentToken] = []
        let chars = Array(text)
        var index = 0
        var clause = 0
        var sentenceStart = true
        var quoteDepth = 0
        var quoteIndex = -1
        var straightQuoteOpen = false

        func isWordChar(_ c: Character) -> Bool { c.isLetter || c == "'" || c == "’" }

        while index < chars.count {
            let c = chars[index]
            if c.isLetter {
                let start = index
                var end = index
                // Letters with inner hyphens or apostrophes («что-то», «sci-fi», «Ocean's»).
                while end < chars.count {
                    if isWordChar(chars[end]) || chars[end].isNumber {
                        end += 1
                    } else if (chars[end] == "-" || chars[end] == "‑") && end + 1 < chars.count && chars[end + 1].isLetter {
                        end += 1
                    } else {
                        break
                    }
                }
                let raw = String(chars[start..<end])
                tokens.append(IntentToken(
                    raw: raw, norm: IntentText.normalize(raw), clause: clause, sentenceStart: sentenceStart,
                    offset: start,
                ).withQuote(quoteDepth > 0 || straightQuoteOpen ? quoteIndex : nil))
                sentenceStart = false
                index = end
            } else if c.isNumber {
                let start = index
                var end = index
                var digits = ""
                while end < chars.count, chars[end].isNumber {
                    digits.append(chars[end])
                    end += 1
                }
                // A decimal part: «7,5», «1.5» (not «7, 8» — the comma must touch a digit on both sides).
                if end + 1 < chars.count, chars[end] == "," || chars[end] == ".", chars[end + 1].isNumber {
                    digits.append(".")
                    end += 1
                    while end < chars.count, chars[end].isNumber {
                        digits.append(chars[end])
                        end += 1
                    }
                }
                var suffix: String?
                // «90-х», «90-е», «2000-х», «90х».
                var suffixStart = end
                if suffixStart < chars.count, chars[suffixStart] == "-" || chars[suffixStart] == "‑" {
                    suffixStart += 1
                }
                if suffixStart < chars.count, chars[suffixStart].isLetter {
                    var suffixEnd = suffixStart
                    while suffixEnd < chars.count, chars[suffixEnd].isLetter { suffixEnd += 1 }
                    let letters = IntentText.normalize(String(chars[suffixStart..<suffixEnd]))
                    if ["х", "е", "ых", "ые", "x", "s", "ый", "й", "ти", "го"].contains(letters) {
                        suffix = letters
                        end = suffixEnd
                    }
                }
                var plus = false
                var percent = false
                var probe = end
                while probe < chars.count, chars[probe] == " " { probe += 1 }
                if probe < chars.count, chars[probe] == "+" {
                    plus = true
                    end = probe + 1
                } else if probe < chars.count, chars[probe] == "%" {
                    percent = true
                    end = probe + 1
                }
                let raw = String(chars[start..<end])
                var token = IntentToken(
                    raw: raw, norm: IntentText.normalize(raw), number: Double(digits), numberSuffix: suffix,
                    clause: clause, sentenceStart: sentenceStart, offset: start,
                )
                token.plus = plus
                token.percent = percent
                tokens.append(token.withQuote(quoteDepth > 0 || straightQuoteOpen ? quoteIndex : nil))
                sentenceStart = false
                index = end
            } else {
                switch c {
                case "«", "“", "„":
                    quoteDepth += 1
                    if quoteDepth == 1 { quoteIndex += 1 }
                case "»", "”":
                    quoteDepth = max(0, quoteDepth - 1)
                case "\"":
                    straightQuoteOpen.toggle()
                    if straightQuoteOpen { quoteIndex += 1 }
                case ".", "!", "?", "…":
                    clause += 1
                    sentenceStart = true
                case "—", "–":
                    // «2015–2020», «20–30 минут» is a range, not a pause.
                    let digitsAround = index > 0 && chars[index - 1].isNumber && index + 1 < chars.count
                        && chars[index + 1].isNumber
                    if !digitsAround { clause += 1 }
                case ",", ";", ":", "(", ")":
                    clause += 1
                case "-":
                    // A lone dash between spaces separates like a comma («комедию - без пошлости»).
                    if index > 0, chars[index - 1] == " " { clause += 1 }
                default:
                    break
                }
                index += 1
            }
        }
        return tokens
    }
}

private extension IntentToken {
    func withQuote(_ quote: Int?) -> IntentToken {
        var copy = self
        copy.quote = quote
        return copy
    }
}
