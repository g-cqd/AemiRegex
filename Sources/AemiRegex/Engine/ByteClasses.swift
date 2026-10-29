internal import AemiKernel

/// Partitions the 256 byte values into classes that no instruction of the program tells apart, so a DFA row has one entry per
/// class instead of one per byte.
struct ByteClasses: Sendable {
    /// The class of each byte.
    let map: [UInt8]
    /// What a byte of each class is to an assertion: 1 newline, 2 word byte, 3 other. Meaningful only when the program has
    /// assertions, which is when the classes are also split along these lines.
    let contexts: [UInt8]
    let count: Int
    /// One byte of each class, to evaluate an instruction against the whole class.
    let representatives: [UInt8]

    /// - Complexity: O(instructions + 256 × distinct byte sets).
    init(_ program: Program) {
        var boundary = [Bool](repeating: false, count: 257)
        for instruction in program.instructions where instruction.op == .byteRange {
            boundary[Int(instruction.x)] = true
            boundary[Int(instruction.y) + 1] = true
        }
        for set in program.sets {
            for byte in 1 ... 255 where set.contains(UInt8(byte)) != set.contains(UInt8(byte - 1)) {
                boundary[byte] = true
            }
        }
        if program.instructions.contains(where: { $0.op == .assertion }) {
            for edge in [0x0A, 0x0B, 0x30, 0x3A, 0x41, 0x5B, 0x5F, 0x60, 0x61, 0x7B] { boundary[edge] = true }
        }
        var map = [UInt8](repeating: 0, count: 256)
        var representatives: [UInt8] = [0]
        for byte in 1 ... 255 {
            if boundary[byte] { representatives.append(UInt8(byte)) }
            map[byte] = UInt8(representatives.count - 1)
        }
        self.map = map
        self.representatives = representatives
        contexts = representatives.map { UInt8(NeighborContext.of($0)) }
        count = representatives.count
    }
}
