import AppKit
import Combine
import Sparkle
import SwiftUI

/// The version in use, «Проверить сейчас», and Sparkle's own preferences (automatic checks, how often, automatic
/// installs). Everything reads and writes the updater directly, so it's right before the updater starts too; until
/// then the button stays off.
struct UpdatesSettings: View {
    let updater: SPUUpdater

    @State private var automaticallyChecks: Bool
    @State private var automaticallyDownloads: Bool
    @State private var interval: UpdateInterval
    @State private var lastCheck: Date?
    @State private var canCheck = false

    init(updater: SPUUpdater) {
        self.updater = updater

        _automaticallyChecks = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloads = State(initialValue: updater.automaticallyDownloadsUpdates)
        _interval = State(initialValue: Self.nearest(to: updater.updateCheckInterval))
        _lastCheck = State(initialValue: updater.lastUpdateCheckDate)
    }

    var body: some View {
        SettingsGroup {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(AppInfo.name) \(AppInfo.version)")
                        .font(KP.font(16, .bold))
                        .foregroundStyle(KP.fg)

                    Text(verbatim: "Сборка \(AppInfo.build) · \(lastCheckText)")
                        .font(KP.font(12.5, .medium).monospacedDigit())
                        .foregroundStyle(KP.fg55)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                UpdateButton(updater: updater, title: "Проверить сейчас")
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .opacity(canCheck ? 1 : 0.45)
            }
            .padding(16)
        }

        SettingsGroup(title: "Автоматически", footer: footnote) {
            SettingsToggle(title: "Проверять обновления", subtitle: "В фоне, без лишних окон: о новой версии скажет уведомление", isOn: $automaticallyChecks)

            SettingsRow(title: "Как часто") {
                Picker(selection: $interval) {
                    ForEach(UpdateInterval.allCases) { interval in
                        Text(interval.localizedKey)
                            .tag(interval)
                    }
                } label: {
                    Text(verbatim: "Как часто")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .disabled(!automaticallyChecks)
            .opacity(automaticallyChecks ? 1 : 0.45)

            SettingsToggle(title: "Скачивать и ставить сами", subtitle: "Новая версия установится при следующем запуске", isOn: $automaticallyDownloads)
                .disabled(!automaticallyChecks || !updater.allowsAutomaticUpdates)
                .opacity(automaticallyChecks && updater.allowsAutomaticUpdates ? 1 : 0.45)
        }
        .animation(.snappy(duration: 0.2), value: automaticallyChecks)
        .onChange(of: automaticallyChecks) {
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
        .onChange(of: automaticallyDownloads) {
            updater.automaticallyDownloadsUpdates = automaticallyDownloads
        }
        .onChange(of: interval) {
            updater.updateCheckInterval = interval.rawValue
        }
        .onReceive(updater.publisher(for: \.lastUpdateCheckDate).receive(on: DispatchQueue.main)) { date in
            lastCheck = date
        }
        .onReceive(updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)) { canCheck in
            self.canCheck = canCheck
        }

        if AppLinks.isSet(AppLinks.releases) {
            Link(destination: AppLinks.releases) {
                Label {
                    Text(verbatim: "Все версии и что в них нового")
                } icon: {
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(KPSecondaryButtonStyle(size: 13))
        }
    }

    /// «проверено вчера», «ещё не проверялось».
    private var lastCheckText: String {
        guard let lastCheck else { return "ещё не проверялось" }

        return "проверено \(lastCheck.formatted(.relative(presentation: .named).locale(Locale(identifier: "ru_RU"))))"
    }

    /// Follows AppUpdates: the updater runs only in a Release build with the real feed and key.
    private var footnote: String {
        #if DEBUG
            return "В отладочной сборке обновления не проверяются."
        #else
            if AppUpdates.isConfigured {
                return "Обновления скачиваются с GitHub и проверяются цифровой подписью перед установкой."
            }

            return "Автообновление заработает с первым публичным релизом."
        #endif
    }

    /// Sparkle keeps any interval in seconds; the picker shows the closest of its four.
    private static func nearest(to seconds: TimeInterval) -> UpdateInterval {
        UpdateInterval.allCases.min { abs($0.rawValue - seconds) < abs($1.rawValue - seconds) } ?? .daily
    }
}
