/// Reads one Unicode scalar at a position of bytes that may not be valid UTF-8, forward or backward.
enum ScalarReader {
    /// The scalar that starts at `index` and its width, or `nil` at the end or where the bytes are not a valid scalar.
    static func scalar(in bytes: ByteBuffer, at index: Int) -> (value: UInt32, width: Int)? {
        guard index >= 0, index < bytes.count else { return nil }
        let lead = bytes[index]
        if lead < 0x80 { return (UInt32(lead), 1) }
        let width = Utf8.width(of: bytes, at: index)
        switch width {
            case 2:
                return ((UInt32(lead & 0x1F) << 6) | UInt32(bytes[index + 1] & 0x3F), 2)
            case 3:
                let value =
                    (UInt32(lead & 0x0F) << 12) | (UInt32(bytes[index + 1] & 0x3F) << 6)
                    | UInt32(bytes[index + 2] & 0x3F)
                return (value, 3)
            case 4:
                let value =
                    (UInt32(lead & 0x07) << 18) | (UInt32(bytes[index + 1] & 0x3F) << 12)
                    | (UInt32(bytes[index + 2] & 0x3F) << 6) | UInt32(bytes[index + 3] & 0x3F)
                return (value, 4)
            default:
                return nil
        }
    }

    /// The scalar that ends at `index` and its width, or `nil` at the start or where the bytes before `index` are not a valid scalar.
    static func scalar(in bytes: ByteBuffer, before index: Int) -> (value: UInt32, width: Int)? {
        guard index > 0, index <= bytes.count else { return nil }
        var start = index - 1
        var steps = 0
        while start > 0, steps < 3, bytes[start] & 0xC0 == 0x80 {
            start -= 1
            steps += 1
        }
        guard let found = scalar(in: bytes, at: start), start + found.width == index else { return nil }
        return found
    }

    /// The width of the scalar at `index`, or 1 when the bytes there are not valid, so a search always advances.
    static func step(in bytes: ByteBuffer, at index: Int) -> Int {
        scalar(in: bytes, at: index)?.width ?? 1
    }
}
