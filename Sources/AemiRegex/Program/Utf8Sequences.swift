/// A closed range of one byte.
struct ByteRange: Equatable, Sendable {
    var lo: UInt8
    var hi: UInt8
}

/// Splits a range of scalar values into the byte-range sequences that match exactly the UTF-8 encodings of its members.
enum Utf8Sequences {
    /// The sequences for `lo ... hi`, in ascending order of scalar value. Surrogates are excluded.
    ///
    /// - Complexity: O(1) in the width of the range: at most a few dozen sequences for any range.
    static func sequences(_ range: ClosedRange<UInt32>) -> [[ByteRange]] {
        var output: [[ByteRange]] = []
        var stack = [range]
        outer: while let current = stack.popLast() {
            let start = current.lowerBound
            let end = current.upperBound
            if start <= 0xDFFF, end >= 0xD800 {
                if end > 0xDFFF { stack.append(0xE000 ... end) }
                if start < 0xD800 { stack.append(start ... 0xD7FF) }
                continue
            }
            for max: UInt32 in [0x7F, 0x7FF, 0xFFFF] where start <= max && max < end {
                stack.append((max + 1) ... end)
                stack.append(start ... max)
                continue outer
            }
            if end <= 0x7F {
                output.append([ByteRange(lo: UInt8(start), hi: UInt8(end))])
                continue
            }
            for shift in [6, 12, 18] {
                let mask: UInt32 = (1 << UInt32(shift)) - 1
                guard (start & ~mask) != (end & ~mask) else { continue }
                if start & mask != 0 {
                    stack.append(((start | mask) + 1) ... end)
                    stack.append(start ... (start | mask))
                    continue outer
                }
                if end & mask != mask {
                    stack.append((end & ~mask) ... end)
                    stack.append(start ... ((end & ~mask) - 1))
                    continue outer
                }
            }
            let low = encode(start)
            let high = encode(end)
            output.append(zip(low, high).map { ByteRange(lo: $0, hi: $1) })
        }
        return output
    }

    /// The UTF-8 encoding of a scalar value that is not a surrogate.
    static func encode(_ scalar: UInt32) -> [UInt8] {
        switch scalar {
            case 0 ..< 0x80: [UInt8(scalar)]
            case 0x80 ..< 0x800: [0xC0 | UInt8(scalar >> 6), 0x80 | UInt8(scalar & 0x3F)]
            case 0x800 ..< 0x10000:
                [0xE0 | UInt8(scalar >> 12), 0x80 | UInt8((scalar >> 6) & 0x3F), 0x80 | UInt8(scalar & 0x3F)]
            default:
                [
                    0xF0 | UInt8(scalar >> 18), 0x80 | UInt8((scalar >> 12) & 0x3F),
                    0x80 | UInt8((scalar >> 6) & 0x3F), 0x80 | UInt8(scalar & 0x3F)
                ]
        }
    }
}
