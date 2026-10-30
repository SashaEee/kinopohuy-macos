import ComposableArchitecture
import Defaults
import Kingfisher
import Pow
import SwiftUI

/// A comment as a card (a reply: under its comment, set off by a thin line), its author, date, text and what you can
/// do with it.
struct CommentView: View {
    private let comment: Comment
    private let isReply: Bool

    init(comment: Comment, isReply: Bool = false) {
        self.comment = comment
        self.isReply = isReply
    }

    @Environment(StoreOf<CommentsFeature>.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    KPAvatar(url: comment.photo, name: comment.author, size: isReply ? 28 : 34)

                    Text(comment.author)
                        .font(KP.font(14, .bold))
                        .foregroundStyle(KP.fg)
                        .textSelection(.enabled)

                    Text(comment.date)
                        .font(KP.font(13))
                        .foregroundStyle(KP.fg38)
                }

                CommentTextView(text: comment.text)

                HStack(alignment: .center, spacing: 8) {
                    CommentLikeButton(comment: comment)

                    CommentReplyButton(commentId: comment.commentId)

                    if !comment.isAdmin {
                        Button {
                            store.send(.reportTapped(comment))
                        } label: {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .foregroundStyle(KP.fg55)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(height: 30)
                                .padding(.horizontal, 14)
                                .contentShape(.capsule)
                                .background(Capsule().fill(KP.chip))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if comment.deleteHash != nil {
                        Button {
                            store.send(.deleteTapped(comment))
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(KP.fg55)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(height: 30)
                                .padding(.horizontal, 14)
                                .contentShape(.capsule)
                                .background(Capsule().fill(KP.chip))
                        }
                        .buttonStyle(.plain)
                    }
                }

                CommentReplyArea(commentId: comment.commentId)
            }

            if !comment.replies.isEmpty {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(comment.replies) { reply in
                        CommentView(comment: reply, isReply: true)
                            .equatable()
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Capsule().fill(KP.line).frame(width: 2)
                }
            }
        }
        .padding(isReply ? 0 : 16)
        .background {
            if !isReply {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KP.surface.opacity(0.75))
            }
        }
    }
}

extension CommentView: Equatable {
    nonisolated static func == (lhs: CommentView, rhs: CommentView) -> Bool {
        lhs.comment == rhs.comment
    }
}

private struct CommentLikeButton: View {
    let comment: Comment

    @State private var isHovering = false

    @Default(.isLoggedIn) private var isLoggedIn

    @Environment(StoreOf<CommentsFeature>.self) private var store

    var body: some View {
        @Bindable var store = store

        Button {
            if isLoggedIn {
                store.send(.likeTapped(comment))
            } else {
                store.send(.signInRequired)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                if comment.isLiked {
                    Image(systemName: "hand.thumbsup.fill")
                        .foregroundStyle(KP.sun)
                        .font(.system(size: 13, weight: .semibold))
                        .transition(.movingParts.pop(KP.sun))
                } else {
                    Image(systemName: "hand.thumbsup")
                        .foregroundStyle(KP.fg55)
                        .font(.system(size: 13, weight: .semibold))
                }

                if comment.likesCount > 0 {
                    Text(verbatim: "\(comment.likesCount)")
                        .font(KP.font(13, .semibold).monospacedDigit())
                        .foregroundStyle(KP.fg80)
                        .contentTransition(.numericText(value: Double(comment.likesCount)))
                }
            }
            .frame(height: 30)
            .padding(.horizontal, 14)
            .background(Capsule().fill(comment.isLiked ? KP.sun.opacity(0.16) : KP.chip))
        }
        .buttonStyle(.plain)
        .disabled(comment.selfComment)
        .onHover { isHovering in
            self.isHovering = isHovering
        }
        .task(id: isHovering) {
            guard isHovering else { return }

            try? await Task.sleep(for: .milliseconds(500))

            guard !Task.isCancelled else { return }

            store.send(.likesHovered(comment))
        }
        .popover(item: $store.likes[comment.commentId], attachmentAnchor: .rect(.bounds), arrowEdge: .top) { like in
            VStack(alignment: .center, spacing: 10) {
                if !like.likes.isEmpty {
                    let chunks = like.likes.chunks(ofCount: 8)

                    ForEach(chunks.indices, id: \.self) { chunkIndex in
                        let likes = chunks[chunkIndex]

                        HStack(alignment: .center, spacing: 10) {
                            ForEach(likes) { like in
                                VStack(alignment: .center, spacing: 5) {
                                    KPAvatar(url: like.photo, name: like.name, size: 52)

                                    Text(like.name)
                                        .lineLimit(1)
                                        .font(KP.font(12, .medium))
                                        .foregroundStyle(KP.fg70)
                                }
                                .frame(width: 64)
                            }
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)
            .background(KP.surface)
            .environment(\.colorScheme, .dark)
        }
    }
}

private struct CommentReplyButton: View {
    let commentId: String

    @Environment(StoreOf<CommentsFeature>.self) private var store

    var body: some View {
        Button {
            withAnimation(.easeInOut) {
                store.reply = (store.reply == commentId) ? nil : commentId
            }
        } label: {
            Group {
                if store.reply == commentId {
                    Image(systemName: "chevron.up")
                } else {
                    Text(verbatim: "Ответить")
                }
            }
            .font(KP.font(13, .semibold))
            .foregroundStyle(KP.fg80)
            .frame(height: 30)
            .padding(.horizontal, 14)
            .contentShape(.capsule)
            .background(Capsule().fill(KP.chip))
        }
        .buttonStyle(.plain)
    }
}

private struct CommentReplyArea: View {
    let commentId: String

    @Environment(StoreOf<CommentsFeature>.self) private var store

    var body: some View {
        if store.reply == commentId {
            CommentTextAreaView()
        }
    }
}
