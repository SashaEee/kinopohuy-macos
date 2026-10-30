import ComposableArchitecture
import SwiftUI

struct RestoreSheetView: View {
    @Bindable var store: StoreOf<RestoreFeature>

    @Environment(\.dismiss) private var dismiss



    private enum FocusedField {
        case login
    }

    @FocusState private var focusedField: FocusedField?

    var body: some View {
        Group {
            switch store.status {
            case .data:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.restore.label")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.password.lost")
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .center, spacing: 8) {
                        VStack(spacing: 2.5) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("key.username.full")

                                TextField("key.username.full", text: $store.login, prompt: Text(String(localized: "key.username.full").lowercased()))
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .login)
                                    .onSubmit {
                                        if !store.login.isEmpty {
                                            store.send(.submit)
                                        }
                                    }
                            }
                            .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .kpField()
                    }

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.submit)
                        } label: {
                            Text("key.restore")
                        }
                        .buttonStyle(KPSheetButtonStyle(primary: true, enabled: !store.login.isEmpty))
                        .disabled(store.login.isEmpty)
                        .animation(.easeInOut, value: !store.login.isEmpty)

                        Button {
                            store.send(.signInTapped)
                        } label: {
                            Text("key.cancel")
                        }
                        .buttonStyle(KPSheetButtonStyle())
                    }
                }
                .onAppear {
                    focusedField = .login
                }
            case .loading:
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.restore.enter")
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
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.ops")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.username.email.error")
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
                            store.send(.signInTapped)
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
        .alert("key.restore.success", isPresented: $store.isSuccessPresented) {
            Button(role: .cancel) {
                store.send(.signInTapped)
            } label: {
                Text("key.ok")
            }
        } message: {
            Text("key.restore.success.message-\(store.email)")
        }
    }
}
