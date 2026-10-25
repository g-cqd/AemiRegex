extension BacktrackingPattern: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { pattern }

    public var debugDescription: String {
        "BacktrackingPattern(/\(pattern)/, dialect: .\(dialect))"
    }
}
