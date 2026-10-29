internal import AemiKernel

/// A pattern that is only an alternation of fixed-length strings, each position a byte or a small set of bytes, in priority order.
///
/// Such a pattern needs no automaton: at a position the prefilter offers, check the alternatives in order, and the first that fits is
/// the match. That is exactly leftmost-first for fixed strings, since no alternative can backtrack into another.
struct LiteralSet: Sendable {
    /// Every position of every alternative, alternative after alternative, in priority order.
    private let positions: [ByteBitmap]
    /// `positions[starts[k] ..< starts[k + 1]]` is alternative `k`; there is one more entry than there are alternatives.
    private let starts: [Int]

    /// For each byte value `b`, the alternatives whose first position accepts `b`, in priority order:
    /// `byFirstByte[firstByteStarts[b] ..< firstByteStarts[b + 1]]`. A candidate is tried only against these.
    private let byFirstByte: [Int32]
    private let firstByteStarts: [Int32]

    /// The number of alternatives, in priority order.
    var count: Int { starts.count - 1 }

    /// The most alternatives and the longest alternative handled; past these the DFA is the better tool.
    static let maxAlternatives = 64
    static let maxLength = 64
    private static let maxSteps = 20_000

    /// The literals of `program`, or `nil` when it is anything else: it has captures, assertions, a loop, an empty alternative, or
    /// more alternatives or longer ones than the limits.
    /// - Complexity: O(maxSteps).
    init?(_ program: Program) {
        guard program.captureCount == 0 else { return nil }
        var found: [[ByteBitmap]] = []
        var stack: [(pc: Int, path: [ByteBitmap])] = [(0, [])]
        var steps = 0
        while let (start, initial) = stack.popLast() {
            var pc = start
            var path = initial
            walk: while true {
                steps += 1
                guard steps <= Self.maxSteps, path.count <= Self.maxLength else { return nil }
                let instruction = program.instructions[pc]
                switch instruction.op {
                    case .jump: pc += Int(instruction.x)
                    case .split:
                        stack.append((pc + Int(instruction.y), path))
                        pc += Int(instruction.x)
                    case .save: pc += 1
                    case .assertion: return nil
                    case .byteRange:
                        var bytes = ByteBitmap()
                        bytes.insert(UInt8(instruction.x) ... UInt8(instruction.y))
                        path.append(bytes)
                        pc += 1
                    case .byteSet:
                        path.append(program.sets[Int(instruction.x)])
                        pc += 1
                    case .match:
                        guard !path.isEmpty, found.count < Self.maxAlternatives else { return nil }
                        found.append(path)
                        break walk
                }
            }
        }
        positions = found.flatMap { $0 }
        var offsets = [0]
        for alternative in found { offsets.append(offsets[offsets.count - 1] + alternative.count) }
        starts = offsets
        var lists: [Int32] = []
        var listStarts: [Int32] = [0]
        for byte in 0 ... 255 {
            for (index, alternative) in found.enumerated() where alternative[0].contains(UInt8(byte)) {
                lists.append(Int32(index))
            }
            listStarts.append(Int32(lists.count))
        }
        byFirstByte = lists
        firstByteStarts = listStarts
    }

    /// The leftmost match: the prefilter offers candidate starts, and each is checked against the alternatives that can start with its
    /// first byte, in priority order.
    ///
    /// Memory safety: `positions` is read only at indices below `starts.last`, which equals `positions.count` by construction;
    /// `byFirstByte` only inside `firstByteStarts[byte] ..< firstByteStarts[byte + 1]`, and `firstByteStarts` has 257 entries; the
    /// haystack is read at `candidate + offset` only after `candidate + length <= haystack.count`, and a candidate is never negative.
    func firstMatch(in haystack: UnsafeBufferPointer<UInt8>, from: Int, prefilter: Prefilter) -> Range<Int>? {
        let size = haystack.count
        return positions.withUnsafeBufferPointer { sets in
            starts.withUnsafeBufferPointer { bounds in
                byFirstByte.withUnsafeBufferPointer { lists in
                    firstByteStarts.withUnsafeBufferPointer { listStarts in
                        unsafe prefilter.firstVerified(in: haystack, from: from) { candidate -> Range<Int>? in
                            guard candidate >= 0, candidate < size else { return nil }
                            let byte = Int(unsafe haystack[candidate])
                            for slot in Int(unsafe listStarts[byte]) ..< Int(unsafe listStarts[byte + 1]) {
                                let index = Int(unsafe lists[slot])
                                let first = unsafe bounds[index]
                                let length = unsafe bounds[index + 1] - first
                                guard candidate + length <= size else { continue }
                                var offset = 1  // position 0 is known to accept this byte
                                while offset < length,
                                    unsafe sets[first + offset].contains(haystack[candidate + offset])
                                {
                                    offset += 1
                                }
                                if offset == length { return candidate ..< candidate + length }
                            }
                            return nil
                        }
                    }
                }
            }
        }
    }
}
