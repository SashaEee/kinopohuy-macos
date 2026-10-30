import SwiftUI

/// Moving between pages. The stack itself can only cut (or slide, like a settings pane), so every push and pop goes
/// under a quick dip into the background colour: the current page fades out (0.14 s), the stack swaps out of sight,
/// and the cover lifts (0.3 s) off a page that is already laid out. The top bar stays above it all.
@MainActor @Observable
final class KPPageFade {
    /// The cover's opacity over the pages (0 … 1).
    private(set) var cover: Double = 0
    /// A dip is running: the cover takes the clicks for all of it (so a second click of a double click lands on it).
    private(set) var blocking = false

    private enum Phase { case idle, covering, revealing }
    private struct Change {
        let key: AnyHashable?
        let run: @MainActor () -> Void
    }

    @ObservationIgnored private var phase = Phase.idle
    /// What runs once the cover is up, in order.
    @ObservationIgnored private var queue: [Change] = []

    /// Runs `change` (a push, a pop, a section switch) under the cover. Requests made during a dip are queued: under
    /// the cover that is rising they run with this one, and after one that is lifting they get a dip of their own.
    /// A request with the same `key` as the last queued one is dropped (a double click opens one page); a change
    /// should read the state it acts on when it runs, not when it was asked for (two «Назад» go back twice).
    func run(key: AnyHashable? = nil, _ change: @escaping @MainActor () -> Void) {
        if let key, queue.last?.key == key { return }
        queue.append(Change(key: key, run: change))
        guard phase == .idle else { return }
        dip()
    }

    private func dip() {
        phase = .covering
        blocking = true
        withAnimation(.easeIn(duration: 0.14)) {
            cover = 1
        } completion: { [self] in
            let changes = queue
            queue.removeAll()
            Self.instantly { changes.forEach { $0.run() } }
            phase = .revealing
            // A turn of the run loop, so the new page is laid out under the cover before it lifts.
            DispatchQueue.main.async { [self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    cover = 0
                } completion: { [self] in
                    phase = .idle
                    if queue.isEmpty {
                        blocking = false
                    } else {
                        dip()
                    }
                }
            }
        }
    }

    private static func instantly(_ change: @MainActor () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// Opens a title, list or person (through the page fade). Set by the shell for everything inside the stack.
/// Equal by the fade it goes through: the shell makes a new one on every pass, and a changed environment value would
/// redraw every link (every card) on screen.
struct KPNavigateAction: Sendable, Equatable {
    let id: ObjectIdentifier?
    let open: @MainActor @Sendable (Destinations) -> Void

    @MainActor func callAsFunction(_ route: Destinations) { open(route) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    @Entry var kpNavigate = KPNavigateAction(id: nil) { _ in }
}

/// A link to a title, list or person: a button that opens it through the page fade (a NavigationLink would push at
/// once, with the stack's cut).
struct KPRouteLink<Label: View>: View {
    let route: Destinations
    @ViewBuilder let label: () -> Label

    @Environment(\.kpNavigate) private var navigate

    var body: some View {
        Button {
            navigate(route)
        } label: {
            label()
        }
        .accessibilityAddTraits(.isLink)
    }
}
