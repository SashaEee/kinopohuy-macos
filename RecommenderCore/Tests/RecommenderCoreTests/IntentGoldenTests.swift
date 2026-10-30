import Foundation
import Testing
@testable import RecommenderCore

/// The rules parser against 60 realistic requests (`Fixtures/IntentGolden.json`). A case passes only when every field
/// matches: an omitted field must come out empty. The bar is 54 of 60; failures are printed with what came out.
@Suite struct IntentGoldenTests {
    struct Case: Decodable {
        var text: String
        var expect: Expectation
    }

    struct RatingExpectation: Decodable, Equatable {
        var source: String
        var value: Double
    }

    /// `{"max": 95}`, `{"episode": 45}`, `"filmNight"`, `"weekendSeries"`.
    enum TimeExpectation: Decodable, Equatable {
        case max(Int)
        case episode(Int)
        case named(String)

        init(from decoder: any Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self = .named(name)
                return
            }
            let values = try decoder.container(keyedBy: Keys.self)
            if let max = try values.decodeIfPresent(Int.self, forKey: .max) {
                self = .max(max)
            } else {
                self = .episode(try values.decode(Int.self, forKey: .episode))
            }
        }

        enum Keys: String, CodingKey {
            case max
            case episode
        }

        init(_ budget: TimeBudget) {
            switch budget {
            case .maxMinutes(let minutes): self = .max(minutes)
            case .episode(let range): self = .episode(range.upperBound)
            case .filmNight: self = .named("filmNight")
            case .weekendSeries: self = .named("weekendSeries")
            }
        }
    }

    struct Expectation: Decodable {
        var kinds: [String]?
        var moods: [String]?
        var company: String?
        var time: TimeExpectation?
        var genres: [String]?
        var notGenres: [String]?
        var countries: [String]?
        var notCountries: [String]?
        var years: [Int]?
        var rating: RatingExpectation?
        var similar: [String]?
        var people: [String]?
        var avoid: [String]?
        var familiarity: Double?
        var offTopic: Bool?
    }

    static let context = EngineContext(now: 1_793_394_000, weekday: 5, hour: 21, minute: 0)

    static func loadCases() throws -> [Case] {
        let url = try #require(Bundle.module.url(forResource: "IntentGolden", withExtension: "json"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    /// What differs between the expectation and the parse, one line per field.
    static func mismatches(_ expect: Expectation, _ parsed: ParsedRequest) -> [String] {
        let intent = parsed.intent
        var problems: [String] = []
        func check<T: Equatable>(_ name: String, _ expected: T, _ actual: T) {
            if expected != actual { problems.append("\(name): ждали \(expected), получили \(actual)") }
        }
        check("kinds", Set(expect.kinds ?? []), Set((intent.kinds ?? []).map(\.rawValue)))
        check("moods", Set(expect.moods ?? []), Set(intent.moods.filter { $0.value > 0 }.map(\.key.rawValue)))
        check("company", expect.company, intent.company?.rawValue)
        check("time", expect.time, intent.time.map(TimeExpectation.init))
        check("genres", Set(expect.genres ?? []), intent.genres.include)
        check("notGenres", Set(expect.notGenres ?? []), intent.genres.exclude)
        check("countries", Set(expect.countries ?? []), intent.countries.include)
        check("notCountries", Set(expect.notCountries ?? []), intent.countries.exclude)
        check("years", expect.years, intent.years.map { [$0.lowerBound, $0.upperBound] })
        check("rating", expect.rating, intent.minRating.map { RatingExpectation(source: $0.source.rawValue, value: $0.value) })
        check("similar", expect.similar ?? [], parsed.similarQueries)
        check("people", expect.people ?? [], parsed.peopleQueries)
        check("avoid", expect.avoid ?? [], intent.avoid)
        check("familiarity", expect.familiarity, intent.familiarity)
        check("offTopic", expect.offTopic ?? false, parsed.offTopic)
        return problems
    }

    @Test func goldenSetIsMostlyRight() throws {
        let cases = try Self.loadCases()
        #expect(cases.count == 60)
        var passed = 0
        var report: [String] = []
        for item in cases {
            let parsed = RuleIntentParser.parse(item.text, context: Self.context)
            let problems = Self.mismatches(item.expect, parsed)
            if problems.isEmpty {
                passed += 1
            } else {
                report.append("«\(item.text)»\n    " + problems.joined(separator: "\n    "))
            }
        }
        print("Golden: \(passed)/\(cases.count)")
        if !report.isEmpty { print("Не совпало:\n" + report.joined(separator: "\n")) }
        #expect(passed >= 54, "Golden \(passed)/\(cases.count):\n\(report.joined(separator: "\n"))")
    }

    @Test func parsingIsFast() throws {
        let cases = try Self.loadCases()
        _ = RuleIntentParser.parse("прогрев", context: Self.context)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for item in cases { _ = RuleIntentParser.parse(item.text, context: Self.context) }
        }
        let perPhrase = elapsed / cases.count
        print("Разбор: \(perPhrase) на фразу")
        // The plan budgets ~5 ms; debug builds are slower, so allow some headroom.
        #expect(perPhrase < .milliseconds(15))
    }
}
