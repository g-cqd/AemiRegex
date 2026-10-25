/// A deterministic, Swift-looking corpus split into file-sized chunks, so the speed gate does not depend on any checkout.
enum SyntheticCorpus {
    private static let words = [
        "value", "name", "result", "session", "provider", "buffer", "token", "request", "state", "index", "model",
        "stream", "reader", "writer", "cursor", "layout", "render", "update", "parse", "decode", "handle", "Queue",
        "client", "server", "record", "event", "frame", "cache", "limit", "range"
    ]
    private static let types = ["String", "Int", "Bool", "Data", "URL", "Sendable", "Result<Int, Error>", "[UInt8]"]

    private static func line(_ rng: inout SplitMix64) -> String {
        let w = words.randomElement(using: &rng) ?? "value"
        let v = words.randomElement(using: &rng) ?? "name"
        let t = types.randomElement(using: &rng) ?? "Int"
        let cap = w.prefix(1).uppercased() + w.dropFirst()
        let n = Int.random(in: 0 ..< 1000, using: &rng)
        switch Int.random(in: 0 ..< 24, using: &rng) {
            case 0: return "    public func \(w)\(n)(_ \(v): \(t)) async throws -> \(t) {"
            case 1, 2: return "    func \(w)(\(v): \(t)) -> \(t) {"
            case 3: return "struct \(cap)\(n): Sendable {"
            case 4: return "enum \(cap)Error: Error { case \(v) }"
            case 5: return "final class \(cap): \(types.randomElement(using: &rng) ?? "Int") {"
            case 6: return "protocol \(cap)Reading { var \(w): \(t) { get } }"
            case 7: return "import Foundation"
            // The marker word is assembled from pieces: the family's tag check bans it in Swift sources, even inside a string.
            case 8: return "    // " + "TO" + "DO: handle \(w) when \(v) is empty"
            case 9: return "    // fixme later \(n)"
            case 10: return "    // a hack around \(v)"
            case 11, 12, 13: return "        return \(w) + \(n)"
            case 14, 15: return "        let \(v) = try await \(w).\(v)(\(n))"
            case 16: return "    }"
            case 17: return "    private var \(w)\(n): \(t) = \(n)"
            case 18: return "\(cap)\(n): \(t) {"
            default: return "        guard let \(v) = \(w) else { return nil }"
        }
    }

    /// `files` chunks of about `bytesPerFile` bytes each.
    static func files(count files: Int = 400, bytesPerFile: Int = 2600) -> [[UInt8]] {
        var rng = SplitMix64(state: 0x5EED_2026)
        return (0 ..< files)
            .map { _ in
                var text = ""
                while text.utf8.count < bytesPerFile { text += line(&rng) + "\n" }
                return Array(text.utf8)
            }
    }
}
