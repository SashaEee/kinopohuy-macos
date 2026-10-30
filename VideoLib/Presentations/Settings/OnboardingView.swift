import AppKit
import Defaults
import SwiftUI

/// The first screen of a fresh install, and of any install still without the site's address: a welcome and the terms,
/// then the address (the app ships without one; it's checked before it's saved), then an offer to sign in. It can't
/// be dismissed before an address is saved. Once one is (here, or in Settings while this is open), «Дальше» moves on.
struct OnboardingView: View {
    /// Told when it's done; `signIn`: the viewer chose «Войти».
    let finish: (_ signIn: Bool) -> Void

    @Default(.mirror) private var mirror

    @State private var step: Step = .welcome
    @State private var forward = true
    /// Whether the saved address answered its check; nil: it was saved without one here (moved on with «Дальше»).
    @State private var verified: Bool?

    private enum Step: Int, CaseIterable {
        case welcome
        case address
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            StepDots(count: Step.allCases.count, current: step.rawValue)
                .padding(.top, 22)

            ZStack {
                switch step {
                case .welcome:
                    welcome
                        .transition(transition)
                case .address:
                    address
                        .transition(transition)
                case .done:
                    done
                        .transition(transition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 30)
        .frame(width: 620, height: 600)
        .background {
            ZStack(alignment: .top) {
                KP.bg

                // The sun rising behind the logo.
                Rectangle()
                    .fill(EllipticalGradient(colors: [KP.sun.opacity(0.2), KP.sun.opacity(0.07), .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .frame(width: 820, height: 520)
                    .offset(y: -280)
            }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func go(_ next: Step) {
        forward = next.rawValue > step.rawValue

        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            step = next
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(.kinoPohuySun)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)

            Text(verbatim: "Добро пожаловать в")
                .font(KP.font(15, .medium))
                .foregroundStyle(KP.fg55)
                .padding(.top, 14)

            KPLogo(height: 36)
                .padding(.top, 4)

            Text(verbatim: "Каталог, плеер, закладки и загрузки в одном тёмном окне на Mac.")
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg70)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "Прежде чем начать")
                    .font(KP.font(13, .semibold))
                    .foregroundStyle(KP.fg)

                DisclaimerPoints(fontSize: 13)
            }
            .padding(18)
            .kpField()
            .padding(.top, 24)

            Spacer(minLength: 20)

            Button {
                go(.address)
            } label: {
                Text(verbatim: "Принимаю")
            }
            .buttonStyle(KPSheetButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)

            Button {
                NSApp.terminateClosingSheets()
            } label: {
                Text(verbatim: "Не сейчас — выйти")
                    .font(KP.font(12.5, .medium))
                    .foregroundStyle(KP.fg38)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private var address: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "globe")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(KP.sun)
                .frame(width: 54, height: 54)
                .background(Circle().fill(KP.sun.opacity(0.14)))

            Text(verbatim: "Адрес сайта")
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)
                .padding(.top, 16)

            Text(verbatim: "В приложении нет адреса сайта: его указываете вы. Скопируйте адрес из адресной строки браузера.")
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            SiteAddressEditor(prominent: true) { _, verified in
                self.verified = verified

                Task {
                    // A beat to read «адрес сохранён» before the next step.
                    try? await Task.sleep(for: .milliseconds(verified ? 700 : 300))
                    if step == .address {
                        go(.done)
                    }
                }
            }
            .padding(.top, 28)

            Spacer(minLength: 20)

            Text(verbatim: "Адрес можно сменить в любой момент: Настройки → Основное.")
                .font(KP.font(12, .medium))
                .foregroundStyle(KP.fg38)

            // An address saved earlier (or in Settings while this is open) needs no new check to go on.
            if SiteAddress.isConfigured(mirror) {
                Button {
                    go(.done)
                } label: {
                    Text(verbatim: "Дальше")
                }
                .buttonStyle(KPSheetButtonStyle(primary: true))
                .padding(.top, 14)
                .transition(.opacity)
            }

            Button {
                go(.welcome)
            } label: {
                Text(verbatim: "Назад")
            }
            .buttonStyle(KPSheetButtonStyle())
            .padding(.top, SiteAddress.isConfigured(mirror) ? 10 : 14)
        }
        .animation(.snappy(duration: 0.2), value: SiteAddress.isConfigured(mirror))
    }

    private var doneMessage: String {
        switch verified {
        case true?: "Сайт отвечает, адрес сохранён."
        case false?: "Адрес сохранён. Если страницы не откроются, проверьте адрес в настройках."
        case nil: "Адрес сайта указан. Если страницы не откроются, проверьте адрес в настройках."
        }
    }

    private var done: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(KP.good)
                .frame(width: 58, height: 58)
                .background(Circle().fill(KP.good.opacity(0.14)))

            Text(verbatim: "Всё готово")
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)
                .padding(.top, 16)

            Text(verbatim: doneMessage)
                .font(KP.font(14, .medium))
                .foregroundStyle(KP.fg70)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(verbatim: "Войдите в аккаунт сайта, чтобы видеть закладки, «Продолжить просмотр» и новые серии. Или сделайте это позже: кнопка «Войти» в верхней панели.")
                .font(KP.font(13.5))
                .foregroundStyle(KP.fg55)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
                .padding(.top, 14)

            Spacer(minLength: 20)

            Button {
                finish(true)
            } label: {
                Text(verbatim: "Войти")
            }
            .buttonStyle(KPSheetButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)

            Button {
                finish(false)
            } label: {
                Text(verbatim: "Позже")
            }
            .buttonStyle(KPSheetButtonStyle())
            .padding(.top, 10)
        }
    }
}

/// Where the first-run screen is: a dot per step, the current one a white bar.
private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? KP.fg : index < current ? KP.fg38 : KP.chipStrong)
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}
