import Observation

/// What the menus ask the windows to show: the Settings section to open on («Поддержать проект» opens «О программе»)
/// and the disclaimer over the main window (Help → «Отказ от ответственности»).
@Observable
@MainActor
final class AppUI {
    static let shared = AppUI()

    var settingsSection: SettingsSection = .general
    var isDisclaimerPresented = false
}
