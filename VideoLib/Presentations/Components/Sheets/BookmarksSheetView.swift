import ComposableArchitecture
import SwiftUI

/// «В закладки»: the folders as rows with a check; a press puts the title in the folder or takes it out.
struct BookmarksSheetView: View {
    @Bindable var store: StoreOf<BookmarksSheetFeature>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        KPSheet(title: "В закладки", subtitle: "Отметьте папки, в которых он будет", symbol: "bookmark.fill", width: 480) {
            Group {
                if let error = store.bookmarks.error {
                    KPErrorView(message: error.kpMessage) { store.send(.reload, animation: .easeInOut) }
                        .frame(height: 200)
                } else if let bookmarks = store.bookmarks.data {
                    if bookmarks.isEmpty {
                        KPEmptyView(message: "Папок пока нет — создайте первую", symbol: "bookmark")
                            .frame(height: 160)
                    } else {
                        ScrollView(.vertical) {
                            VStack(spacing: 4) {
                                ForEach(bookmarks) { bookmark in
                                    FolderRow(bookmark: bookmark, enabled: store.id.id != nil) {
                                        store.send(.toggle(bookmark))
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    KPLoadingView().frame(height: 160)
                }
            }

            HStack {
                Button {
                    store.send(.createTapped)
                } label: {
                    Label("Новая папка", systemImage: "plus")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 14))
                Spacer()
                Button("Готово") {
                    dismiss()
                }
                .buttonStyle(KPPrimaryButtonStyle(size: 14))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .dialogSeverity(.critical)
    }
}

private struct FolderRow: View {
    let bookmark: Bookmark
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    private var checked: Bool { bookmark.isChecked ?? false }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(checked ? KP.sun : KP.fg38)
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: bookmark.name)
                    .font(KP.font(15, checked ? .semibold : .medium))
                    .foregroundStyle(KP.fg)
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "\(bookmark.count)")
                    .font(KP.font(13, .semibold).monospacedDigit())
                    .foregroundStyle(KP.fg38)
                    .contentTransition(.numericText(value: Double(bookmark.count)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? KP.surfaceHigh : KP.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.18), value: checked)
    }
}
