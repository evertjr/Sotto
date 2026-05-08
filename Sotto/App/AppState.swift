import Foundation

enum SettingsTab: String, Hashable {
    case general
    case hotkey
    case model
    case ai
    case history
    case about
}

@Observable
@MainActor
final class AppState {
    var settingsTab: SettingsTab = .general
}
