import Foundation

enum GitChangeStatus: String, Codable, CaseIterable {
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case conflicted

    var label: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .untracked: return "New"
        case .conflicted: return "Conflict"
        }
    }

    var symbol: String {
        switch self {
        case .modified: return "pencil"
        case .added: return "plus"
        case .deleted: return "minus"
        case .renamed: return "arrow.right"
        case .untracked: return "sparkle"
        case .conflicted: return "exclamationmark.triangle"
        }
    }
}

struct GitChange: Identifiable, Equatable {
    let id: String
    let file: String
    let relativePath: String
    let status: GitChangeStatus

    init(file: String, relativePath: String, status: GitChangeStatus) {
        self.id = "\(status.rawValue):\(relativePath)"
        self.file = file
        self.relativePath = relativePath
        self.status = status
    }
}
