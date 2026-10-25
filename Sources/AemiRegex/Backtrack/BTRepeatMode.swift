/// How a quantifier chooses between taking one more repetition and stopping.
enum BTRepeatMode: Sendable {
    case greedy
    case lazy
    /// Takes as many as it can and never gives one back (`a*+`).
    case possessive
}
