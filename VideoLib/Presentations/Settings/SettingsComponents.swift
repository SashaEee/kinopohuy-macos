import SwiftUI

/// The Settings window's sections, in the sidebar's order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case player
    case recommendations
    case downloads
    case updates
    case data
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "Основное"
        case .player: "Плеер"
        case .recommendations: "Рекомендации"
        case .downloads: "Загрузки"
        case .updates: "Обновления"
        case .data: "Данные"
        case .about: "О программе"
        }
    }

    /// The line under the section's title.
    var subtitle: String {
        switch self {
        case .general: "Адрес сайта, аккаунт и вид приложения"
        case .player: "Как открывается, выглядит и звучит видео"
        case .recommendations: "Что советовать и как узнать ваш вкус. Всё хранится только на этом Mac"
        case .downloads: "Куда и сколько загружать одновременно"
        case .updates: "Новые версии приходят сами или по кнопке"
        case .data: "Кэш картинок, места просмотра и история"
        case .about: ""
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .player: "play.rectangle.fill"
        case .recommendations: "sparkles"
        case .downloads: "arrow.down.circle.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .data: "internaldrive.fill"
        case .about: "info.circle.fill"
        }
    }
}

// MARK: - Sidebar

/// The sections down the left: the chosen one on a light chip with its icon in a white square (the app's "chosen is
/// white"), ⌘1…⌘7 to jump between them.
struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(.kinoPohuySun)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Настройки")
                        .font(KP.font(15, .bold))
                        .foregroundStyle(KP.fg)
                    Text(verbatim: AppInfo.name)
                        .font(KP.font(12, .medium))
                        .foregroundStyle(KP.fg38)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)

            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element) { index, section in
                SettingsSidebarItem(section: section, selected: selection == section) {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = section
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Spacer(minLength: 16)

            Text(verbatim: AppInfo.versionLine)
                .font(KP.font(11.5, .medium).monospacedDigit())
                .foregroundStyle(KP.fg38)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 52) // under the traffic lights
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KP.ink)
    }
}

private struct SettingsSidebarItem: View {
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? KP.ink : KP.fg80)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? KP.fg : KP.chip))

                Text(verbatim: section.title)
                    .font(KP.font(13.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? KP.fg : KP.fg70)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? KP.chip : hover ? KP.chip.opacity(0.5) : .clear)
            )
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}

// MARK: - Cards and rows

/// A group of settings on a rounded card, with a quiet heading above it and a footnote below; its rows are split by
/// hairlines.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(verbatim: title)
                    .font(KP.font(12, .semibold))
                    .foregroundStyle(KP.fg55)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                Group(subviews: content()) { rows in
                    ForEach(rows) { row in
                        row

                        if row.id != rows.last?.id {
                            Rectangle()
                                .fill(KP.line)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .background(KP.chip.opacity(0.4), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(KP.line, in: .rect(cornerRadius: 12, style: .continuous).stroke(lineWidth: 1))

            if let footer {
                Text(verbatim: footer)
                    .font(KP.font(12))
                    .foregroundStyle(KP.fg38)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// One setting: its name and a quieter line saying what it does on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(KP.font(13.5, .medium))
                    .foregroundStyle(KP.fg)

                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(KP.font(12))
                        .foregroundStyle(KP.fg55)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

/// An on/off setting.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(isOn: $isOn) {
                Text(verbatim: title)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

/// A short line with an icon under a field: what a check found (green), what's wrong (red), or a hint.
struct SettingsStatusLine: View {
    enum Tone {
        case quiet, good, warning, bad
    }

    let text: String
    var symbol: String?
    var tone: Tone = .quiet

    private var color: Color {
        switch tone {
        case .quiet: KP.fg55
        case .good: KP.good
        case .warning: KP.sun
        case .bad: KP.bad
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
            }

            Text(verbatim: text)
                .font(KP.font(12.5, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }
}
