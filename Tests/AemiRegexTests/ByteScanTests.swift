import Testing

@testable import AemiRegex

struct ByteScanTests {
    private static let sizes = [0, 1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65, 100, 257]

    /// A buffer of `size` bytes from a small alphabet, so every needle occurs, with some dense and some sparse runs.
    private static func buffer(size: Int, seed: UInt8) -> [UInt8] {
        (0 ..< size)
            .map { i in
                let mixed = UInt8(truncatingIfNeeded: i &* 37 &+ Int(seed) &* 11)
                return mixed % 7 == 0 ? 0x61 : (mixed % 11 == 0 ? 0x62 : 0x78)
            }
    }

    private static func naive(_ bytes: [UInt8], from: Int, _ predicate: (Int) -> Bool) -> Int? {
        (from ..< bytes.count).first(where: predicate)
    }

    @Test(arguments: sizes)
    func `a single byte is found at the first position from every start offset`(size: Int) {
        let bytes = Self.buffer(size: size, seed: 3)
        for needle: UInt8 in [0x61, 0x62, 0x78, 0x7A] {
            for from in 0 ... size {
                let expected = Self.naive(bytes, from: from) { bytes[$0] == needle }
                let actual = bytes.withUnsafeBufferPointer { ByteScan.firstIndex(of: needle, in: $0, from: from) }
                #expect(actual == expected, "needle \(needle) from \(from) in \(size) bytes")
            }
        }
    }

    @Test(arguments: sizes)
    func `a byte pair is found only where both bytes are adjacent`(size: Int) {
        let bytes = Self.buffer(size: size, seed: 5)
        for (first, second): (UInt8, UInt8) in [(0x61, 0x62), (0x78, 0x78), (0x62, 0x61), (0x7A, 0x61)] {
            for from in 0 ... size {
                let expected = Self.naive(bytes, from: from) {
                    $0 + 1 < size && bytes[$0] == first && bytes[$0 + 1] == second
                }
                let actual = bytes.withUnsafeBufferPointer {
                    ByteScan.firstIndex(ofPair: first, second, in: $0, from: from)
                }
                #expect(actual == expected, "pair \(first),\(second) from \(from) in \(size) bytes")
            }
        }
    }

    @Test(arguments: sizes)
    func `any byte of a small set is found at the first position`(size: Int) {
        let bytes = Self.buffer(size: size, seed: 9)
        let sets: [[UInt8]] = [
            [0x61], [0x61, 0x62], [0x62, 0x7A], [0x61, 0x62, 0x78, 0x7A, 0x41, 0x42, 0x43, 0x44], [0x7A, 0x7B]
        ]
        for set in sets {
            for from in 0 ... size {
                let expected = Self.naive(bytes, from: from) { set.contains(bytes[$0]) }
                let actual = bytes.withUnsafeBufferPointer { ByteScan.firstIndex(ofAny: set, in: $0, from: from) }
                #expect(actual == expected, "set \(set) from \(from) in \(size) bytes")
            }
        }
    }

    @Test func `a start offset outside the buffer finds nothing instead of reading out of bounds`() {
        let bytes: [UInt8] = [0x61, 0x61]
        bytes.withUnsafeBufferPointer {
            #expect(ByteScan.firstIndex(of: 0x61, in: $0, from: 3) == nil)
            #expect(ByteScan.firstIndex(of: 0x61, in: $0, from: -1) == nil)
            #expect(ByteScan.firstIndex(ofPair: 0x61, 0x61, in: $0, from: 2) == nil)
        }
    }

    /// The bytes just past the end are made to look like a match, so a scan that reads past the end reports a position it must not.
    /// An overread returns the same answers on clean memory, so only a poisoned tail (or ASan) can see it.
    @Test(arguments: sizes)
    func `no scan reads or reports anything past the end of the buffer`(size: Int) {
        guard size > 0 else { return }
        var storage = [UInt8](repeating: 0x78, count: size)
        storage[size - 1] = 0x61
        storage += [UInt8](repeating: 0x62, count: 40)
        storage.withUnsafeBufferPointer { whole in
            let body = UnsafeBufferPointer(rebasing: whole[0 ..< size])
            #expect(ByteScan.firstIndex(ofPair: 0x61, 0x62, in: body, from: 0) == nil, "pair, \(size) bytes")
            #expect(ByteScan.firstIndex(of: 0x62, in: body, from: 0) == nil, "single, \(size) bytes")
            #expect(ByteScan.firstIndex(ofAny: [0x62, 0x63], in: body, from: 0) == nil, "set, \(size) bytes")
        }
    }
}
