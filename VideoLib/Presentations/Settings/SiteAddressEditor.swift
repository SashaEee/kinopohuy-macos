import Defaults
import SwiftUI

/// The site's address: a field, «Проверить», and what the check found under it. An address that answers is saved at
/// once; one that didn't can still be saved by hand («Сохранить всё равно»: some addresses turn away a plain request
/// but work in the app). With the field empty, «Проверить» asks the saved address. `prominent` is the first-run
/// screen's bigger field with the white button; there the saved address answering counts as saved (`onSaved`), so
/// the first run moves on even when the address was saved elsewhere (Settings) while it was open.
struct SiteAddressEditor: View {
    var prominent = false
    /// Told after an address is saved; `verified`: it answered the check.
    var onSaved: (_ url: URL, _ verified: Bool) -> Void = { _, _ in }

    @Default(.mirror) private var mirror

    @State private var text = ""
    @State private var status: Status = .idle
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private enum Status: Equatable {
        case idle
        case invalid
        case checking
        /// The saved address answered.
        case reachable
        /// A new address is saved; `verified`: it answered first.
        case saved(verified: Bool)
        case failed(URL, String)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConfigured: Bool {
        SiteAddress.isConfigured(mirror)
    }

    private var canCheck: Bool {
        status != .checking && (!trimmed.isEmpty || isConfigured)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                field

                if prominent {
                    Button(action: check) {
                        Text(verbatim: status == .checking ? "Проверяем…" : "Проверить")
                    }
                    .buttonStyle(KPPrimaryButtonStyle(size: 13))
                    .disabled(!canCheck)
                    .opacity(canCheck ? 1 : 0.45)
                } else {
                    Button(action: check) {
                        Text(verbatim: status == .checking ? "Проверяем…" : "Проверить")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .disabled(!canCheck)
                    .opacity(canCheck ? 1 : 0.45)
                }
            }

            statusLine
                .frame(minHeight: 18, alignment: .top)
        }
        .animation(.snappy(duration: 0.2), value: status)
        .onChange(of: text) {
            // Cleared after a save: keep «адрес сохранён» on screen.
            if text.isEmpty, case .saved = status { return }

            checkTask?.cancel()
            status = .idle
        }
        .onDisappear {
            checkTask?.cancel()
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: prominent ? 15 : 13, weight: .medium))
                .foregroundStyle(focused ? KP.fg70 : KP.fg38)

            TextField(text: $text, prompt: Text(verbatim: prompt).foregroundStyle(KP.fg38)) {
                Text(verbatim: "Адрес сайта")
            }
            .textFieldStyle(.plain)
            .font(KP.font(prominent ? 15 : 13.5, .medium))
            .foregroundStyle(KP.fg)
            .autocorrectionDisabled()
            .focused($focused)
            .onSubmit(check)
        }
        .padding(.horizontal, 12)
        .frame(height: prominent ? 44 : 34)
        .background(KP.bg.opacity(0.75), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(focused ? KP.fg38 : KP.line, in: .rect(cornerRadius: 10, style: .continuous).stroke(lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    /// The saved address as the hint, so it's clear what's in use; an example form while there is none.
    private var prompt: String {
        if isConfigured, let host = mirror.host() {
            return host
        }

        return "https://адрес-сайта"
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            if prominent, isConfigured {
                SettingsStatusLine(text: "Адрес уже указан. Пустое поле проверит его, или введите другой.", symbol: "info.circle")
            } else if prominent {
                SettingsStatusLine(text: "Вставьте адрес из браузера и нажмите «Проверить».", symbol: "info.circle")
            } else if isConfigured {
                SettingsStatusLine(text: "Чтобы изменить адрес, введите новый. Пустое поле проверит текущий.", symbol: "info.circle")
            } else {
                SettingsStatusLine(text: "Адрес не указан: без него приложение не откроет ни одной страницы.", symbol: "exclamationmark.circle", tone: .warning)
            }
        case .invalid:
            SettingsStatusLine(text: "Это не похоже на адрес сайта. Пример: https://site.example", symbol: "exclamationmark.circle.fill", tone: .bad)
        case .checking:
            SettingsStatusLine(text: "Проверяем, отвечает ли сайт…", symbol: "clock")
        case .reachable:
            SettingsStatusLine(text: "Сайт отвечает", symbol: "checkmark.circle.fill", tone: .good)
        case let .saved(verified):
            SettingsStatusLine(text: verified ? "Сайт отвечает, адрес сохранён" : "Адрес сохранён без проверки", symbol: "checkmark.circle.fill", tone: verified ? .good : .warning)
        case let .failed(url, message):
            VStack(alignment: .leading, spacing: 8) {
                SettingsStatusLine(text: message, symbol: "exclamationmark.triangle.fill", tone: .bad)

                if url != mirror {
                    Button {
                        save(url, verified: false)
                    } label: {
                        Text(verbatim: "Сохранить всё равно")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                }
            }
        }
    }

    private func check() {
        guard canCheck else { return }

        let url: URL
        let isNew: Bool

        if trimmed.isEmpty {
            url = mirror
            isNew = false
        } else {
            guard let normalized = SiteAddressCheck.normalize(trimmed) else {
                status = .invalid
                return
            }

            url = normalized
            isNew = normalized != mirror
        }

        status = .checking

        let userAgent = Const.userAgent

        checkTask?.cancel()
        checkTask = Task {
            let outcome = await SiteAddressCheck.check(url, userAgent: userAgent)

            guard !Task.isCancelled else { return }

            switch outcome {
            case .reachable:
                if isNew {
                    save(url, verified: true)
                } else if prominent {
                    // Already saved (perhaps from Settings while the first run was open): it answered, so it's done.
                    markSaved(url, verified: true)
                } else {
                    status = .reachable
                }
            case let .failed(message):
                status = .failed(url, message)
            }
        }
    }

    private func save(_ url: URL, verified: Bool) {
        CookiesManager.shared.setMirror(url)

        markSaved(url, verified: verified)
    }

    /// «Адрес сохранён» on screen and `onSaved`, for an address that is the saved one now.
    private func markSaved(_ url: URL, verified: Bool) {
        status = .saved(verified: verified)
        text = ""
        focused = false

        onSaved(url, verified)
    }
}
