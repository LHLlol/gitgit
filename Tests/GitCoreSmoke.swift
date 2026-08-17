import Foundation

@main
struct GitCoreSmoke {
    static func main() async {
        guard CommandLine.arguments.count > 1 else {
            fputs("usage: GitCoreSmoke <repository>\n", stderr)
            exit(2)
        }

        let repositoryURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = GitService()
        do {
            let root = try await service.validateRepository(at: repositoryURL)
            let snapshot = try await service.loadSnapshot(at: root)
            guard !snapshot.status.changes.isEmpty else {
                throw NSError(domain: "GitCoreSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a local change before sync"])
            }
            let message = "Smoke test sync"
            let summary = try await service.sync(at: root, repository: snapshot.repository, message: message, fetchBeforeSync: true)
            let final = try await service.loadSnapshot(at: root)
            guard summary.didCreateCommit, summary.didPush, final.status.isClean, final.status.ahead == 0, final.status.behind == 0 else {
                throw NSError(domain: "GitCoreSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sync assertions failed"])
            }
            print("SMOKE_OK")
            print("branch=\(final.status.branch ?? "detached")")
            print("remote=\(final.repository.remoteName ?? "none")")
            print("status=clean")
        } catch {
            fputs("SMOKE_FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
