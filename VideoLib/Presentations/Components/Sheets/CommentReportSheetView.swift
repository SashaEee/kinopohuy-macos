import ComposableArchitecture
import SwiftUI

struct CommentReportSheetView: View {
    @Bindable var store: StoreOf<CommentReportFeature>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch store.status {
            case .data:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.report.label")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        ForEach(Reports.allCases) { report in
                            RadioButton(tag: report, selection: $store.report, message: $store.message, label: report.rawValue)
                        }
                    }

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.submit, animation: .easeInOut)
                        } label: {
                            Text("key.report")
                        }
                        .buttonStyle(KPSheetButtonStyle(primary: true, enabled: store.canSubmit))
                        .disabled(!store.canSubmit)
                        .animation(.easeInOut, value: store.canSubmit)

                        Button {
                            dismiss()
                        } label: {
                            Text("key.cancel")
                        }
                        .buttonStyle(KPSheetButtonStyle())
                    }
                }
            case .loading:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.report.enter")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.request.wait")
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                            .lineLimit(1, reservesSpace: true)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.cancelRequest, animation: .easeInOut)
                        } label: {
                            Text("key.cancel")
                        }
                        .buttonStyle(KPSheetButtonStyle())
                    }
                }
            case .error:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.ops")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.report.error")
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                            .lineLimit(1, reservesSpace: true)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.retry, animation: .easeInOut)
                        } label: {
                            Text("key.retry")
                        }
                        .buttonStyle(KPSheetButtonStyle(primary: true))

                        Button {
                            dismiss()
                        } label: {
                            Text("key.cancel")
                        }
                        .buttonStyle(KPSheetButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 35)
        .padding(.top, 35)
        .padding(.bottom, 25)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .background(KP.bg)
    }

    private struct RadioButton: View {
        @Binding private var isSelected: Bool
        @Binding private var message: String
        private let tag: Reports
        private let label: LocalizedStringKey

        @FocusState private var focused: Bool

        init(tag: Reports, selection: Binding<Reports?>, message: Binding<String>, label: LocalizedStringKey) {
            _isSelected = Binding(
                get: { selection.wrappedValue == tag },
                set: { _ in selection.wrappedValue = tag }
            )
            _message = message
            self.tag = tag
            self.label = label
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 0) {
                    Text(label)
                        .font(KP.font(14, .medium))
                        .foregroundStyle(KP.fg55)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }

                if isSelected, tag == .other {
                    TextField("key.message", text: $message, prompt: Text(String(localized: "key.message.more")))
                        .textFieldStyle(.plain)
                        .font(KP.font(14))
                        .focused($focused)
                }
            }
            .padding(10)
            .contentShape(.rect(cornerRadius: 6))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(isSelected ? Color.accentColor : KP.line, in: .rect(cornerRadius: 12, style: .continuous).stroke(lineWidth: 1))
            .onTapGesture { isSelected = true }
            .animation(.easeInOut, value: isSelected)
            .onChange(of: isSelected) {
                if isSelected, tag == .other {
                    focused = true
                } else {
                    focused = false
                }
            }
        }
    }
}
