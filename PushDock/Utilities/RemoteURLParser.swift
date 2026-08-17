import Foundation

enum RemoteURLParser {
    static func displayName(from value: String?) -> String {
        guard let value, !value.isEmpty else { return "No remote configured" }
        var cleaned = value
        if let at = cleaned.firstIndex(of: "@"), cleaned.contains("://") {
            let schemeEnd = cleaned.range(of: "://")?.upperBound ?? cleaned.startIndex
            if at > schemeEnd { cleaned = String(cleaned[at...]).dropFirst().description }
        }
        if cleaned.hasPrefix("git@") {
            cleaned = String(cleaned.dropFirst(4))
            if let separator = cleaned.firstIndex(of: ":") {
                cleaned = String(cleaned[..<separator]) + "/" + String(cleaned[cleaned.index(after: separator)...])
            }
        }
        if let scheme = cleaned.range(of: "://") {
            cleaned = String(cleaned[scheme.upperBound...])
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleaned.hasSuffix(".git") { cleaned.removeLast(4) }
        return cleaned
    }

    static func redacted(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let scheme = value.range(of: "://"), let at = value[scheme.upperBound...].firstIndex(of: "@") else {
            return value
        }
        let prefix = value[..<scheme.upperBound]
        let host = value[value.index(after: at)...]
        return "\(prefix)••••@\(host)"
    }
}
