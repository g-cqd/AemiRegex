extension Pattern: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { pattern }

    public var debugDescription: String {
        "Pattern(/\(pattern)/, syntax: .\(syntax))"
    }
}
