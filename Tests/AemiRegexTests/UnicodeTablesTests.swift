import Testing

@testable import AemiRegex

/// The generated Unicode tables (from Go's `unicode` package, one version) and the property-name rules Go's `regexp` applies.
/// The tables are checked three ways: against the standard library (independent data), by internal invariants, and, in
/// `GoldenTests`, by what the engine does with them against Go.
struct UnicodeTablesTests {
    private static func set(_ name: String) -> ScalarSet? { UnicodeProperties.set(named: name) }

    private static func scalars(in set: ScalarSet) -> [Bool] {
        var member = [Bool](repeating: false, count: 0x110000)
        for range in set.ranges { for value in range { member[Int(value)] = true } }
        return member
    }

    private static let codes = Array(
        "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn"
            .split(separator: " ").map(String.init))

    private static func code(_ category: Unicode.GeneralCategory) -> String {
        switch category {
            case .uppercaseLetter: "Lu"
            case .lowercaseLetter: "Ll"
            case .titlecaseLetter: "Lt"
            case .modifierLetter: "Lm"
            case .otherLetter: "Lo"
            case .nonspacingMark: "Mn"
            case .spacingMark: "Mc"
            case .enclosingMark: "Me"
            case .decimalNumber: "Nd"
            case .letterNumber: "Nl"
            case .otherNumber: "No"
            case .connectorPunctuation: "Pc"
            case .dashPunctuation: "Pd"
            case .openPunctuation: "Ps"
            case .closePunctuation: "Pe"
            case .initialPunctuation: "Pi"
            case .finalPunctuation: "Pf"
            case .otherPunctuation: "Po"
            case .mathSymbol: "Sm"
            case .currencySymbol: "Sc"
            case .modifierSymbol: "Sk"
            case .otherSymbol: "So"
            case .spaceSeparator: "Zs"
            case .lineSeparator: "Zl"
            case .paragraphSeparator: "Zp"
            case .control: "Cc"
            case .format: "Cf"
            case .surrogate: "Cs"
            case .privateUse: "Co"
            case .unassigned: "Cn"
            @unknown default: "Cn"
        }
    }

    // MARK: Categories

    @Test func `the tables say which Unicode version they are`() {
        #expect(GeneratedUnicodeTables.unicodeVersion == "17.0.0")
    }

    @Test
    func
        `every character that is old enough to be in any platform's data has the category the standard library gives it`()
    {
        var owner = [Int8](repeating: -1, count: 0x110000)
        for (index, name) in Self.codes.enumerated() {
            guard let members = Self.set(name) else {
                Issue.record("no set for \(name)")
                return
            }
            for range in members.ranges { for value in range { owner[Int(value)] = Int8(index) } }
        }
        #expect(!owner.contains(-1), "the 30 categories must cover every scalar value")
        var mismatches: [String] = []
        var compared = 0
        for value in 0 ..< 0x110000 {
            // Assigned before Unicode 15: the data of any supported platform agrees on these.
            guard let scalar = Unicode.Scalar(UInt32(value)), let age = scalar.properties.age, age.major < 15 else {
                continue
            }
            compared += 1
            let expected = Self.code(scalar.properties.generalCategory)
            if Self.codes[Int(owner[value])] != expected, mismatches.count < 8 {
                mismatches.append(
                    "U+\(String(value, radix: 16)): table \(Self.codes[Int(owner[value])]), stdlib \(expected)")
            }
        }
        #expect(compared > 140_000, "compared only \(compared) scalars")
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test func `the groups, Cn, C and LC are what their members make them`() throws {
        func union(_ names: [String]) throws -> ScalarSet {
            try names.reduce(ScalarSet()) { try $0.union(#require(Self.set($1))) }
        }
        #expect(try Self.set("L") == union(["Lu", "Ll", "Lt", "Lm", "Lo"]))
        #expect(try Self.set("C") == union(["Cc", "Cf", "Co", "Cs", "Cn"]))
        #expect(try Self.set("Lc") == union(["Lu", "Ll", "Lt"]))
        let assigned = try union(Self.codes.filter { $0 != "Cn" })
        #expect(Self.set("Cn") == assigned.negated())
        #expect(try #require(Self.set("Cn")).ranges.first?.contains(0x378) == true)
    }

    // MARK: Names, as Go's regexp reads them

    @Test(arguments: [
        ("greek", "Greek"), ("GREEK", "Greek"), ("gr_eek", "Greek"), ("Gr-eek", "Greek"), (" Greek", "Greek"),
        ("lu", "Lu"),
        ("old_italic", "Old_Italic"), ("Old Italic", "Old_Italic"), ("olditalic", "Old_Italic"), ("Letter", "L"),
        ("Uppercase_Letter", "Lu"), ("L u", "Lu"), ("punct", "P"), ("digit", "Nd"), ("cntrl", "Cc"), ("LC", "Lc"),
        ("l", "L")
    ])
    func `a property name is matched loosely: case, spaces, underscores and hyphens do not count`(
        spelling: String, canonical: String
    ) throws {
        let found = try #require(Self.set(spelling), "\(spelling) must name a property")
        #expect(found == Self.set(canonical), "\(spelling) is \(canonical)")
    }

    @Test(arguments: ["Latn", "Script=Greek", "sc=Greek", "", "Foo", "G", "Greekk", "Lx"])
    func `a name that is not a property is nil`(name: String) {
        #expect(Self.set(name) == nil)
    }

    @Test func `the special names are the whole range, the assigned range, ASCII and cased letters`() throws {
        #expect(try #require(Self.set("Any")).ranges == [0 ... 0x10FFFF])
        #expect(try #require(Self.set("Ascii")).ranges == [0 ... 0x7F])
        #expect(try #require(Self.set("Assigned")) == #require(Self.set("Cn")).negated())
    }

    // MARK: Scripts

    @Test func `the scripts are present, non-empty and never overlap`() throws {
        let names = Array(GeneratedUnicodeTables.scriptNames.split(whereSeparator: \.isWhitespace).map(String.init))
        #expect(names.count == 174)
        var owner = [Int16](repeating: -1, count: 0x110000)
        for (index, name) in names.enumerated() {
            let members = try #require(Self.set(name), "\(name)")
            #expect(!members.isEmpty, "\(name) is empty")
            for range in members.ranges {
                for value in range {
                    #expect(
                        owner[Int(value)] == -1,
                        "U+\(String(value, radix: 16)) is in \(name) and \(names[Int(max(owner[Int(value)], 0))])")
                    owner[Int(value)] = Int16(index)
                }
            }
        }
    }

    @Test func `well-known characters are in the script they belong to`() throws {
        func inside(_ script: String, _ scalar: Unicode.Scalar) throws -> Bool {
            try #require(Self.set(script)).ranges.contains { $0.contains(scalar.value) }
        }
        #expect(try inside("Greek", "α") && !inside("Greek", "a"))
        #expect(try inside("Latin", "a") && inside("Latin", "É") && !inside("Latin", "α"))
        #expect(try inside("Han", "日") && inside("Hiragana", "ひ") && inside("Katakana", "カ"))
        #expect(try inside("Cyrillic", "П") && inside("Common", " ") && inside("Inherited", "\u{0301}"))
    }

    // MARK: Case folding

    @Test func `fold orbits are closed, ascending, and found from every member`() throws {
        var members = 0
        var cursor = 0
        let flat = GeneratedUnicodeTables.foldOrbits
        while cursor < flat.count {
            var orbit: [UInt32] = []
            while flat[cursor] != 0 {
                orbit.append(flat[cursor])
                cursor += 1
            }
            cursor += 1
            #expect(orbit.count >= 2 && orbit == orbit.sorted(), "\(orbit)")
            for member in orbit { #expect(UnicodeFolding.orbit(of: member) == orbit, "U+\(String(member, radix: 16))") }
            members += orbit.count
        }
        #expect(members == GeneratedUnicodeTables.foldIndex.count / 2)
        #expect(UnicodeFolding.orbit(of: 0x61)?.contains(0x41) == true)
        #expect(UnicodeFolding.orbit(of: 0x3000) == nil, "a scalar without case has no orbit")
    }

    @Test func `the orbits include the folds the case mappings alone would get wrong`() {
        #expect(UnicodeFolding.orbit(of: 0x6B) == [0x4B, 0x6B, 0x212A], "k, K and the Kelvin sign")
        #expect(UnicodeFolding.orbit(of: 0x73) == [0x53, 0x73, 0x17F], "s, S and the long s")
        #expect(UnicodeFolding.orbit(of: 0x3C3) == [0x3A3, 0x3C2, 0x3C3], "sigma, final sigma and capital sigma")
        #expect(UnicodeFolding.orbit(of: 0x69) == [0x49, 0x69], "dotless i is not folded with i (a Turkic mapping)")
        #expect(UnicodeFolding.orbit(of: 0x390) == [0x390, 0x1FD3], "an entry that exists only as a simple folding")
        #expect(UnicodeFolding.orbit(of: 0xFB05) == [0xFB05, 0xFB06], "the long-s t and st ligatures")
    }

    @Test func `folding a set adds the other members of every orbit it touches, and nothing else`() throws {
        #expect(ScalarSet(0x6B).folded() == ScalarSet(normalizing: [0x4B ... 0x4B, 0x6B ... 0x6B, 0x212A ... 0x212A]))
        #expect(ScalarSet(0x3000).folded() == ScalarSet(0x3000))
        let letters = ScalarSet(normalizing: [0x61 ... 0x7A])
        let folded = letters.folded()
        #expect(folded.ranges.contains { $0.contains(0x41) } && folded.ranges.contains { $0.contains(0x17F) })
        #expect(folded.folded() == folded, "folding twice changes nothing")
        let everything = ScalarSet(normalizing: [0 ... ScalarSet.maxScalar])
        #expect(everything.folded() == everything)
    }
}
