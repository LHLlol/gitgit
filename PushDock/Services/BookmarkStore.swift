import Foundation

final class BookmarkStore {
    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("PushDock", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("repositories.json")
    }

    func load() -> [Repository] {
        guard let data = try? Data(contentsOf: storageURL), let values = try? JSONDecoder().decode([Repository].self, from: data) else { return [] }
        return values.sorted { $0.lastOpened > $1.lastOpened }
    }

    func save(_ repositories: [Repository]) {
        guard let data = try? JSONEncoder().encode(repositories) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ repository: Repository) throws -> (url: URL, isStale: Bool) {
        if let bookmarkData = repository.bookmarkData {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard fileManager.fileExists(atPath: url.path) else { throw GitAppError.bookmarkUnavailable }
            _ = url.startAccessingSecurityScopedResource()
            return (url, stale)
        }
        let url = URL(fileURLWithPath: repository.path)
        guard fileManager.fileExists(atPath: url.path) else { throw GitAppError.bookmarkUnavailable }
        return (url, false)
    }
}
