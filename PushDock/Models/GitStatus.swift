import Foundation

struct GitStatus: Equatable {
    var branch: String?
    var upstream: String?
    var ahead: Int
    var behind: Int
    var isClean: Bool
    var isDetachedHead: Bool
    var isRebasing: Bool
    var isMerging: Bool
    var changes: [GitChange]

    var hasLocalWork: Bool { !changes.isEmpty }
    var hasRemoteChanges: Bool { behind > 0 }
    var isDiverged: Bool { ahead > 0 && behind > 0 }

    static let empty = GitStatus(
        branch: nil,
        upstream: nil,
        ahead: 0,
        behind: 0,
        isClean: true,
        isDetachedHead: false,
        isRebasing: false,
        isMerging: false,
        changes: []
    )
}
