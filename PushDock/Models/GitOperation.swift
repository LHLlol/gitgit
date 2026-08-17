import Foundation

enum GitOperationState: String, Equatable {
    case idle
    case checking
    case fetching
    case staging
    case committing
    case rebasing
    case pushing
    case success
    case error
    case conflict

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .checking: return "Checking"
        case .fetching: return "Fetching"
        case .staging: return "Staging"
        case .committing: return "Committing"
        case .rebasing: return "Rebasing"
        case .pushing: return "Pushing"
        case .success: return "Completed"
        case .error: return "Needs attention"
        case .conflict: return "Conflict"
        }
    }
}

struct GitOperationLog: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let detail: String?
    let isSuccess: Bool?
    let isTechnical: Bool

    init(title: String, detail: String? = nil, isSuccess: Bool? = nil, isTechnical: Bool = false) {
        self.timestamp = Date()
        self.title = title
        self.detail = detail
        self.isSuccess = isSuccess
        self.isTechnical = isTechnical
    }
}

struct GitCommandRecord: Codable, Equatable {
    var command: String
    var startTime: Date
    var endTime: Date
    var status: Int32
    var stdout: String
    var stderr: String
}

struct ActivityItem: Identifiable, Codable, Equatable {
    var id: UUID
    var repositoryID: UUID
    var repositoryName: String
    var branch: String
    var commitMessage: String
    var timestamp: Date
    var result: String
    var commitHash: String?
    var remote: String?
    var duration: TimeInterval?
    var steps: [String]

    init(
        repositoryID: UUID,
        repositoryName: String,
        branch: String,
        commitMessage: String,
        timestamp: Date = Date(),
        result: String,
        commitHash: String? = nil,
        remote: String? = nil,
        duration: TimeInterval? = nil,
        steps: [String] = []
    ) {
        self.id = UUID()
        self.repositoryID = repositoryID
        self.repositoryName = repositoryName
        self.branch = branch
        self.commitMessage = commitMessage
        self.timestamp = timestamp
        self.result = result
        self.commitHash = commitHash
        self.remote = remote
        self.duration = duration
        self.steps = steps
    }
}
