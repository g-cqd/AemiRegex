/// Why a pattern was rejected. Every case that points into the pattern carries the UTF-8 byte offset.
public enum PatternError: Error, Equatable, Sendable {
    /// The syntax is malformed at `offset`; `reason` says how.
    case syntax(Reason, offset: Int)
    /// A limit in ``Pattern/Limits`` was exceeded.
    case limit(Limit)

    /// What is wrong with the syntax.
    public enum Reason: Equatable, Sendable {
        case unexpectedEnd
        case unmatchedOpenParen
        case unmatchedCloseParen
        case unterminatedClass
        case invalidClassRange
        case invalidEscape
        case invalidRepetition
        case nestedRepetition
        case repetitionWithoutOperand
        case invalidGroupSyntax
        case invalidFlag
        case invalidGroupName
        case duplicateGroupName
        case unknownClassName
        case invalidScalar
        case unsupported
        /// A character that the dialect does not allow where it appears.
        case invalidCharacter
    }

    /// Which limit a pattern exceeded.
    public enum Limit: Equatable, Sendable {
        case patternLength
        case nestingDepth
        case programSize
        case repetitionCount
        case captureCount
    }
}
