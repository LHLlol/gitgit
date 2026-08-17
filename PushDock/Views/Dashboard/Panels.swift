import SwiftUI

struct ChangesPanelView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Changes", trailing: "All changes will be included")
                if app.status?.changes.contains(where: { $0.file == ".DS_Store" }) == true {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(".DS_Store detected").font(.subheadline.weight(.medium))
                            Text("Consider adding it to .gitignore.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add to .gitignore") { app.addDSStoreToGitignore() }
                            .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                if let changes = app.status?.changes, !changes.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(changes) { change in
                            ChangeRow(change: change)
                            if change.id != changes.last?.id { Divider().padding(.leading, 34) }
                        }
                    }
                } else if app.status == nil {
                    HStack { ProgressView().controlSize(.small); Text("Reading repository status…").font(.subheadline).foregroundStyle(.secondary) }
                        .padding(.vertical, 24)
                } else {
                    EmptyStateView(title: "Working tree clean", message: "No local changes need to be committed.")
                        .frame(height: 160)
                }
            }
        }
    }
}

struct ConflictFilesPanelView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Rebase conflict", trailing: "PushDock stopped safely")
                Text("Resolve these files manually, then refresh the repository. Nothing will be pushed while the conflict remains.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if app.conflictFiles.isEmpty {
                    Text("Git reported a conflict, but did not provide a file list. Open Logs for technical details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.conflictFiles, id: \.self) { file in
                        Label(file, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct ChangeRow: View {
    let change: GitChange

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: change.status.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(change.file)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(change.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(change.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.file), \(change.status.label)")
    }

    private var color: Color {
        switch change.status {
        case .deleted, .conflicted: return .orange
        case .added, .untracked: return .green
        case .renamed: return .blue
        case .modified: return PushDockPalette.accent
        }
    }
}

struct RepositoryInfoPanelView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(title: "Repository")
                InfoLine(title: "Remote", value: RemoteURLParser.displayName(from: app.selectedRepository?.remoteURL))
                InfoLine(title: "Branch", value: app.status?.branch ?? "Detached HEAD")
                InfoLine(title: "Path", value: app.selectedRepository?.path ?? "—", isPath: true)
                InfoLine(title: "Last commit", value: app.selectedRepository?.lastCommitMessage ?? "No local app history")
                InfoLine(title: "Last sync", value: lastSync)
                if app.selectedRepository?.remoteURL == nil {
                    Button("Add Remote") { app.showAddRemote = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var lastSync: String {
        guard let date = app.selectedRepository?.lastPush else { return "Not yet" }
        return date.formatted(.relative(presentation: .named))
    }
}

struct InfoLine: View {
    let title: String
    let value: String
    var isPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(isPath ? .caption : .subheadline)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

struct RecentActivityPanelView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(title: "Recent Activity", trailing: app.activities.isEmpty ? nil : "View all")
                let recent = app.activities.filter { $0.repositoryID == app.selectedRepositoryID }.prefix(4)
                if recent.isEmpty {
                    EmptyStateView(title: "No activity yet", message: "Your PushDock sync history will appear here.")
                        .frame(height: 92)
                } else {
                    ForEach(Array(recent)) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.result == "Success" ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(item.result == "Success" ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.commitMessage).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(item.result).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.timestamp.formatted(.dateTime.hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct ActivityPageView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Text("Local app history")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            Divider()
            if app.activities.isEmpty {
                EmptyStateView(title: "No activity yet", message: "Completed syncs will be saved locally on this Mac.")
            } else {
                List(app.activities) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.result == "Success" ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(item.result == "Success" ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.repositoryName).font(.subheadline.weight(.medium))
                            Text(item.commitMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }
        }
        .background(PushDockPalette.background)
    }
}

struct AddRemoteSheet: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Remote")
                .font(.title2.weight(.semibold))
            Text("Add a remote for \(app.selectedRepository?.name ?? "this repository"). PushDock will not contact GitHub until you sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("https://github.com/username/repository.git", text: $app.newRemoteURL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { app.showAddRemote = false }
                Button("Add Remote") { app.addRemote() }
                    .buttonStyle(.borderedProminent)
                    .tint(PushDockPalette.accent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct PushConfirmationSheet: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review before push")
                .font(.title2.weight(.semibold))
            if let repository = app.selectedRepository {
                VStack(alignment: .leading, spacing: 10) {
                    InfoLine(title: "Repository", value: repository.name)
                    InfoLine(title: "Branch", value: app.status?.branch ?? "Detached HEAD")
                    InfoLine(title: "Changes", value: "\(app.status?.changes.count ?? 0) files")
                    InfoLine(title: "Commit", value: app.commitMessage)
                    InfoLine(title: "Remote", value: repository.remoteName ?? "Not configured")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { app.showPushConfirmation = false }
                Button("Sync & Push") { app.performSync() }
                    .buttonStyle(.borderedProminent)
                    .tint(PushDockPalette.accent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
