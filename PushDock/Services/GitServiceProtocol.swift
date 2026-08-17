import Foundation

protocol GitServiceProtocol: AnyObject {
    func validateRepository(at url: URL) async throws -> URL
    func loadSnapshot(at url: URL, existing: Repository?, onOutput: GitService.OutputHandler?) async throws -> RepositorySnapshot
    func currentStatus(at url: URL, onOutput: GitService.OutputHandler?) async throws -> GitStatus
    func sync(at url: URL, repository: Repository, message: String, fetchBeforeSync: Bool, automaticallyAddDSStore: Bool, onProgress: GitService.ProgressHandler?, onOutput: GitService.OutputHandler?) async throws -> SyncSummary
}

extension GitService: GitServiceProtocol {}
