import Foundation

enum GitAppError: LocalizedError, Equatable {
    case notRepository
    case gitUnavailable
    case authenticationFailed(details: String)
    case networkUnavailable(details: String)
    case remoteNotFound
    case branchNotFound
    case detachedHead
    case rebaseInProgress
    case mergeInProgress
    case rebaseConflict(files: [String], details: String)
    case pushRejected(details: String)
    case largeFile(files: [String])
    case nothingToCommit
    case processFailed(command: String, status: Int32, details: String)
    case invalidCommitMessage
    case bookmarkUnavailable

    var errorDescription: String? {
        switch self {
        case .notRepository: return "This folder is not a Git repository."
        case .gitUnavailable: return "Git is not available on this Mac."
        case .authenticationFailed: return "GitHub authentication failed."
        case .networkUnavailable: return "Network connection unavailable."
        case .remoteNotFound: return "No remote repository configured."
        case .branchNotFound: return "The current branch could not be determined."
        case .detachedHead: return "This repository is currently in detached HEAD state."
        case .rebaseInProgress: return "A rebase is already in progress."
        case .mergeInProgress: return "A merge is already in progress."
        case .rebaseConflict: return "Rebase conflict detected."
        case .pushRejected: return "Remote changes need to be synchronized first."
        case let .largeFile(files):
            let suffix = files.isEmpty ? "" : ": " + files.joined(separator: ", ")
            return "Large file detected\(suffix). GitHub may reject files larger than 100 MB."
        case .nothingToCommit: return "There are no local changes to commit."
        case .processFailed: return "Git could not complete this operation."
        case .invalidCommitMessage: return "Enter a commit message before syncing."
        case .bookmarkUnavailable: return "This repository is no longer available."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notRepository: return "Choose a folder that contains a Git repository."
        case .gitUnavailable: return "Install the Xcode Command Line Tools, then try again."
        case .authenticationFailed: return "Open Terminal to complete your existing GitHub authentication."
        case .networkUnavailable: return "Check your connection. Your local commit is safe."
        case .remoteNotFound: return "Add a remote repository before pushing."
        case .detachedHead: return "Switch to a branch before pushing."
        case .rebaseConflict: return "Resolve the conflicted files, then refresh the repository."
        case .largeFile: return "Remove the file from the commit or use Git LFS."
        case .pushRejected: return "Pull the remote changes with rebase, then retry the push."
        case .nothingToCommit: return "The repository is already up to date."
        default: return nil
        }
    }

    var technicalDetails: String? {
        switch self {
        case let .authenticationFailed(details), let .networkUnavailable(details), let .rebaseConflict(_, details), let .pushRejected(details): return details
        case let .processFailed(command, status, details): return "$ git \(command)\nexit \(status)\n\(details)"
        default: return nil
        }
    }

    var conflictFiles: [String] {
        if case let .rebaseConflict(files, _) = self { return files }
        return []
    }

    var title: String {
        switch self {
        case .rebaseConflict: return "Action required"
        case .authenticationFailed: return "Authentication failed"
        case .networkUnavailable: return "Unable to reach GitHub"
        case .remoteNotFound: return "No remote configured"
        default: return "Git operation failed"
        }
    }

    static func from(command: String, status: Int32, stdout: String, stderr: String) -> GitAppError {
        let details = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = details.lowercased()
        if lower.contains("not a git repository") { return .notRepository }
        if lower.contains("permission denied (publickey)") || lower.contains("authentication failed") || lower.contains("could not read username") {
            return .authenticationFailed(details: details)
        }
        if lower.contains("could not resolve host") || lower.contains("network is unreachable") || lower.contains("failed to connect") || lower.contains("connection timed out") {
            return .networkUnavailable(details: details)
        }
        if lower.contains("non-fast-forward") || lower.contains("fetch first") || lower.contains("rejected") {
            return .pushRejected(details: details)
        }
        if lower.contains("unmerged files") || lower.contains("conflict") {
            return .rebaseConflict(files: [], details: details)
        }
        return .processFailed(command: command, status: status, details: details)
    }
}
