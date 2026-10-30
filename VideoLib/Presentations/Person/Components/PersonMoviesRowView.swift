import SwiftUI

/// A person's titles in one role: the first twenty in a row, «Все» opens them all in a grid.
struct PersonMoviesRowView: View {
    private let title: String
    private let movies: [MovieSimple]

    @Environment(\.kpNavigate) private var navigate

    init(_ title: String, _ movies: [MovieSimple]) {
        self.title = title
        self.movies = movies
    }

    var body: some View {
        // The row's own «Все», on the heading's baseline like every other row's.
        KPRow(title: title, count: movies.count, items: Array(movies.prefix(20)), seeAll: movies.count > 20 ? { [navigate, movies, title] in
            navigate(.customList(movies, title))
        } : nil) { movie in
            CardView(movie: movie)
                .equatable()
        }
    }
}
