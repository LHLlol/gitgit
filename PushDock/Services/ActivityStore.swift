import Foundation

final class ActivityStore {
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = support.appendingPathComponent("PushDock", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("activity.json")
    }

    func load() -> [ActivityItem] {
        guard let data = try? Data(contentsOf: storageURL), let values = try? JSONDecoder().decode([ActivityItem].self, from: data) else { return [] }
        return values.sorted { $0.timestamp > $1.timestamp }
    }

    func save(_ values: [ActivityItem]) {
        let trimmed = Array(values.sorted { $0.timestamp > $1.timestamp }.prefix(100))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
