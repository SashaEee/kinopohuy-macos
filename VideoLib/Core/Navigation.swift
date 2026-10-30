import SwiftUI

enum Tabs: Hashable, Identifiable, CaseIterable {
    case home
    case categories
    case collections
    case search
    case watchingLater
    case bookmarks

    var label: LocalizedStringKey {
        switch self {
        case .home:
            "key.home"
        case .search:
            "key.search"
        case .categories:
            "key.categories"
        case .collections:
            "key.collections"
        case .watchingLater:
            "key.watching_later"
        case .bookmarks:
            "key.bookmarks"
        }
    }

    /// Its name in the top bar.
    var title: String {
        switch self {
        case .home: "Главная"
        case .search: "Поиск"
        case .categories: "Каталог"
        case .collections: "Подборки"
        case .watchingLater: "Досмотреть"
        case .bookmarks: "Закладки"
        }
    }

    /// The top bar's order.
    static let barOrder: [Tabs] = [.home, .search, .categories, .collections, .watchingLater, .bookmarks]

    var image: String {
        switch self {
        case .home:
            "house"
        case .search:
            "magnifyingglass"
        case .categories:
            "square.grid.2x2"
        case .collections:
            "film.stack"
        case .watchingLater:
            "clock.arrow.circlepath"
        case .bookmarks:
            "bookmark"
        }
    }

    var needAccount: Bool {
        switch self {
        case .watchingLater, .bookmarks:
            true
        default:
            false
        }
    }

    var id: Self {
        self
    }
}

enum Destinations: Hashable, Identifiable {
    case details(MovieSimple)
    /// The title's page with the voice-over and episode choice opened at once («Смотреть» on Home's banner).
    case watch(MovieSimple)
    case country(MovieCountry)
    case category(Categories)
    case genre(MovieGenre)
    case collection(MoviesCollection)
    case customList([MovieSimple], String)
    case list(MovieList)
    case person(PersonSimple)
    case comments(MovieDetailed)

    static func fromNamed(_ item: some Named) -> Destinations {
        if let country = item as? MovieCountry {
            return .country(country)
        } else if let genre = item as? MovieGenre {
            return .genre(genre)
        } else if let person = item as? PersonSimple {
            return .person(person)
        } else if let list = item as? MovieList {
            return .list(list)
        } else if let collection = item as? MoviesCollection {
            return .collection(collection)
        }

        fatalError("Need \"named\" implementation")
    }

    var id: Self {
        self
    }
}
