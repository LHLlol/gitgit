import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("PushDock uses your existing local Git configuration and stores data only on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsSection(title: "Git", systemImage: "terminal") {
                    SettingsRow(title: "Default remote", detail: "Used when a repository has no configured remote name.") {
                        TextField("origin", text: settingBinding(\.defaultRemote))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }

                SettingsSection(title: "Commit", systemImage: "text.badge.checkmark") {
                    SettingsRow(title: "Default commit template", detail: "Use {repository} to insert the repository name.") {
                        TextField("Update {repository}", text: settingBinding(\.defaultCommitTemplate))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                SettingsSection(title: "Behaviour", systemImage: "slider.horizontal.3") {
                    Toggle("Fetch before sync", isOn: settingBinding(\.fetchBeforeSync))
                    Toggle("Review before push", isOn: settingBinding(\.confirmBeforePush))
                    Toggle("Automatically add .DS_Store to .gitignore", isOn: settingBinding(\.automaticallyAddDSStore))
                    Text("The last option is off by default and never edits .gitignore without your explicit setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsSection(title: "Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Theme", selection: settingBinding(\.appearance)) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSection(title: "Privacy", systemImage: "lock.shield") {
                    Text("PushDock does not upload project files, use GitHub OAuth, store tokens, collect analytics, or send crash reports. Repository paths, settings, and activity history remain local.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(PushDockPalette.background)
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { app.settings[keyPath: keyPath] },
            set: { app.settings[keyPath: keyPath] = $0 }
        )
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                content
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    let control: Control

    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}
