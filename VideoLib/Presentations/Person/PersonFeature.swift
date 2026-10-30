import ComposableArchitecture
import SwiftUI

@Reducer
struct PersonFeature {
    @ObservableState
    struct State: Equatable {
        let id: String
        let name: String

        var details: DataState<PersonDetailed> = .idle

        init(person: PersonSimple) {
            id = person.personId
            name = person.name
        }
    }

    enum Action {
        case onAppear
        case reload
        case detailsLoaded(Result<PersonDetailed, any Error>)
    }

    private enum CancelID { case load }

    @Dependency(\.getPersonDetailsUseCase) private var getPersonDetailsUseCase
    @Dependency(\.recommender) private var recommender

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.details.needsLoad else { return .none }

                return .send(.reload)

            case .reload:
                state.details = .loading

                return .run { [id = state.id, name = state.name] send in
                    let result = await Result { try await getPersonDetailsUseCase(id: id) }

                    await send(.detailsLoaded(result), animation: .easeInOut)

                    // Their filmography goes into the recommender's catalogue (no extra request).
                    if case let .success(details) = result { await recommender.captureFilmography(details, personPath: id, name: name) }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .detailsLoaded(.success(details)):
                state.details = .data(details)

                return .none

            case let .detailsLoaded(.failure(error)):
                state.details = .error(error)

                return .none
            }
        }
    }
}
