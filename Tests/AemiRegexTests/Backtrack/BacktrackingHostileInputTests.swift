import Testing

@testable import AemiRegex

/// Patterns and texts built to exhaust the stack, the memory or the time: each ends in a typed error or a clean answer.
struct BacktrackingHostileInputTests {
    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `deeply nested groups stop at the nesting limit instead of overflowing the stack`(
        dialect: BacktrackingPattern.Dialect
    ) {
        let depth = 10_000
        let pattern = String(repeating: "(?:", count: depth) + "a" + String(repeating: ")", count: depth)
        #expect(throws: PatternError.limit(.nestingDepth)) { try BacktrackingPattern(pattern, dialect: dialect) }
        let lookarounds = String(repeating: "(?=", count: depth) + "a" + String(repeating: ")", count: depth)
        #expect(throws: PatternError.limit(.nestingDepth)) { try BacktrackingPattern(lookarounds, dialect: dialect) }
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `nested counted repetitions stop at the program size limit instead of using all memory`(
        dialect: BacktrackingPattern.Dialect
    ) {
        let pattern = "((((a{1000}){1000}){1000}){1000}){1000}"
        #expect(throws: PatternError.limit(.programSize)) { try BacktrackingPattern(pattern, dialect: dialect) }
    }

    @Test func `a pattern longer than the limit is refused before it is read`() {
        let pattern = String(repeating: "a", count: Pattern.Limits.default.maxPatternBytes + 1)
        #expect(throws: PatternError.limit(.patternLength)) { try BacktrackingPattern(pattern, dialect: .pcre2) }
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `a class and a dot never match a byte that is not valid UTF-8`(dialect: BacktrackingPattern.Dialect) throws {
        let pattern = try BacktrackingPattern(".", dialect: dialect)
        #expect(try pattern.matches(in: [0x61, 0xFF, 0x62]).map(\.range) == [0 ..< 1, 2 ..< 3])
        #expect(try pattern.firstMatch(in: [0xE2, 0x82]) == nil, "a truncated three-byte sequence")
        #expect(try pattern.firstMatch(in: [0xC0, 0x80]) == nil, "an overlong encoding")
        #expect(try pattern.firstMatch(in: [0xED, 0xA0, 0x80]) == nil, "an encoded surrogate")
        let behind = try BacktrackingPattern("(?<=.)b", dialect: dialect)
        #expect(try behind.firstMatch(in: [0xFF, 0x62]) == nil, "the byte before is not a character")
        #expect(try behind.firstMatch(in: [0xC3, 0xA9, 0x62])?.range == 2 ..< 3)
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `a search that starts inside a character reads no character before it`(dialect: BacktrackingPattern.Dialect)
        throws
    {
        let pattern = try BacktrackingPattern("(?<=.)", dialect: dialect)
        // At offset 1 no character ends, so the match is the first position where one does.
        #expect(try pattern.firstMatch(in: [0xC3, 0xA9], from: 1)?.range == 2 ..< 2)
        #expect(try pattern.firstMatch(in: [0xC3, 0xA9, 0x62], from: 1)?.range == 2 ..< 2)
    }

    @Test func `matches shares one budget across every search of the call`() throws {
        let budget = BacktrackingPattern.Budget(maxSteps: 1000, maxStackEntries: 1000)
        let pattern = try BacktrackingPattern("a", dialect: .pcre2, budget: budget)
        let text = Array(String(repeating: "a", count: 10_000).utf8)
        #expect(try pattern.firstMatch(in: text)?.range == 0 ..< 1)
        #expect(throws: BacktrackError.budgetExceeded(.steps)) { try pattern.matches(in: text) }
    }

    @Test func `a look-behind longer than 255 characters is refused in PCRE2 and allowed in ECMAScript`() throws {
        let unbounded = "(?<=a{1,300})b"
        #expect(throws: PatternError.syntax(.unboundedLookbehind, offset: 0)) {
            try BacktrackingPattern(unbounded, dialect: .pcre2)
        }
        #expect(throws: PatternError.syntax(.unboundedLookbehind, offset: 0)) {
            try BacktrackingPattern("(?<=a+)b", dialect: .pcre2)
        }
        let ecma = try BacktrackingPattern(unbounded, dialect: .ecmaScript)
        #expect(try ecma.firstMatch(in: Array("aab".utf8))?.range == 2 ..< 3)
    }

    @Test func `the x flag is PCRE2 only`() {
        #expect(throws: PatternError.syntax(.invalidFlag, offset: 0)) {
            try BacktrackingPattern("a b", dialect: .ecmaScript, options: .extended)
        }
    }

    @Test(arguments: [BacktrackingPattern.Dialect.ecmaScript, .pcre2])
    func `a text of a million characters is searched without growing the stack past the budget`(
        dialect: BacktrackingPattern.Dialect
    ) throws {
        let pattern = try BacktrackingPattern("[^x]*y", dialect: dialect)
        let text = Array(String(repeating: "a", count: 1_000_000).utf8) + [0x79]
        #expect(try pattern.firstMatch(in: text)?.range == 0 ..< 1_000_001)
    }

    @Test func `recursion deeper than the budget ends in budgetExceeded, and a larger budget allows it`() throws {
        let balanced = #"^(\((?:[^()]|(?1))*\))$"#
        let text = Array((String(repeating: "(", count: 300) + String(repeating: ")", count: 300)).utf8)
        let shallow = try BacktrackingPattern(balanced, dialect: .pcre2)
        #expect(throws: BacktrackError.budgetExceeded(.recursion)) { try shallow.firstMatch(in: text) }
        let budget = BacktrackingPattern.Budget(maxSteps: 10_000_000, maxStackEntries: 1 << 20, maxRecursionDepth: 400)
        let deep = try BacktrackingPattern(balanced, dialect: .pcre2, budget: budget)
        #expect(try deep.firstMatch(in: text)?.range == 0 ..< 600)
    }

    @Test func `a recursion that cannot make progress fails the path instead of looping`() throws {
        let pattern = try BacktrackingPattern("(?R)a|b", dialect: .pcre2)
        #expect(try pattern.firstMatch(in: Array("ab".utf8))?.range == 1 ..< 2)
        let left = try BacktrackingPattern("(a|(?1)b)", dialect: .pcre2)
        #expect(try left.firstMatch(in: Array("ab".utf8))?.range == 0 ..< 1)
    }

    @Test func `calls and conditionals are PCRE2 only`() {
        for pattern in ["(a)(?1)", "(?R)", "(a)?(?(1)b|c)", #"(a)\g<1>"#] {
            #expect(throws: PatternError.self) { try BacktrackingPattern(pattern, dialect: .ecmaScript) }
        }
    }

    @Test func `classes nested in v mode stop at the nesting limit instead of overflowing the stack`() {
        let depth = 20_000
        let pattern = String(repeating: "[", count: depth) + "a" + String(repeating: "]", count: depth)
        #expect(throws: PatternError.limit(.nestingDepth)) {
            try BacktrackingPattern(pattern, dialect: .ecmaScript, options: .unicodeSets)
        }
    }

    @Test func `the v flag is ECMAScript only, and properties of strings are not supported`() {
        #expect(throws: PatternError.syntax(.invalidFlag, offset: 0)) {
            try BacktrackingPattern("[a]", dialect: .pcre2, options: .unicodeSets)
        }
        #expect(throws: PatternError.self) {
            try BacktrackingPattern(#"[\p{RGI_Emoji}]"#, dialect: .ecmaScript, options: .unicodeSets)
        }
        #expect(throws: PatternError.self) {
            try BacktrackingPattern("[a--b", dialect: .ecmaScript, options: .unicodeSets)
        }
    }
}
