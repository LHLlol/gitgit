import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var app: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showTechnical = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Execution Log")
                        .font(.title3.weight(.semibold))
                    Text(app.selectedRepository?.name ?? "Repository")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Technical details", isOn: $showTechnical)
                    .toggleStyle(.checkbox)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(PushDockPalette.accent)
            }
            .padding(18)
            Divider()
            if visibleLogs.isEmpty {
                EmptyStateView(title: "No logs yet", message: "Run Refresh or Sync & Push to see execution details.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLogs) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: item))
                                    .foregroundStyle(color(for: item))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(item.isTechnical ? .system(.caption, design: .monospaced) : .subheadline.weight(.medium))
                                    if let detail = item.detail {
                                        Text(detail)
                                            .font(item.isTechnical ? .system(.caption2, design: .monospaced) : .caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer()
                                Text(item.timestamp.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .frame(width: 720, height: 520)
    }

    private var visibleLogs: [GitOperationLog] {
        app.logs.filter { showTechnical || !$0.isTechnical }
    }

    private func icon(for log: GitOperationLog) -> String {
        if log.isTechnical { return "chevron.left.forwardslash.chevron.right" }
        if log.isSuccess == true { return "checkmark.circle.fill" }
        if log.isSuccess == false { return "exclamationmark.circle.fill" }
        return "circle.fill"
    }

    private func color(for log: GitOperationLog) -> Color {
        if log.isSuccess == true { return .green }
        if log.isSuccess == false { return .orange }
        return PushDockPalette.accent
    }
}
