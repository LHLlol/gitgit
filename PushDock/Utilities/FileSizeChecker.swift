import Foundation

struct FileSizeChecker {
    static let warningLimit: Int64 = 95 * 1024 * 1024

    static func largeFiles(changes: [GitChange], repositoryURL: URL, fileManager: FileManager = .default) -> [String] {
        changes.compactMap { change in
            guard change.status != .deleted else { return nil }
            let url = repositoryURL.appendingPathComponent(change.relativePath)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > warningLimit else { return nil }
            let megabytes = Double(size.int64Value) / 1_048_576.0
            return "\(change.relativePath) (\(String(format: "%.0f", megabytes)) MB)"
        }
    }
}
