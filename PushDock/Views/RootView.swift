import SwiftUI
import UniformTypeIdentifiers

enum SidebarSection: Hashable {
    case dashboard
    case activity
    case settings
}

struct RootView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: SidebarSection = .dashboard
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section)
                .frame(width: 226)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PushDockPalette.background)
        }
        .frame(minWidth: 960, minHeight: 640)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await app.refreshSelected(fetch: false) } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dashboard:
            if app.hasSelectedRepository { DashboardView() }
            else { RepositoryDropView(isTargeted: $dropTargeted) }
        case .activity:
            ActivityPageView()
        case .settings:
            SettingsView()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let value = item as? URL { url = value }
            else if let value = item as? NSURL { url = value as URL }
            else { url = nil }
            guard let url else { return }
            DispatchQueue.main.async { app.importFolder(url) }
        }
        return true
    }
}
