import SwiftUI
import UniformTypeIdentifiers

struct RepositoryDropView: View {
    @EnvironmentObject private var app: AppViewModel
    @Binding var isTargeted: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Text("Push your project without Terminal.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Drop a local Git repository to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isTargeted ? PushDockPalette.accent : .secondary)
                    .scaleEffect(isTargeted ? 1.03 : 1)
                Text("Drop Repository Here")
                    .font(.headline)
                Text("Drag a Git project from Finder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Rectangle().fill(PushDockPalette.separator).frame(width: 46, height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Rectangle().fill(PushDockPalette.separator).frame(width: 46, height: 1)
                }
                Button("Choose Folder") { app.chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .tint(PushDockPalette.accent)
            }
            .frame(width: 360, height: 250)
            .background(PushDockPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isTargeted ? PushDockPalette.accent : PushDockPalette.separator, lineWidth: isTargeted ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
            .animation(.easeInOut(duration: 0.18), value: isTargeted)

            Text("Your files stay on your Mac. Git operations use your existing local Git configuration.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else if let value = item as? NSURL { url = value as URL }
                else { url = nil }
                if let url { DispatchQueue.main.async { app.importFolder(url) } }
            }
            return true
        }
    }
}
