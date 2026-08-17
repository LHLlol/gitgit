import AppKit
import Combine
import Foundation

struct ErrorPresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recovery: String?
    let technicalDetails: String?
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var repositories: [Repository]
    @Published private(set) var activities: [ActivityItem]
    @Published var selectedRepositoryID: UUID?
    @Published private(set) var selectedRepository: Repository?
    @Published private(set) var status: GitStatus?
    @Published private(set) var operationState: GitOperationState = .idle
    @Published private(set) var logs: [GitOperationLog] = []
    @Published var commitMessage = ""
    @Published var activeError: ErrorPresentation?
    @Published var showPushConfirmation = false
    @Published var showAbortConfirmation = false
    @Published var showAddRemote = false
    @Published var newRemoteURL = ""
    @Published var showLogs = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var retryPushAvailable = false
    @Published private(set) var conflictFiles: [String] = []
    @Published private(set) var successMessage: String?

    @Published var settings: AppSettings {
        didSet { settings.save() }
    }

    let gitService: GitService
    private let bookmarkStore: BookmarkStore
    private let activityStore: ActivityStore
    private var selectedAccessURL: URL?

    init(
        gitService: GitService = GitService(),
        bookmarkStore: BookmarkStore = BookmarkStore(),
        activityStore: ActivityStore = ActivityStore()
    ) {
        self.gitService = gitService
        self.bookmarkStore = bookmarkStore
        self.activityStore = activityStore
        self.repositories = bookmarkStore.load()
        self.activities = activityStore.load()
        self.settings = AppSettings.load()
        self.selectedRepositoryID = repositories.first?.id
        if let selectedRepositoryID {
            self.selectedRepository = repositories.first(where: { $0.id == selectedRepositoryID })
            self.commitMessage = selectedRepository?.lastCommitMessage ?? settings.commitMessage(for: selectedRepository?.name ?? "Repository")
        }
        Task { [weak self] in
            await self?.refreshSelected(fetch: false)
        }
    }

    var isBusy: Bool {
        switch operationState {
        case .checking, .fetching, .staging, .committing, .rebasing, .pushing: return true
        default: return false
        }
    }

    var hasSelectedRepository: Bool { selectedRepository != nil }

    func selectRepository(_ repository: Repository) {
        guard !isBusy else { return }
        selectedRepositoryID = repository.id
        selectedRepository = repository
        status = nil
        successMessage = nil
        retryPushAvailable = false
        conflictFiles = []
        commitMessage = repository.lastCommitMessage ?? settings.commitMessage(for: repository.name)
        Task { [weak self] in await self?.refreshSelected(fetch: false) }
    }

    func importFolder(_ url: URL) {
        guard !isBusy else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let root = try await gitService.validateRepository(at: url)
                let bookmark = try? bookmarkStore.makeBookmark(for: root)
                let existing = repositories.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == root.standardizedFileURL })
                let snapshot = try await gitService.loadSnapshot(at: root, existing: existing)
                var repository = snapshot.repository
                repository.bookmarkData = bookmark
                repository.lastOpened = Date()
                if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                    repositories[index] = repository
                } else {
                    repositories.insert(repository, at: 0)
                }
                bookmarkStore.save(repositories)
                selectedRepositoryID = repository.id
                selectedRepository = repository
                status = snapshot.status
                commitMessage = repository.lastCommitMessage ?? settings.commitMessage(for: repository.name)
                appendLog("Repository detected", detail: root.path, isSuccess: true)
            } catch {
                present(error)
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Repository"
        if panel.runModal() == .OK, let url = panel.url {
            importFolder(url)
        }
    }

    func removeRepository(_ repository: Repository) {
        guard !isBusy else { return }
        repositories.removeAll { $0.id == repository.id }
        bookmarkStore.save(repositories)
        if selectedRepositoryID == repository.id {
            selectedRepositoryID = repositories.first?.id
            selectedRepository = repositories.first
            status = nil
            commitMessage = selectedRepository.map { $0.lastCommitMessage ?? settings.commitMessage(for: $0.name) } ?? ""
            if selectedRepository != nil { Task { [weak self] in await self?.refreshSelected(fetch: false) } }
        }
    }

    func refreshSelected(fetch: Bool = true) async {
        guard let repository = selectedRepository else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let url = try resolve(repository)
            if fetch, let remote = repository.remoteName, !remote.isEmpty {
                appendLog("Checking remote…")
                do {
                    try await gitService.fetch(at: url, remote: remote) { [weak self] text, isError in
                        Task { @MainActor in self?.appendTechnical(text, isError: isError) }
                    }
                } catch {
                    appendLog("Remote check unavailable", detail: "Local status was refreshed.\n\(error.localizedDescription)", isSuccess: false)
                }
            }
            let snapshot = try await gitService.loadSnapshot(at: url, existing: repository) { [weak self] text, isError in
                Task { @MainActor in self?.appendTechnical(text, isError: isError) }
            }
            apply(snapshot)
        } catch {
            present(error)
        }
    }

    func requestSync() {
        guard selectedRepository != nil, !isBusy else { return }
        guard !(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            present(GitAppError.invalidCommitMessage)
            return
        }
        if settings.confirmBeforePush {
            showPushConfirmation = true
        } else {
            performSync()
        }
    }

    func performSync() {
        guard let repository = selectedRepository, !isBusy else { return }
        showPushConfirmation = false
        operationState = .checking
        retryPushAvailable = false
        successMessage = nil
        logs = []
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try resolve(repository)
                let summary = try await gitService.sync(
                    at: url,
                    repository: repository,
                    message: message,
                    fetchBeforeSync: settings.fetchBeforeSync,
                    automaticallyAddDSStore: settings.automaticallyAddDSStore,
                    onProgress: { [weak self] state, message in
                        Task { @MainActor in
                            self?.operationState = state
                            self?.appendLog(message)
                        }
                    },
                    onOutput: { [weak self] text, isError in
                        Task { @MainActor in self?.appendTechnical(text, isError: isError) }
                    }
                )
                var updated = summary.repository
                updated.lastPush = summary.didPush ? Date() : repository.lastPush
                updated.lastCommitMessage = message
                updateRepository(updated)
                status = summary.status
                operationState = .success
                successMessage = summary.didPush ? "\(updated.name) has been pushed successfully." : "Everything is up to date."
                appendLog(summary.didPush ? "Push completed" : "Everything is up to date", detail: summary.didPush ? "\(updated.branch ?? "Branch") · \(updated.remoteName ?? "Remote")" : nil, isSuccess: true)
                activities.insert(ActivityItem(repositoryID: updated.id, repositoryName: updated.name, branch: updated.branch ?? "Detached", commitMessage: message, result: summary.didPush ? "Success" : "Up to date", commitHash: summary.commitHash, remote: updated.remoteName, duration: summary.duration, steps: summary.steps), at: 0)
                activityStore.save(activities)
            } catch {
                operationState = (error as? GitAppError)?.conflictFiles.isEmpty == false ? .conflict : .error
                if let gitError = error as? GitAppError {
                    retryPushAvailable = isRetryablePushError(gitError)
                    conflictFiles = gitError.conflictFiles
                }
                present(error)
                appendLog(error.localizedDescription, detail: (error as? GitAppError)?.recoverySuggestion, isSuccess: false)
            }
        }
    }

    func retryPush() {
        guard let repository = selectedRepository, retryPushAvailable, !isBusy else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try resolve(repository)
                let snapshot = try await gitService.loadSnapshot(at: url, existing: repository)
                guard let remote = snapshot.repository.remoteName, let branch = snapshot.status.branch else { throw GitAppError.remoteNotFound }
                operationState = .pushing
                appendLog("Retrying push…")
                try await gitService.push(at: url, remote: remote, branch: branch, setUpstream: snapshot.status.upstream == nil) { [weak self] text, isError in
                    Task { @MainActor in self?.appendTechnical(text, isError: isError) }
                }
                let updatedSnapshot = try await gitService.loadSnapshot(at: url, existing: repository)
                apply(updatedSnapshot)
                operationState = .success
                retryPushAvailable = false
                activeError = nil
                successMessage = "\(repository.name) has been pushed successfully."
                appendLog("Push completed", isSuccess: true)
            } catch {
                operationState = .error
                present(error)
            }
        }
    }

    func confirmAbortRebase() {
        showAbortConfirmation = true
    }

    func abortRebase() {
        guard let repository = selectedRepository else { return }
        showAbortConfirmation = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await gitService.abortRebase(at: resolve(repository)) { [weak self] text, isError in
                    Task { @MainActor in self?.appendTechnical(text, isError: isError) }
                }
                appendLog("Rebase aborted", isSuccess: true)
                await refreshSelected(fetch: false)
            } catch { present(error) }
        }
    }

    func addRemote() {
        guard let repository = selectedRepository else { return }
        let value = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        showAddRemote = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await gitService.addRemote(at: resolve(repository), name: settings.defaultRemote.isEmpty ? "origin" : settings.defaultRemote, remoteURL: value)
                newRemoteURL = ""
                await refreshSelected(fetch: false)
            } catch { present(error) }
        }
    }

    func addDSStoreToGitignore() {
        guard let repository = selectedRepository else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try gitService.addDSStoreToGitignore(at: resolve(repository))
                appendLog("Updated .gitignore", detail: ".DS_Store", isSuccess: true)
                await refreshSelected(fetch: false)
            } catch { present(error) }
        }
    }

    func openFinder() {
        guard let repository = selectedRepository else { return }
        let url = URL(fileURLWithPath: repository.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTerminal() {
        guard let repository = selectedRepository else { return }
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: repository.path)], withApplicationAt: terminalURL, configuration: configuration)
    }

    func showRepositoryLogs() { showLogs = true }

    private func resolve(_ repository: Repository) throws -> URL {
        let resolved = try bookmarkStore.resolve(repository)
        selectedAccessURL = resolved.url
        if resolved.isStale, let bookmark = try? bookmarkStore.makeBookmark(for: resolved.url) {
            var updated = repository
            updated.bookmarkData = bookmark
            updateRepository(updated)
        }
        return resolved.url
    }

    private func apply(_ snapshot: RepositorySnapshot) {
        updateRepository(snapshot.repository)
        selectedRepository = snapshot.repository
        status = snapshot.status
        if commitMessage.isEmpty { commitMessage = snapshot.repository.lastCommitMessage ?? settings.commitMessage(for: snapshot.repository.name) }
    }

    private func updateRepository(_ repository: Repository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
        } else {
            repositories.insert(repository, at: 0)
        }
        selectedRepository = repository.id == selectedRepositoryID ? repository : selectedRepository
        bookmarkStore.save(repositories)
    }

    private func present(_ error: Error) {
        let value: GitAppError
        if let error = error as? GitAppError { value = error }
        else { value = .processFailed(command: "", status: -1, details: error.localizedDescription) }
        activeError = ErrorPresentation(title: value.title, message: value.errorDescription ?? "Git operation failed.", recovery: value.recoverySuggestion, technicalDetails: value.technicalDetails)
    }

    private func isRetryablePushError(_ error: GitAppError) -> Bool {
        switch error {
        case .authenticationFailed, .networkUnavailable, .pushRejected: return true
        default: return false
        }
    }

    private func appendLog(_ title: String, detail: String? = nil, isSuccess: Bool? = nil) {
        logs.append(GitOperationLog(title: title, detail: detail, isSuccess: isSuccess))
    }

    private func appendTechnical(_ text: String, isError: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        logs.append(GitOperationLog(title: isError ? "stderr" : "stdout", detail: cleaned, isSuccess: isError ? false : nil, isTechnical: true))
    }
}
