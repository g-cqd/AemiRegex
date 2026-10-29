import AemiUnicode
import Testing

@testable import AemiRegex

/// The property-name rules Go's `regexp` applies over AemiUnicode's `UnicodeData` (ADR-0013). The tables themselves are tested in aemi
/// (`UnicodeDataTests`: the standard library and their own invariants); `GoldenTests` checks what the engine does with them against Go.
struct UnicodeTablesTests {
    private static func set(_ name: String) -> UnicodeScalarSet? { UnicodeProperties.set(named: name) }

    private static let codes = Array(
        "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn"
            .split(separator: " ").map(String.init))

    // MARK: Categories

    @Test func `the groups, Cn, C and LC are what their members make them`() throws {
        func union(_ names: [String]) throws -> UnicodeScalarSet {
            try names.reduce(UnicodeScalarSet()) { try $0.union(#require(Self.set($1))) }
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
}
