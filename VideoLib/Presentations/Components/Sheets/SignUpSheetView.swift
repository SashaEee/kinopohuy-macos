import ComposableArchitecture
import Defaults
import SwiftUI

struct SignUpSheetView: View {
    @Bindable var store: StoreOf<SignUpFeature>

    @Environment(\.dismiss) private var dismiss


    private enum FocusedField {
        case email, username, password1, password2, verifyCode
    }

    @FocusState private var focusedField: FocusedField?

    @State private var confirmPasswordValid: Bool?

    @State private var showPassword: Bool = false
    @State private var passwordIsEmpty: Bool = true
    @State private var showConfirmPassword: Bool = false
    @State private var confirmPasswordIsEmpty: Bool = true


    @State private var showPremiumWarning: Bool = true

    var body: some View {
        Group {
            if store.status.isLoading {
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.sign_up.enter")
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
            } else {
                VStack(alignment: .center, spacing: 25) {
                    VStack(alignment: .center, spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KP.sun)

                        Text("key.sign_up.label")
                            .font(KP.font(24, .heavy))
                            .foregroundStyle(KP.fg)

                        Text("key.sign_up.description")
                            .font(KP.font(14, .medium))
                            .foregroundStyle(KP.fg55)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .center, spacing: 8) {
                        VStack(spacing: 2.5) {
                            if store.step == .first {
                                HStack(alignment: .center, spacing: 8) {
                                    Text("key.email")

                                    TextField("key.email", text: $store.email, prompt: Text(String(localized: "key.email").lowercased()))
                                        .textFieldStyle(.plain)
                                        .multilineTextAlignment(.trailing)
                                        .focused($focusedField, equals: FocusedField.email)
                                        .onSubmit {
                                            focusedField = .username
                                        }
                                }
                                .padding(.vertical, 10)

                                Divider()

                                HStack(alignment: .center, spacing: 8) {
                                    Text("key.username")

                                    TextField("key.username", text: $store.username, prompt: Text(String(localized: "key.username").lowercased()))
                                        .textFieldStyle(.plain)
                                        .multilineTextAlignment(.trailing)
                                        .focused($focusedField, equals: .username)
                                        .onSubmit {
                                            focusedField = .password1
                                        }
                                }
                                .padding(.vertical, 10)

                                Divider()

                                HStack(alignment: .center, spacing: 8) {
                                    Text("key.password")

                                    Group {
                                        if showPassword {
                                            TextField("key.password", text: $store.password1, prompt: Text(String(localized: "key.password").lowercased()))
                                                .textFieldStyle(.plain)
                                                .multilineTextAlignment(.trailing)
                                                .focused($focusedField, equals: .password1)
                                                .onSubmit {
                                                    focusedField = .password2
                                                }
                                        } else {
                                            SecureField("key.password", text: $store.password1, prompt: Text(String(localized: "key.password").lowercased()))
                                                .textFieldStyle(.plain)
                                                .multilineTextAlignment(.trailing)
                                                .focused($focusedField, equals: .password1)
                                                .onSubmit {
                                                    focusedField = .password2
                                                }
                                        }
                                    }
                                    .task(id: store.password1) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            passwordIsEmpty = store.password1.isEmpty
                                        }

                                        withAnimation(.easeInOut) {
                                            confirmPasswordValid = nil
                                        }

                                        guard !store.password1.isEmpty, !store.password2.isEmpty else { return }

                                        try? await Task.sleep(for: .milliseconds(500))

                                        guard !Task.isCancelled else { return }

                                        withAnimation(.easeInOut) {
                                            confirmPasswordValid = store.password2 == store.password1
                                        }
                                    }

                                    if !passwordIsEmpty {
                                        Image(systemName: "eye")
                                            .foregroundStyle(Color.accentColor.opacity(showPassword ? 0.5 : 1))
                                            .simultaneousGesture(
                                                DragGesture(minimumDistance: 0)
                                                    .onChanged { _ in
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            showPassword = true
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            showPassword = false
                                                        } completion: {
                                                            focusedField = .password1
                                                        }
                                                    }
                                            )
                                    }
                                }
                                .padding(.vertical, 10)

                                Divider()

                                HStack(alignment: .center, spacing: 8) {
                                    Text("key.password.confirm")

                                    Group {
                                        if showConfirmPassword {
                                            TextField("key.password.confirm", text: $store.password2, prompt: Text(String(localized: "key.password.confirm").lowercased()))
                                                .textFieldStyle(.plain)
                                                .multilineTextAlignment(.trailing)
                                                .focused($focusedField, equals: .password2)
                                                .onSubmit {
                                                    if confirmPasswordValid == true {
                                                        store.send(.submit)
                                                    }
                                                }
                                        } else {
                                            SecureField("key.password.confirm", text: $store.password2, prompt: Text(String(localized: "key.password.confirm").lowercased()))
                                                .textFieldStyle(.plain)
                                                .multilineTextAlignment(.trailing)
                                                .focused($focusedField, equals: .password2)
                                                .onSubmit {
                                                    if confirmPasswordValid == true {
                                                        store.send(.submit)
                                                    }
                                                }
                                        }
                                    }
                                    .task(id: store.password2) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            confirmPasswordIsEmpty = store.password2.isEmpty
                                        }

                                        withAnimation(.easeInOut) {
                                            confirmPasswordValid = nil
                                        }

                                        guard !store.password1.isEmpty, !store.password2.isEmpty else { return }

                                        try? await Task.sleep(for: .milliseconds(500))

                                        guard !Task.isCancelled else { return }

                                        withAnimation(.easeInOut) {
                                            confirmPasswordValid = store.password2 == store.password1
                                        }
                                    }

                                    if !confirmPasswordIsEmpty {
                                        Image(systemName: "eye")
                                            .foregroundStyle(Color.accentColor.opacity(showConfirmPassword ? 0.5 : 1))
                                            .simultaneousGesture(
                                                DragGesture(minimumDistance: 0)
                                                    .onChanged { _ in
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            showConfirmPassword = true
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            showConfirmPassword = false
                                                        } completion: {
                                                            focusedField = .password2
                                                        }
                                                    }
                                            )
                                    }
                                }
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottomLeading) {
                                    if confirmPasswordValid == false {
                                        Text(String(localized: "key.password.confirm.error").lowercased())
                                            .font(KP.font(12, .medium))
                                            .foregroundStyle(KP.sun)
                                    }
                                }
                                .onAppear {
                                    focusedField = .email
                                }
                            } else if store.step == .third {
                                HStack(alignment: .center, spacing: 8) {
                                    Text("key.verify.code")

                                    TextField("key.verify.code", text: $store.verifyCode, prompt: Text(String(localized: "key.verify.code").lowercased()))
                                        .textFieldStyle(.plain)
                                        .multilineTextAlignment(.trailing)
                                        .focused($focusedField, equals: .verifyCode)
                                        .onSubmit {
                                            store.send(.submit)
                                        }
                                }
                                .padding(.vertical, 10)
                                .onAppear {
                                    focusedField = .verifyCode
                                }
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .kpField()
                    }

                    VStack(alignment: .center, spacing: 10) {
                        Button {
                            store.send(.submit)
                        } label: {
                            Text("key.sign_up")
                        }
                        .buttonStyle(KPSheetButtonStyle(primary: true, enabled: confirmPasswordValid == true))
                        .disabled(confirmPasswordValid != true)

                        Button {
                            dismiss()
                        } label: {
                            Text("key.cancel")
                        }
                        .buttonStyle(KPSheetButtonStyle())
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text("key.sign_up.sign_in.q").font(KP.font(12, .medium))

                        Button {
                            store.send(.signInTapped)
                        } label: {
                            Text(verbatim: "\(String(localized: "key.sign_in"))!")
                                .font(KP.font(12, .medium))
                                .foregroundStyle(KP.sun)
                        }
                        .buttonStyle(.plain)
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
        .alert("key.ops", isPresented: Binding { store.status.error != nil } set: { _ in }) {
            Button {
                store.send(.retry, animation: .easeInOut)
            } label: {
                Text("key.retry")
            }

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("key.cancel")
            }
        } message: {
            if let error = store.status.error {
                Text(error.kpMessage)
            }
        }
        .dialogSeverity(.critical)
        .confirmationDialog("key.verify.code", isPresented: Binding { store.step == .second && store.status.error == nil } set: { _ in }) {
            Button {
                store.send(.submit)
            } label: {
                Text("key.continue")
            }

            Button(role: .cancel) {
                store.send(.cancelVerification, animation: .easeInOut)
            } label: {
                Text("key.cancel")
            }
        } message: {
            Text("ket.verify.code-\(store.email)")
        }
        .alert("key.sign_up.premium", isPresented: $showPremiumWarning) {
            Button(role: .cancel) {} label: {
                Text("key.ok")
            }
        } message: {
            Text("key.sign_up.premium.description")
        }
        .dialogSeverity(.critical)
    }
}
