/// Why a backtracking search stopped without an answer.
public enum BacktrackError: Error, Equatable, Sendable {
    /// The search used up a budget before it could say whether there is a match.
    case budgetExceeded(Exhausted)

    /// Which budget ran out.
    public enum Exhausted: Equatable, Sendable {
        /// ``BacktrackingPattern/Budget/maxSteps`` instructions were executed.
        case steps
        /// ``BacktrackingPattern/Budget/maxStackEntries`` choice points and undo records were held at once.
        case stack
        /// Subroutine calls nested deeper than ``BacktrackingPattern/Budget/maxRecursionDepth``.
        case recursion
    }
}
