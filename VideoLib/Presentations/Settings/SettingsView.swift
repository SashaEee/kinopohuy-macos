import Sparkle
import SwiftUI

/// Settings, in the app's dark look: the sections down a sidebar on the left, the chosen one's cards on the right
/// (scrolled back to the top on each switch). The window can be resized; the cards keep a readable width.
struct SettingsView: View {
    let updater: SPUUpdater

    @Bindable private var ui = AppUI.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $ui.settingsSection)
                .frame(width: 216)

            Rectangle()
                .fill(KP.line)
                .frame(width: 1)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    if !ui.settingsSection.subtitle.isEmpty {
                        header
                    }

                    content
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
            .id(ui.settingsSection)
            .scrollIndicators(.automatic, axes: .vertical)
            .viewModifier { view in
                if #available(macOS 26, *) {
                    view.scrollEdgeEffectStyle(.soft, for: .top)
                } else {
                    view
                }
            }
        }
        .frame(minWidth: 780, idealWidth: 880, maxWidth: 1240, minHeight: 540, idealHeight: 660, maxHeight: .infinity)
        .background(KP.bg)
        .ignoresSafeArea()
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .containerBackground(KP.bg, for: .window)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: ui.settingsSection.title)
                .font(KP.font(26, .heavy))
                .tracking(-0.5)
                .foregroundStyle(KP.fg)

            Text(verbatim: ui.settingsSection.subtitle)
                .font(KP.font(13.5, .medium))
                .foregroundStyle(KP.fg55)
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch ui.settingsSection {
        case .general:
            GeneralSettings()
        case .player:
            PlayerSettings()
        case .downloads:
            DownloadsSettings()
        case .updates:
            UpdatesSettings(updater: updater)
        case .data:
            DataSettings()
        case .about:
            AboutSettings()
        }
    }
}
