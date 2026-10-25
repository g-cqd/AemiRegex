import Foundation

@testable import AemiRegex

/// One recorded oracle answer: the pattern and subject, the flags, and what `node` or `libpcre2` said.
struct BacktrackCase: Decodable {
    enum Expected: Equatable {
        case error
        case noMatch
        case match([Range<Int>?])
        /// Every match of a global search, each as its groups.
        case all([[Range<Int>?]])
    }

    let p: String
    let s: String
    let f: String
    let r: Expected

    private enum Key: String, CodingKey { case p, s, f, r }

    /// A global case (`g` in the flags) records a list of matches, any other a single match, so the flags decide how `r` reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        p = try container.decode(String.self, forKey: .p)
        s = try container.decode(String.self, forKey: .s)
        f = try container.decode(String.self, forKey: .f)
        if try container.decodeNil(forKey: .r) {
            r = .noMatch
        } else if let text = try? container.decode(String.self, forKey: .r), text == "error" {
            r = .error
        } else if f.contains("g") {
            let lists = try container.decode([[[Int]?]].self, forKey: .r)
            r = .all(lists.map { $0.map { $0.map { $0[0] ..< $0[1] } } })
        } else {
            let pairs = try container.decode([[Int]?].self, forKey: .r)
            r = .match(pairs.map { $0.map { $0[0] ..< $0[1] } })
        }
    }

    var options: BacktrackingPattern.Options {
        var options: BacktrackingPattern.Options = []
        if f.contains("i") { options.insert(.ignoreCase) }
        if f.contains("m") { options.insert(.multiLine) }
        if f.contains("s") { options.insert(.dotAll) }
        if f.contains("x") { options.insert(.extended) }
        return options
    }
}
