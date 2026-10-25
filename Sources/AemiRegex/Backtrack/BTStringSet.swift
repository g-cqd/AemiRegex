/// What a class in ECMAScript's `v` mode denotes: single scalars, and the strings of `\q{…}` (each of any length, the empty one too).
struct BTStringSet: Equatable {
    var scalars = ScalarSet()
    /// Strings other than one-scalar ones, which belong in `scalars`.
    var strings: Set<[UInt32]> = []

    init() {}

    init(scalars: ScalarSet) { self.scalars = scalars }

    /// Adds a string, moving a one-scalar string into the scalar set.
    mutating func insert(_ string: [UInt32]) {
        if string.count == 1 {
            scalars = scalars.union(ScalarSet(string[0]))
        } else {
            strings.insert(string)
        }
    }

    func union(_ other: BTStringSet) -> BTStringSet {
        var result = BTStringSet(scalars: scalars.union(other.scalars))
        result.strings = strings.union(other.strings)
        return result
    }

    func intersection(_ other: BTStringSet) -> BTStringSet {
        var result = BTStringSet(scalars: scalars.intersection(other.scalars))
        result.strings = strings.intersection(other.strings)
        return result
    }

    func subtracting(_ other: BTStringSet) -> BTStringSet {
        var result = BTStringSet(scalars: scalars.subtracting(other.scalars))
        result.strings = strings.subtracting(other.strings)
        return result
    }

    /// Applies `transform` to the scalars; used to fold case.
    func mappingScalars(_ transform: (ScalarSet) -> ScalarSet) -> BTStringSet {
        var result = self
        result.scalars = transform(scalars)
        return result
    }
}
