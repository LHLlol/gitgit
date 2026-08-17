import Foundation

struct Repository: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?
    var remoteURL: String?
    var remoteName: String?
    var branch: String?
    var gitUserName: String?
    var gitUserEmail: String?
    var lastOpened: Date
    var lastPush: Date?
    var lastCommitMessage: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmarkData: Data? = nil,
        remoteURL: String? = nil,
        remoteName: String? = nil,
        branch: String? = nil,
        gitUserName: String? = nil,
        gitUserEmail: String? = nil,
        lastOpened: Date = Date(),
        lastPush: Date? = nil,
        lastCommitMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.remoteURL = remoteURL
        self.remoteName = remoteName
        self.branch = branch
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.lastOpened = lastOpened
        self.lastPush = lastPush
        self.lastCommitMessage = lastCommitMessage
    }
}
