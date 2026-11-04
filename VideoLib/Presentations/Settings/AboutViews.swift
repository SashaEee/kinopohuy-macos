import AppKit
import CoreImage.CIFilterBuiltins
import Defaults
import SwiftUI

// MARK: - Pieces shared by the About window and Settings → «О программе»

/// The icon with a warm glow, «КиноПохуй», the version, what the app is, the copyright.
struct AboutHero: View {
    var iconSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [KP.sun.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: iconSize * 0.95))
                        .frame(width: iconSize * 1.9, height: iconSize * 1.9)
                }

            KPLogo(height: 26)
                .padding(.top, 2)

            Text(verbatim: AppInfo.versionLine)
                .font(KP.font(12.5, .medium).monospacedDigit())
                .foregroundStyle(KP.fg55)
                .textSelection(.enabled)

            Text(verbatim: AppInfo.summary)
                .font(KP.font(13))
                .foregroundStyle(KP.fg70)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .padding(.top, 4)

            Text(verbatim: AppInfo.copyright)
                .font(KP.font(11.5, .medium))
                .foregroundStyle(KP.fg38)
        }
    }
}

/// The project's links that are filled in (`AppLinks`): source code, the Telegram channel, the issue tracker.
struct AboutLinks: View {
    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let url: URL
    }

    private var items: [Item] {
        [
            Item(id: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: AppLinks.repository),
            Item(id: "Telegram", symbol: "paperplane.fill", url: AppLinks.telegram),
            Item(id: "Сообщить о проблеме", symbol: "exclamationmark.bubble.fill", url: AppLinks.issues),
        ]
        .filter { AppLinks.isSet($0.url) }
    }

    static var isAvailable: Bool {
        [AppLinks.repository, AppLinks.telegram, AppLinks.issues].contains(where: AppLinks.isSet)
    }

    var body: some View {
        // One row when it fits; in a narrow window the third link goes under the first two.
        ViewThatFits(in: .horizontal) {
            row(items)

            VStack(spacing: 8) {
                row(Array(items.prefix(2)))
                row(Array(items.dropFirst(2)))
            }
        }
    }

    private func row(_ items: [Item]) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Link(destination: item.url) {
                    Label {
                        Text(verbatim: item.id)
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
                .help(item.url.absoluteString)
            }
        }
    }
}

/// «© 2025 voidboost, MIT»: the notice the license asks to keep, as plain text.
struct UpstreamCredit: View {
    var body: some View {
        Text(verbatim: AppInfo.upstreamCredit)
            .font(KP.font(11.5, .medium))
            .foregroundStyle(KP.fg38)
            .textSelection(.enabled)
    }
}

// MARK: - Donations

/// The donation options that are filled in (`AppLinks`), in the order they're shown.
enum Donations {
    struct Option: Identifiable {
        let id: String
        let symbol: String
        let url: URL
        /// How it works, on hover: whether it needs an account.
        let help: String
    }

    struct Wallet: Identifiable {
        let id: String
        let address: String
        /// What the address takes, under its QR code: a coin sent on another network is lost.
        let note: String
        /// A Bybit UID is typed into Bybit's transfer form, not scanned: it gets no QR code.
        var hasQR = true
    }

    /// The card first: it needs no account, while Boosty asks to sign in before a tip.
    static var options: [Option] {
        [
            Option(id: "Картой или СБП", symbol: "creditcard.fill", url: AppLinks.cloudtips,
                   help: "Через CloudTips: любой картой или по СБП, без регистрации"),
            Option(id: "Boosty", symbol: "heart.fill", url: AppLinks.boosty,
                   help: "Разово или подпиской, нужен аккаунт Boosty"),
            Option(id: "ЮMoney", symbol: "rublesign.circle.fill", url: AppLinks.yoomoney,
                   help: "Картой или из кошелька ЮMoney"),
        ]
        .filter { AppLinks.isSet($0.url) }
    }

    static var wallets: [Wallet] {
        [
            Wallet(id: "USDT · TON", address: AppLinks.cryptoUSDT, note: "Только USDT в сети TON"),
            Wallet(id: "Bybit · UID", address: AppLinks.bybitUID, note: "Перевод по UID внутри Bybit, без комиссии",
                   hasQR: false),
            Wallet(id: "BTC", address: AppLinks.cryptoBTC, note: "Только BTC в сети Bitcoin"),
        ]
        .filter { AppLinks.isSet($0.address) }
    }

    /// Whether there's anything to show under «Поддержать проект».
    static var isAvailable: Bool {
        !options.isEmpty || !wallets.isEmpty
    }
}

/// «Поддержать проект»: a thank-you, never a paywall. The links open in the browser; a wallet's address is copied or
/// shown as a QR code.
struct SupportProjectCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KP.sun)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(KP.sun.opacity(0.14)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Поддержать проект")
                        .font(KP.font(16, .bold))
                        .foregroundStyle(KP.fg)

                    Text(verbatim: "КиноПохуй — открытый проект, и все функции доступны всем. Донат — просто спасибо: он пойдёт на сертификат Apple, чтобы приложение открывалось без лишних шагов, и на новые функции.")
                        .font(KP.font(12.5))
                        .foregroundStyle(KP.fg55)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !Donations.options.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Donations.options) { option in
                        Link(destination: option.url) {
                            Label {
                                Text(verbatim: option.id)
                            } icon: {
                                Image(systemName: option.symbol)
                            }
                        }
                        .buttonStyle(KPSecondaryButtonStyle(size: 13))
                        .help(option.help)
                    }
                }
            }

            if !Donations.wallets.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Donations.wallets) { wallet in
                        WalletRow(wallet: wallet)

                        if wallet.id != Donations.wallets.last?.id {
                            Rectangle()
                                .fill(KP.line)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(KP.bg.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
                .overlay(KP.line, in: .rect(cornerRadius: 10, style: .continuous).stroke(lineWidth: 1))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KP.chip.opacity(0.4))
                .overlay {
                    // A faint warmth from the top left corner, the heart's side.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(RadialGradient(colors: [KP.sun.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 320))
                }
        }
        .overlay(KP.line, in: .rect(cornerRadius: 14, style: .continuous).stroke(lineWidth: 1))
    }
}

/// A wallet: its network, the address in the middle (cut in the middle if long), «Скопировать» and a QR code.
private struct WalletRow: View {
    let wallet: Donations.Wallet

    @State private var copied = false
    @State private var showQR = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: wallet.id)
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.fg70)
                .frame(width: 104, alignment: .leading)
                .help(wallet.note)

            Text(verbatim: wallet.address)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(KP.fg)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(wallet.address, forType: .string)

                withAnimation(.snappy) {
                    copied = true
                }

                Task {
                    try? await Task.sleep(for: .seconds(1.6))

                    withAnimation(.snappy) {
                        copied = false
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(KPIconButtonStyle(diameter: 28))
            .help(copied ? "Скопировано" : wallet.hasQR ? "Скопировать адрес" : "Скопировать UID")

            if wallet.hasQR {
                Button {
                    showQR.toggle()
                } label: {
                    Image(systemName: "qrcode")
                }
                .buttonStyle(KPIconButtonStyle(diameter: 28))
                .help("Показать QR-код")
                .popover(isPresented: $showQR, arrowEdge: .bottom) {
                    QRCodeView(text: wallet.address, caption: wallet.note)
                }
            }
        }
        .frame(height: 44)
    }
}

/// A QR code of a wallet's address on white, for a phone's camera.
private struct QRCodeView: View {
    let text: String
    let caption: String

    var body: some View {
        VStack(spacing: 10) {
            if let image = Self.image(for: text) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .padding(12)
                    .background(Color.white, in: .rect(cornerRadius: 12, style: .continuous))
            }

            Text(verbatim: caption)
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.fg70)
        }
        .padding(16)
    }

    private static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }

        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)

        return image
    }
}

// MARK: - Settings → «О программе»

/// The About page inside Settings: the hero, the links, donations, the disclaimer and licenses, the credit.
struct AboutSettings: View {
    @Environment(\.openWindow) private var openWindow

    @State private var showDisclaimer = false

    var body: some View {
        VStack(spacing: 22) {
            AboutHero(iconSize: 88)
                .padding(.top, 8)

            if AboutLinks.isAvailable {
                AboutLinks()
            }
        }
        .frame(maxWidth: .infinity)

        if Donations.isAvailable {
            SupportProjectCard()
        }

        SettingsGroup {
            SettingsRow(title: "Отказ от ответственности", subtitle: "Что приложение делает и чего не делает") {
                Button {
                    showDisclaimer = true
                } label: {
                    Text(verbatim: "Открыть")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }

            SettingsRow(title: "Лицензии", subtitle: "Открытые библиотеки, на которых собрано приложение") {
                Button {
                    openWindow(id: Windows.licenses.id)
                } label: {
                    Text(verbatim: "Открыть")
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerSheetView()
        }

        UpstreamCredit()
            .frame(maxWidth: .infinity)
    }
}

// MARK: - The About window

/// «О программе «КиноПохуй»»: a small window of its own in place of the standard panel.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 22) {
            AboutHero(iconSize: 104)

            if AboutLinks.isAvailable || Donations.isAvailable {
                VStack(spacing: 10) {
                    if AboutLinks.isAvailable {
                        AboutLinks()
                    }

                    if Donations.isAvailable {
                        Button {
                            AppUI.shared.settingsSection = .about
                            openSettings()
                        } label: {
                            Label {
                                Text(verbatim: "Поддержать проект")
                            } icon: {
                                Image(systemName: "heart.fill")
                            }
                        }
                        .buttonStyle(KPPrimaryButtonStyle(size: 13))
                    }
                }
            }

            VStack(spacing: 8) {
                Rectangle()
                    .fill(KP.line)
                    .frame(height: 1)
                    .padding(.bottom, 6)

                UpstreamCredit()

                Button {
                    openWindow(id: Windows.licenses.id)
                } label: {
                    Text(verbatim: "Лицензии")
                        .font(KP.font(11.5, .medium))
                        .foregroundStyle(KP.fg55)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 22)
        .frame(width: 460)
        .background(KP.bg)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Disclaimer

/// The disclaimer's points (the strings file keeps them as a Markdown list), each after a dot in the sun's colour.
struct DisclaimerPoints: View {
    var fontSize: CGFloat = 13.5

    private var points: [AttributedString] {
        String(localized: "key.disclaimer.description")
            .split(separator: "\n")
            .map { line in
                let text = line.trimmingCharacters(in: .whitespaces).replacing(/^[-•]\s*/, with: "")
                return (try? AttributedString(markdown: text)) ?? AttributedString(text)
            }
            .filter { !$0.characters.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "•")
                        .font(KP.font(fontSize, .heavy))
                        .foregroundStyle(KP.sun)

                    Text(point)
                        .font(KP.font(fontSize))
                        .foregroundStyle(KP.fg80)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Help → «Отказ от ответственности», and the same from Settings: the points and, once the site is set, its rules.
struct DisclaimerSheetView: View {
    @Default(.mirror) private var mirror

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        KPSheet(title: "Отказ от ответственности", symbol: "checkmark.shield.fill", width: 520) {
            DisclaimerPoints()
                .padding(16)
                .kpField()

            HStack(spacing: 10) {
                if SiteAddress.isConfigured(mirror) {
                    Link(destination: mirror.appending(path: "rules/", directoryHint: .notDirectory)) {
                        Text("key.site.rules")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(verbatim: "Понятно")
                }
                .buttonStyle(KPSheetButtonStyle(primary: true, width: 150))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }
}
