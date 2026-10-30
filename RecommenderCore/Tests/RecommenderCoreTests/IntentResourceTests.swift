import Foundation
import Testing
@testable import RecommenderCore

/// `lexicon_ru.json` and `mood_map.json` are the TV's copies of the compiled-in vocabulary; they must stay identical.
/// To regenerate them after editing `LexiconBuiltIn.swift` or `MoodMap.builtIn`:
/// `INTENT_RESOURCES_OUT=$PWD/Sources/RecommenderCore/Resources swift test --filter IntentResourceTests`.
@Suite struct IntentResourceTests {
    @Test func lexiconResourceMatchesBuiltIn() throws {
        let bundled = try #require(Lexicon.loadBundled(), "lexicon_ru.json is missing or doesn't decode")
        #expect(bundled == Lexicon.builtIn, "lexicon_ru.json differs from Lexicon.builtIn: regenerate it")
        #expect(Lexicon.current == Lexicon.builtIn)
    }

    @Test func moodMapResourceMatchesBuiltIn() throws {
        let bundled = try #require(MoodMap.loadBundled(), "mood_map.json is missing or doesn't decode")
        #expect(bundled == MoodMap.builtIn, "mood_map.json differs from MoodMap.builtIn: regenerate it")
    }

    @Test func everyMoodAndCompanyHasAnEntry() {
        for mood in Mood.allCases {
            #expect(MoodMap.builtIn.entry(mood) != nil, "\(mood)")
            #expect(Lexicon.builtIn.mood(mood) != nil, "\(mood)")
        }
        for company in Company.allCases {
            #expect(MoodMap.builtIn.entry(company) != nil, "\(company)")
            #expect(Lexicon.builtIn.company.contains { $0.company == company }, "\(company)")
        }
    }

    @Test func genreExclusionsNamedByMoodsExist() {
        let lexicon = Lexicon.builtIn
        for entry in lexicon.moods {
            for genre in entry.negation.exclude { #expect(lexicon.genre(genre) != nil, "\(entry.mood) → \(genre)") }
        }
        for group in lexicon.countryGroups {
            for member in group.members {
                #expect(lexicon.countries.contains { $0.name == member }, "\(group.id) → \(member)")
            }
        }
    }

    @Test func writeResourcesWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo.environment["INTENT_RESOURCES_OUT"] else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(Lexicon.builtIn).write(to: URL(fileURLWithPath: directory).appendingPathComponent("lexicon_ru.json"))
        try encoder.encode(MoodMap.builtIn).write(to: URL(fileURLWithPath: directory).appendingPathComponent("mood_map.json"))
    }
}
