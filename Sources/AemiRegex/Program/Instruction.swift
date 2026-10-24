/// One step of a compiled program. Jump targets are offsets relative to the instruction itself, so a fragment can be copied
/// (for `x{n,m}`) without relocating anything.
struct Instruction: Equatable, Sendable {
    enum Op: UInt8, Sendable {
        /// Consume one byte in `x ... y`.
        case byteRange
        /// Consume one byte in the set `x` of ``Program/sets``.
        case byteSet
        /// Continue at `pc + x` first, then at `pc + y`.
        case split
        /// Continue at `pc + x`.
        case jump
        /// Record the position in capture slot `x`.
        case save
        /// Continue at `pc + 1` only if ``Assertion`` `x` holds at the position.
        case assertion
        /// The pattern matched.
        case match
    }

    var op: Op
    var x: Int32
    var y: Int32

    static func byteRange(_ lo: UInt8, _ hi: UInt8) -> Instruction {
        Instruction(op: .byteRange, x: Int32(lo), y: Int32(hi))
    }
    static func byteSet(_ index: Int) -> Instruction {
        Instruction(op: .byteSet, x: Int32(truncatingIfNeeded: index), y: 0)
    }
    static func split(_ first: Int, _ second: Int) -> Instruction {
        Instruction(op: .split, x: Int32(truncatingIfNeeded: first), y: Int32(truncatingIfNeeded: second))
    }
    static func jump(_ offset: Int) -> Instruction {
        Instruction(op: .jump, x: Int32(truncatingIfNeeded: offset), y: 0)
    }
    static func save(_ slot: Int) -> Instruction { Instruction(op: .save, x: Int32(truncatingIfNeeded: slot), y: 0) }
    static func assertion(_ kind: Assertion) -> Instruction {
        Instruction(op: .assertion, x: Int32(kind.rawValue), y: 0)
    }
    static let match = Instruction(op: .match, x: 0, y: 0)
}

/// A zero-width condition on the position.
enum Assertion: UInt8, Sendable {
    case beginText, endText, beginLine, endLine, wordBoundary, notWordBoundary
}
