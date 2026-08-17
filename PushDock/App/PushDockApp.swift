import SwiftUI

@main
struct PushDockApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Repository…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Refresh") { Task { await model.refreshSelected() } }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Sync & Push") { model.requestSync() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Show Logs") { model.showRepositoryLogs() }
                    .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
