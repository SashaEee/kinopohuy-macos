import ComposableArchitecture
import SwiftUI

struct RenameBookmarkSheetView: View {
    @Bindable var store: StoreOf<RenameBookmarkFeature>

    @Environment(\.dismiss) private var dismiss

    private enum FocusedField {
        case name
    }

    @FocusState private var focusedField: FocusedField?

    var body: some View {
        Group {
            switch store.status {
            case .data:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text(verbatim: "Переименовать папку")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text(verbatim: "Новое название папки")
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                            .multilineTextAlignment(.center)
                    }

                    TextField("key.name", text: $store.name, prompt: Text(verbatim: "Название").foregroundStyle(KP.fg38))
                        .textFieldStyle(.plain)
                        .font(KP.font(16, .medium))
                        .foregroundStyle(KP.fg)
                        .focused($focusedField, equals: .name)
                        .onSubmit {
                            store.send(.submit)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .kpField()
                        .overlay(KP.sun.opacity(focusedField == .name ? 0.6 : 0), in: .rect(cornerRadius: 12, style: .continuous).stroke(lineWidth: 1.5))
                        .animation(.easeOut(duration: 0.15), value: focusedField)

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.submit)
                        } label: {
                            Text("key.rename")
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
                .onAppear {
                    focusedField = .name
                }
            case .loading:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.rename.enter")
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
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.ops")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.name.error")
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
}
