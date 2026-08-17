import Foundation

enum AppearancePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var defaultRemote = "origin"
    var defaultCommitTemplate = "Update {repository}"
    var fetchBeforeSync = true
    var confirmBeforePush = true
    var automaticallyAddDSStore = false
    var appearance: AppearancePreference = .system

    private static let storageKey = "PushDock.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func commitMessage(for repositoryName: String) -> String {
        defaultCommitTemplate.replacingOccurrences(of: "{repository}", with: repositoryName)
    }
}
