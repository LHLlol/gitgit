import Foundation

struct RepositorySnapshot {
    var repository: Repository
    var status: GitStatus
}

struct SyncSummary {
    var repository: Repository
    var status: GitStatus
    var commitMessage: String
    var commitHash: String?
    var didCreateCommit: Bool
    var didPush: Bool
    var duration: TimeInterval
    var steps: [String]
}

final class GitService {
    typealias OutputHandler = (_ text: String, _ isError: Bool) -> Void
    typealias ProgressHandler = (_ state: GitOperationState, _ message: String) -> Void

    private let runner: ProcessRunner
    private let fileManager: FileManager
    private let gitURL: URL?

    init(runner: ProcessRunner = ProcessRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
        self.gitURL = GitService.findGitURL()
    }

    static func findGitURL() -> URL? {
        let preferred = URL(fileURLWithPath: "/usr/bin/git")
        if FileManager.default.isExecutableFile(atPath: preferred.path) { return preferred }
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard FileManager.default.isExecutableFile(atPath: xcrun.path) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = xcrun
        process.arguments = ["--find", "git"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    func validateRepository(at url: URL) async throws -> URL {
        guard gitURL != nil else { throw GitAppError.gitUnavailable }
        let result = try await runGit(arguments: ["rev-parse", "--is-inside-work-tree"], repositoryURL: url)
        guard result.succeeded, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw GitAppError.notRepository
        }
        let rootResult = try await runGit(arguments: ["rev-parse", "--show-toplevel"], repositoryURL: url)
        guard rootResult.succeeded else { throw Self.mapError(rootResult) }
        let rootPath = rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rootPath.isEmpty else { throw GitAppError.notRepository }
        return URL(fileURLWithPath: rootPath).standardizedFileURL
    }

    func loadSnapshot(at url: URL, existing: Repository? = nil, onOutput: OutputHandler? = nil) async throws -> RepositorySnapshot {
        let root = try await validateRepository(at: url)
        let metadata = try await loadMetadata(at: root, onOutput: onOutput)
        var repository = existing ?? Repository(name: root.lastPathComponent, path: root.path)
        repository.name = root.lastPathComponent
        repository.path = root.path
        repository.remoteName = metadata.remoteName
        repository.remoteURL = metadata.remoteURL
        repository.branch = metadata.status.branch
        repository.gitUserName = metadata.userName
        repository.gitUserEmail = metadata.userEmail
        repository.lastOpened = Date()
        return RepositorySnapshot(repository: repository, status: metadata.status)
    }

    func currentStatus(at url: URL, onOutput: OutputHandler? = nil) async throws -> GitStatus {
        let root = try await validateRepository(at: url)
        return try await status(at: root, onOutput: onOutput)
    }

    func fetch(at url: URL, remote: String, onOutput: OutputHandler? = nil) async throws {
        _ = try await execute(arguments: ["fetch", "--prune", remote], repositoryURL: url, onOutput: onOutput)
    }

    func addRemote(at url: URL, name: String, remoteURL: String, onOutput: OutputHandler? = nil) async throws {
        guard !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitAppError.remoteNotFound }
        _ = try await execute(arguments: ["remote", "add", name, remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)], repositoryURL: url, onOutput: onOutput)
    }

    func addDSStoreToGitignore(at url: URL) throws {
        let ignoreURL = url.appendingPathComponent(".gitignore")
        let current = (try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? ""
        let entries = Set(current.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !entries.contains(".DS_Store") else { return }
        let separator = current.isEmpty || current.hasSuffix("\n") ? "" : "\n"
        try (current + separator + ".DS_Store\n").write(to: ignoreURL, atomically: true, encoding: .utf8)
    }

    func stageAll(at url: URL, onOutput: OutputHandler? = nil) async throws {
        _ = try await execute(arguments: ["add", "-A"], repositoryURL: url, onOutput: onOutput)
    }

    func hasStagedChanges(at url: URL) async throws -> Bool {
        let result = try await runProcess(arguments: ["diff", "--cached", "--quiet"], repositoryURL: url)
        return result.status != 0
    }

    func commit(at url: URL, message: String, onOutput: OutputHandler? = nil) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitAppError.invalidCommitMessage }
        _ = try await execute(arguments: ["commit", "-m", trimmed], repositoryURL: url, onOutput: onOutput)
        let hash = try await execute(arguments: ["rev-parse", "HEAD"], repositoryURL: url)
        return hash.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pullRebase(at url: URL, remote: String, branch: String, onOutput: OutputHandler? = nil) async throws {
        do {
            _ = try await execute(arguments: ["pull", "--rebase", remote, branch], repositoryURL: url, onOutput: onOutput)
        } catch let error as GitAppError {
            if isRebaseInProgress(at: url) {
                throw await makeConflictError(at: url, fallback: error)
            }
            throw error
        }
    }

    func push(at url: URL, remote: String, branch: String, setUpstream: Bool, onOutput: OutputHandler? = nil) async throws {
        var args = ["push"]
        if setUpstream { args.append(contentsOf: ["-u", remote, branch]) }
        else { args.append(contentsOf: [remote, branch]) }
        _ = try await execute(arguments: args, repositoryURL: url, onOutput: onOutput)
    }

    func abortRebase(at url: URL, onOutput: OutputHandler? = nil) async throws {
        _ = try await execute(arguments: ["rebase", "--abort"], repositoryURL: url, onOutput: onOutput)
    }

    func conflictFiles(at url: URL) async -> [String] {
        guard let result = try? await execute(arguments: ["diff", "--name-only", "--diff-filter=U"], repositoryURL: url) else { return [] }
        return result.stdout.split(whereSeparator: \.isNewline).map(String.init)
    }

    func isRebaseInProgress(at url: URL) -> Bool {
        guard let gitDirURL = gitDirectory(at: url) else { return false }
        return fileManager.fileExists(atPath: gitDirURL.appendingPathComponent("rebase-merge").path)
            || fileManager.fileExists(atPath: gitDirURL.appendingPathComponent("rebase-apply").path)
    }

    func isMergeInProgress(at url: URL) -> Bool {
        guard let gitDirURL = gitDirectory(at: url) else { return false }
        return fileManager.fileExists(atPath: gitDirURL.appendingPathComponent("MERGE_HEAD").path)
    }

    func sync(
        at url: URL,
        repository: Repository,
        message: String,
        fetchBeforeSync: Bool,
        automaticallyAddDSStore: Bool = false,
        onProgress: ProgressHandler? = nil,
        onOutput: OutputHandler? = nil
    ) async throws -> SyncSummary {
        let started = Date()
        var steps: [String] = []
        var didCreateCommit = false
        var commitHash: String?
        var current = try await loadSnapshot(at: url, existing: repository, onOutput: onOutput)
        guard let branch = current.status.branch, !branch.isEmpty else { throw GitAppError.detachedHead }
        guard !current.status.isDetachedHead else { throw GitAppError.detachedHead }
        guard !current.status.isRebasing else { throw GitAppError.rebaseInProgress }
        guard !current.status.isMerging else { throw GitAppError.mergeInProgress }
        guard let remote = current.repository.remoteName, !remote.isEmpty,
              let _ = current.repository.remoteURL, !current.repository.remoteURL!.isEmpty else {
            throw GitAppError.remoteNotFound
        }

        let largeFiles = FileSizeChecker.largeFiles(changes: current.status.changes, repositoryURL: url, fileManager: fileManager)
        if !largeFiles.isEmpty { throw GitAppError.largeFile(files: largeFiles) }

        if automaticallyAddDSStore && current.status.changes.contains(where: { $0.relativePath == ".DS_Store" || $0.file == ".DS_Store" }) {
            try addDSStoreToGitignore(at: url)
            current = try await loadSnapshot(at: url, existing: current.repository, onOutput: onOutput)
        }

        onProgress?(.checking, "Checking repository")
        steps.append("Repository checked")

        onProgress?(.staging, "Staging local changes")
        try await stageAll(at: url, onOutput: onOutput)
        let hasStaged = try await hasStagedChanges(at: url)
        if hasStaged {
            onProgress?(.committing, "Creating local commit")
            commitHash = try await commit(at: url, message: message, onOutput: onOutput)
            didCreateCommit = true
            steps.append("Created local commit")
        } else {
            steps.append("Working tree clean; no empty commit created")
        }

        if fetchBeforeSync {
            onProgress?(.fetching, "Checking remote changes")
            try await fetch(at: url, remote: remote, onOutput: onOutput)
            steps.append("Fetched \(remote)")
        }

        current = try await loadSnapshot(at: url, existing: current.repository, onOutput: onOutput)
        if current.status.behind > 0 {
            onProgress?(.rebasing, "Rebasing local commits")
            try await pullRebase(at: url, remote: remote, branch: branch, onOutput: onOutput)
            steps.append("Rebased local commits")
        }

        let hasCommitsToPush = current.status.ahead > 0 || didCreateCommit
        guard hasCommitsToPush else {
            current = try await loadSnapshot(at: url, existing: current.repository, onOutput: onOutput)
            onProgress?(.success, "Everything is up to date")
            return SyncSummary(repository: current.repository, status: current.status, commitMessage: message, commitHash: commitHash, didCreateCommit: didCreateCommit, didPush: false, duration: Date().timeIntervalSince(started), steps: steps)
        }

        onProgress?(.pushing, "Pushing to \(remote)")
        var pushed = false
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let hasUpstream = current.status.upstream != nil
                try await push(at: url, remote: remote, branch: branch, setUpstream: !hasUpstream, onOutput: onOutput)
                pushed = true
                steps.append(attempt == 0 ? "Push completed" : "Push completed after remote retry")
                break
            } catch let error as GitAppError {
                lastError = error
                guard attempt == 0, isPushRejection(error) else { throw error }
                onProgress?(.fetching, "Remote changed; retrying safely")
                try await fetch(at: url, remote: remote, onOutput: onOutput)
                current = try await loadSnapshot(at: url, existing: current.repository, onOutput: onOutput)
                if current.status.behind > 0 {
                    onProgress?(.rebasing, "Rebasing after remote update")
                    try await pullRebase(at: url, remote: remote, branch: branch, onOutput: onOutput)
                }
            }
        }
        if let lastError, !pushed { throw lastError }
        current = try await loadSnapshot(at: url, existing: current.repository, onOutput: onOutput)
        onProgress?(.success, "Synced successfully")
        return SyncSummary(repository: current.repository, status: current.status, commitMessage: message, commitHash: commitHash, didCreateCommit: didCreateCommit, didPush: pushed, duration: Date().timeIntervalSince(started), steps: steps)
    }

    private func loadMetadata(at root: URL, onOutput: OutputHandler?) async throws -> (status: GitStatus, remoteName: String?, remoteURL: String?, userName: String?, userEmail: String?) {
        let status = try await status(at: root, onOutput: onOutput)
        let remotesResult = try await execute(arguments: ["remote"], repositoryURL: root, onOutput: onOutput)
        let remotes = remotesResult.stdout.split(whereSeparator: \.isNewline).map(String.init)
        let remoteName = remotes.contains("origin") ? "origin" : remotes.first
        var remoteURL: String?
        if let remoteName {
            let result = try await execute(arguments: ["remote", "get-url", remoteName], repositoryURL: root, onOutput: onOutput)
            remoteURL = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let userName = try? await configValue(at: root, key: "user.name")
        let userEmail = try? await configValue(at: root, key: "user.email")
        return (status, remoteName, remoteURL, userName ?? nil, userEmail ?? nil)
    }

    private func status(at root: URL, onOutput: OutputHandler?) async throws -> GitStatus {
        let result = try await execute(arguments: ["status", "--porcelain=v2", "-b"], repositoryURL: root, onOutput: onOutput)
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var changes: [GitChange] = []

        for line in result.stdout.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                branch = value == "(detached)" ? nil : value
                continue
            }
            if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
                continue
            }
            if line.hasPrefix("# branch.ab ") {
                let values = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for value in values {
                    if value.hasPrefix("+") { ahead = Int(value.dropFirst()) ?? 0 }
                    if value.hasPrefix("-") { behind = Int(value.dropFirst()) ?? 0 }
                }
                continue
            }
            guard !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard let marker = line.first else { continue }
            if marker == "?" {
                let path = String(line.dropFirst(2))
                changes.append(GitChange(file: URL(fileURLWithPath: path).lastPathComponent, relativePath: path, status: .untracked))
                continue
            }
            if marker == "u" {
                let path = parts.last.map(String.init) ?? ""
                changes.append(GitChange(file: URL(fileURLWithPath: path).lastPathComponent, relativePath: path, status: .conflicted))
                continue
            }
            guard parts.count >= 9 else { continue }
            let xy = String(parts[1])
            let path = String(parts[8].split(separator: "\t", maxSplits: 1).first ?? parts[8])
            let changeStatus = Self.changeStatus(for: xy)
            changes.append(GitChange(file: URL(fileURLWithPath: path).lastPathComponent, relativePath: path, status: changeStatus))
        }

        let isDetached = branch == nil
        return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, isClean: changes.isEmpty, isDetachedHead: isDetached, isRebasing: isRebaseInProgress(at: root), isMerging: isMergeInProgress(at: root), changes: changes)
    }

    private func configValue(at root: URL, key: String) async throws -> String {
        let result = try await execute(arguments: ["config", "--get", key], repositoryURL: root)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func execute(arguments: [String], repositoryURL: URL, onOutput: OutputHandler? = nil) async throws -> ProcessResult {
        let result = try await runProcess(arguments: arguments, repositoryURL: repositoryURL, onOutput: onOutput)
        guard result.succeeded else { throw Self.mapError(result) }
        return result
    }

    private func runProcess(arguments: [String], repositoryURL: URL, onOutput: OutputHandler? = nil) async throws -> ProcessResult {
        guard let gitURL else { throw GitAppError.gitUnavailable }
        let result: ProcessResult
        do {
            result = try await runner.run(executableURL: gitURL, arguments: arguments, currentDirectoryURL: repositoryURL) { text, isError in
                onOutput?(RemoteURLParser.redacted(text) ?? text, isError)
            }
        } catch {
            throw GitAppError.processFailed(command: arguments.joined(separator: " "), status: -1, details: error.localizedDescription)
        }
        return result
    }

    private func runGit(arguments: [String], repositoryURL: URL) async throws -> ProcessResult {
        try await execute(arguments: arguments, repositoryURL: repositoryURL)
    }

    private func makeConflictError(at url: URL, fallback: Error) async -> GitAppError {
        let files = await conflictFiles(at: url)
        let details = (fallback as? GitAppError)?.technicalDetails ?? fallback.localizedDescription
        return .rebaseConflict(files: files, details: details)
    }

    private func gitDirectory(at root: URL) -> URL? {
        let dotGit = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8), contents.hasPrefix("gitdir:") else { return nil }
        let path = contents.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: String(path), relativeTo: root).standardizedFileURL
    }

    private static func mapError(_ result: ProcessResult) -> GitAppError {
        GitAppError.from(command: result.arguments.joined(separator: " "), status: result.status, stdout: result.stdout, stderr: result.stderr)
    }

    private static func changeStatus(for xy: String) -> GitChangeStatus {
        if xy.contains("R") { return .renamed }
        if xy.contains("D") { return .deleted }
        if xy.contains("A") { return .added }
        return .modified
    }

    private func isPushRejection(_ error: GitAppError) -> Bool {
        if case .pushRejected = error { return true }
        return false
    }
}
