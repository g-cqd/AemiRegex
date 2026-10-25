/// What a character escape such as `\n` or `\d` stands for.
enum BTEscaped: Equatable {
    case scalar(UInt32)
    case set(ScalarSet)
}
