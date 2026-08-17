import Foundation

struct ProcessResult {
    let executable: String
    let arguments: [String]
    let status: Int32
    let stdout: String
    let stderr: String
    let duration: TimeInterval

    var succeeded: Bool { status == 0 }
    var commandDescription: String {
        ([executable] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"$;&|()<>"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

final class ProcessRunner {
    enum RunnerError: Error { case launchFailed(Error) }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        onOutput: ((String, Bool) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let start = Date()
            let stateQueue = DispatchQueue(label: "com.pushdock.process-runner")
            var stdoutData = Data()
            var stderrData = Data()
            var didResume = false

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stateQueue.async {
                    stdoutData.append(data)
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        onOutput?(text, false)
                    }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                stateQueue.async {
                    stderrData.append(data)
                    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        onOutput?(text, true)
                    }
                }
            }

            process.terminationHandler = { process in
                stateQueue.async {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: ProcessResult(
                        executable: executableURL.path,
                        arguments: arguments,
                        status: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        duration: Date().timeIntervalSince(start)
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                stateQueue.async {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(throwing: RunnerError.launchFailed(error))
                }
            }
        }
    }
}
