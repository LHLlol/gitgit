import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppViewModel
    @Binding var section: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PushDockPalette.accent)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                Text("PushDock")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)

            Text("REPOSITORIES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.7)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(app.repositories) { repository in
                        RepositoryRow(repository: repository, isSelected: repository.id == app.selectedRepositoryID) {
                            app.selectRepository(repository)
                            section = .dashboard
                        }
                        .contextMenu {
                            Button("Open") { app.selectRepository(repository); section = .dashboard }
                            Button("Open in Finder") {
                                app.selectRepository(repository)
                                app.openFinder()
                            }
                            Button("Open in Terminal") {
                                app.selectRepository(repository)
                                app.openTerminal()
                            }
                            Divider()
                            Button("Remove from Sidebar", role: .destructive) { app.removeRepository(repository) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("GENERAL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.7)
                    .padding(.bottom, 4)
                SidebarItem(title: "Dashboard", systemImage: "rectangle.3.group", isSelected: section == .dashboard) { section = .dashboard }
                SidebarItem(title: "Activity", systemImage: "clock.arrow.circlepath", isSelected: section == .activity) { section = .activity }
                SidebarItem(title: "Settings", systemImage: "gearshape", isSelected: section == .settings) { section = .settings }
            }
            .padding(.horizontal, 10)

            Divider().padding(.top, 18)

            HStack(spacing: 10) {
                Circle()
                    .fill(PushDockPalette.accent)
                    .frame(width: 28, height: 28)
                    .overlay(Text(initials).font(.caption2.weight(.bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.selectedRepository?.gitUserName ?? "Git user")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(app.selectedRepository?.gitUserEmail ?? "Configure git user")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .background(PushDockPalette.card)
    }

    private var initials: String {
        let name = app.selectedRepository?.gitUserName ?? "G"
        return String(name.split(separator: " ").prefix(2).compactMap { $0.first })
    }
}

struct SidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? PushDockPalette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct RepositoryRow: View {
    let repository: Repository
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isSelected ? PushDockPalette.accent : Color.green)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(repository.branch ?? "Detached HEAD")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? PushDockPalette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
