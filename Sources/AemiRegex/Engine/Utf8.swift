/// UTF-8 decoding helpers for scalar boundaries in a byte haystack that may not be valid UTF-8.
enum Utf8 {
    /// The width of the valid UTF-8 scalar that starts at `index`, or 1 when the bytes there are not a valid scalar.
    static func width(of bytes: [UInt8], at index: Int) -> Int {
        let lead = bytes[index]
        let expected: Int
        var lowest: UInt8 = 0x80
        var highest: UInt8 = 0xBF
        switch lead {
            case 0x00 ... 0x7F: return 1
            case 0xC2 ... 0xDF: expected = 2
            case 0xE0:
                expected = 3
                lowest = 0xA0
            case 0xE1 ... 0xEC, 0xEE ... 0xEF: expected = 3
            case 0xED:
                expected = 3
                highest = 0x9F
            case 0xF0:
                expected = 4
                lowest = 0x90
            case 0xF1 ... 0xF3: expected = 4
            case 0xF4:
                expected = 4
                highest = 0x8F
            default: return 1
        }
        guard index + expected <= bytes.count else { return 1 }
        guard (lowest ... highest).contains(bytes[index + 1]) else { return 1 }
        for offset in 2 ..< expected where !(0x80 ... 0xBF).contains(bytes[index + offset]) { return 1 }
        return expected
    }
}
