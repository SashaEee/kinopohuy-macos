import Foundation
import Testing
@testable import RecsAppLogic

@Suite("Импорт оценок")
struct RatingImportTests {
    @Test func imdbExport() throws {
        let csv = """
        Const,Your Rating,Date Rated,Title,Original Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
        tt0133093,10,2024-03-17,The Matrix,The Matrix,https://www.imdb.com/title/tt0133093/,Movie,8.7,136,1999,"Action, Sci-Fi",2100000,1999-03-24,"Lana Wachowski, Lilly Wachowski"
        tt1375666,8,2023-01-02,Inception,Inception,https://www.imdb.com/title/tt1375666/,Movie,8.8,148,2010,"Action, Adventure, Sci-Fi",2600000,2010-07-08,Christopher Nolan
        tt0000001,3,2020-05-05,"Bad, ""really"" bad",x,y,Movie,2,1,1990,Drama,10,1990-01-01,Someone
        """
        let parsed = try #require(RatingImport.parse(csv))
        #expect(parsed.format == .imdb)
        #expect(parsed.entries.map(\.imdb) == [133093, 1375666, 1])
        #expect(parsed.entries.map(\.level) == [2, 1, -1.5])
        #expect(parsed.entries[0].ratedAt == 1_710_633_600)
    }

    @Test func letterboxdRatings() throws {
        let csv = "Date,Name,Year,Letterboxd URI,Rating\r\n2024-01-05,Arrival,2016,https://boxd.it/x,4.5\r\n2024-01-06,\"Crash, The\",2004,https://boxd.it/y,2\r\n2024-01-07,Unrated,2001,https://boxd.it/z,\r\n"
        let parsed = try #require(RatingImport.parse(csv))
        #expect(parsed.format == .letterboxd)
        #expect(parsed.entries.map(\.name) == ["Arrival", "Crash, The"])
        #expect(parsed.entries.map(\.year) == [2016, 2004])
        #expect(parsed.entries.map(\.level) == [2, -1.5])
    }

    @Test func somethingElseIsRefused() {
        #expect(RatingImport.parse("a,b,c\n1,2,3") == nil)
        #expect(RatingImport.parse("") == nil)
    }
}
