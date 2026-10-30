import ComposableArchitecture
import SwiftUI

struct CommentsView: View {
    @Bindable var store: StoreOf<CommentsFeature>

    var body: some View {
        ScrollView(.vertical) {
            KPScreenHeader(title: store.title)
                .kpBelowTopBar()
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                if store.comments.data?.isEmpty == false, store.reply == nil {
                    CommentTextAreaView()
                        .padding(.top, 18)
                        .environment(store)
                }

                LazyVStack(alignment: .leading, spacing: 16) {
                    if let comments = store.comments.data, !comments.isEmpty {
                        ForEach(comments) { comment in
                            CommentView(comment: comment)
                                .equatable()
                                .environment(store)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 18)
            }
            .padding(.horizontal, KP.gutter)
            .frame(maxWidth: 980 + KP.gutter * 2, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.paginationState == .loading {
                KPLoadingView().frame(height: 60)
            }
        }
        .scrollIndicators(.visible, axes: .vertical)
        .onScrollTargetVisibilityChange(idType: Comment.ID.self) { onScreenComments in
            if store.paginationState == .idle,
               let comments = store.comments.data,
               !comments.isEmpty,
               let last = comments.last,
               onScreenComments.contains(where: { $0 == last.id })
            {
                store.send(.loadMore)
            }
        }
        .viewModifier { view in
            if #available(macOS 26, *) {
                view.scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                view
            }
        }
        .overlay {
            if let error = store.comments.error {
                KPErrorView(message: error.kpMessage) {
                    store.send(.reload)
                }
            } else if let comments = store.comments.data, comments.isEmpty {
                ScrollView(.vertical) {
                    KPScreenHeader(title: store.title)
                        .kpBelowTopBar()
                    CommentTextAreaView()
                        .padding(.vertical, 18)
                        .padding(.horizontal, KP.gutter)
                        .frame(maxWidth: 980 + KP.gutter * 2, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(store)
                }
                .background(KP.bg)
                .scrollIndicators(.visible, axes: .vertical)
                .viewModifier { view in
                    if #available(macOS 26, *) {
                        view.scrollEdgeEffectStyle(.soft, for: .all)
                    } else {
                        view
                    }
                }
            } else if store.comments.isLoading {
                KPLoadingView()
            }
        }
        .background {
            Button("") { store.send(.reload) }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
        .alert($store.scope(state: \.moderationAlert, action: \.moderationAlert))
        .dialogSeverity(.automatic)
        .sheet(isPresented: $store.isCommentPresented) {
            KPSheet(title: "Комментарий", symbol: "text.bubble.fill", width: 680) {
                if let comment = store.comment {
                    ScrollView(.vertical) {
                        CommentView(comment: comment)
                            .equatable()
                            .environment(store)
                    }
                    .scrollIndicators(.visible, axes: .vertical)
                    .frame(maxHeight: 460)
                } else {
                    KPLoadingView().frame(height: 120)
                }
            }
        }
        .sheet(item: $store.scope(state: \.reportComment, action: \.reportComment)) { store in
            CommentReportSheetView(store: store)
        }
        .confirmationDialog($store.scope(state: \.deleteDialog, action: \.deleteDialog))
        .kpScreenBackground()
    }
}
