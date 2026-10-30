import ComposableArchitecture
import SwiftUI

extension Send {
    func callAsFunction(_ action: Action, awaitingAnimation animation: Animation) async {
        await withCheckedContinuation { continuation in
            // A cancelled effect's send is dropped, and its transaction (with the completion) with it.
            guard !Task.isCancelled else {
                continuation.resume()
                return
            }
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion {
                continuation.resume()
            }

            self(action, transaction: transaction)
        }
    }
}
