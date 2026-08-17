import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            dashboardToolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatusBannerView()
                    if app.operationState == .conflict {
                        ConflictFilesPanelView()
                    }
                    OverviewCardsView()
                    HStack(alignment: .top, spacing: 18) {
                        ChangesPanelView()
                            .frame(maxWidth: .infinity)
                        RepositoryInfoPanelView()
                            .frame(width: 285)
                    }
                    RecentActivityPanelView()
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $app.showLogs) { LogsView() }
        .sheet(isPresented: $app.showAddRemote) { AddRemoteSheet() }
        .sheet(isPresented: $app.showPushConfirmation) { PushConfirmationSheet() }
        .alert(item: $app.activeError) { error in
            let message = [error.message, error.recovery].compactMap { $0 }.joined(separator: "\n\n")
            return Alert(
                title: Text(error.title),
                message: Text(message),
                primaryButton: error.technicalDetails == nil ? .default(Text("OK")) : .default(Text("View Logs")) {
                    if error.technicalDetails != nil { app.showLogs = true }
                },
                secondaryButton: .cancel(Text("Dismiss"))
            )
        }
        .confirmationDialog("Abort current rebase?", isPresented: $app.showAbortConfirmation, titleVisibility: .visible) {
            Button("Abort Rebase", role: .destructive) { app.abortRebase() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops the rebase and leaves your local commits and files in place.")
        }
    }

    private var dashboardToolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Text(app.selectedRepository?.name ?? "Repository")
                    .font(.headline)
                Text("/")
                    .foregroundStyle(.tertiary)
                Text("Dashboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(title: "Refresh", systemImage: "arrow.clockwise") { Task { await app.refreshSelected() } }
            IconButton(title: "Open in Finder", systemImage: "folder") { app.openFinder() }
            IconButton(title: "Open in Terminal", systemImage: "terminal") { app.openTerminal() }
            IconButton(title: "Show Logs", systemImage: "list.bullet.rectangle") { app.showRepositoryLogs() }
            Divider().frame(height: 18)
            Button {
                app.requestSync()
            } label: {
                Label(app.isBusy ? "Syncing…" : app.retryPushAvailable ? "Retry Push" : "Sync & Push", systemImage: app.isBusy ? "arrow.triangle.2.circlepath" : "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(PushDockPalette.accent)
            .disabled(app.isBusy || app.status?.isDetachedHead == true || app.status?.isRebasing == true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(PushDockPalette.card)
        .overlay(alignment: .bottom) { Rectangle().fill(PushDockPalette.separator).frame(height: 1) }
    }
}

struct StatusBannerView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.16))
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.status?.isDetachedHead == true {
                StatusPill(title: "Detached HEAD", color: .orange, systemImage: "exclamationmark.triangle")
            } else if app.operationState == .conflict {
                Button("Open Logs") { app.showRepositoryLogs() }
                    .buttonStyle(.bordered)
                Button("Abort Rebase") { app.confirmAbortRebase() }
                    .buttonStyle(.bordered)
            } else if app.retryPushAvailable {
                Button("Retry Push") { app.retryPush() }
                    .buttonStyle(.borderedProminent)
                    .tint(PushDockPalette.accent)
            }
        }
        .padding(18)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(iconColor.opacity(0.15)))
    }

    private var title: String {
        if app.operationState == .conflict { return "Action required" }
        if app.status?.isDetachedHead == true { return "Detached HEAD" }
        if app.status?.hasRemoteChanges == true { return "Remote changes detected" }
        if app.status?.hasLocalWork == true { return "Local changes detected" }
        if app.status?.ahead ?? 0 > 0 { return "Ready to push" }
        if app.operationState == .success { return app.successMessage ?? "Everything is up to date" }
        return "Repository is ready"
    }

    private var subtitle: String {
        if app.operationState == .conflict { return "Resolve the conflicted files before pushing anything else." }
        if app.status?.isDetachedHead == true { return "Switch to a branch before pushing." }
        if app.status?.hasRemoteChanges == true { return "The remote has commits that need to be rebased locally." }
        if app.status?.hasLocalWork == true { return "Review your changes and sync them to GitHub." }
        return app.successMessage ?? "Your local Git repository is ready to work."
    }

    private var icon: String {
        if app.operationState == .conflict || app.status?.isDetachedHead == true { return "exclamationmark.triangle.fill" }
        if app.status?.hasLocalWork == true || app.status?.ahead ?? 0 > 0 { return "arrow.up.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var iconColor: Color {
        if app.operationState == .conflict || app.status?.isDetachedHead == true { return .orange }
        if app.status?.hasLocalWork == true || app.status?.ahead ?? 0 > 0 { return PushDockPalette.accent }
        return .green
    }

    private var background: Color { iconColor.opacity(0.07) }
}

struct OverviewCardsView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            OverviewCard(title: "Repository", value: app.selectedRepository?.name ?? "—", systemImage: "folder")
            OverviewCard(title: "Branch", value: app.status?.branch ?? "Detached HEAD", systemImage: "arrow.branch")
            OverviewCard(title: "Changes", value: "\(app.status?.changes.count ?? 0) files", systemImage: "doc.on.doc")
            OverviewCard(title: "Sync", value: syncValue, systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private var syncValue: String {
        guard let status = app.status else { return "Reading…" }
        if status.ahead == 0 && status.behind == 0 { return "Up to date" }
        let values = [status.ahead > 0 ? "\(status.ahead) ahead" : nil, status.behind > 0 ? "\(status.behind) behind" : nil].compactMap { $0 }
        return values.joined(separator: " · ")
    }
}

struct OverviewCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        DashboardCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                    Text(value)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: systemImage)
                    .foregroundStyle(PushDockPalette.accent)
            }
        }
    }
}
