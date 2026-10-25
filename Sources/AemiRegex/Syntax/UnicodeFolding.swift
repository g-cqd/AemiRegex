/// Simple case folding: the orbits of scalars that fold to each other (`k`, `K` and the Kelvin sign), from Go's tables.
///
/// The standard library's case mappings are not enough: derived from them the orbits are wrong in five places (probe in ADR-0009),
/// among them `ı`, which a mapping folds with `I` and the simple folding does not.
enum UnicodeFolding {
    /// The members of the orbit `scalar` belongs to, ascending, or `nil` when it has no case partners.
    /// - Complexity: O(log orbits).
    static func orbit(of scalar: UInt32) -> [UInt32]? {
        let index = GeneratedUnicodeTables.foldIndex
        var low = 0
        var high = index.count / 2 - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = index[2 * middle]
            if candidate == scalar {
                var members: [UInt32] = []
                var cursor = Int(index[2 * middle + 1])
                while GeneratedUnicodeTables.foldOrbits[cursor] != 0 {
                    members.append(GeneratedUnicodeTables.foldOrbits[cursor])
                    cursor += 1
                }
                return members
            }
            if candidate < scalar { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }

    /// Every orbit, each ascending.
    static let orbits: [[UInt32]] = {
        var result: [[UInt32]] = []
        var current: [UInt32] = []
        for value in GeneratedUnicodeTables.foldOrbits {
            if value == 0 {
                result.append(current)
                current = []
            } else {
                current.append(value)
            }
        }
        return result
    }()
}

extension ScalarSet {
    /// Whether `value` is in the set.
    /// - Complexity: O(log ranges).
    func contains(_ value: UInt32) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if value < ranges[middle].lowerBound {
                high = middle - 1
            } else if value > ranges[middle].upperBound {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    /// The set plus every scalar that folds to a member: for each orbit the set touches, all of the orbit.
    ///
    /// A set of a few scalars (a literal) looks each one up; a larger set is checked against every orbit.
    /// - Complexity: O(scalars log orbits) for a small set, O(orbits log ranges) otherwise.
    func folded() -> ScalarSet {
        var extra: [ClosedRange<UInt32>] = []
        var size = 0
        for range in ranges { size += Int(range.upperBound - range.lowerBound) + 1 }
        if size <= 64 {
            for range in ranges {
                for value in range {
                    guard let orbit = UnicodeFolding.orbit(of: value) else { continue }
                    for member in orbit where !contains(member) { extra.append(member ... member) }
                }
            }
        } else {
            for orbit in UnicodeFolding.orbits where orbit.contains(where: { contains($0) }) {
                for member in orbit where !contains(member) { extra.append(member ... member) }
            }
        }
        return extra.isEmpty ? self : ScalarSet(normalizing: ranges + extra)
    }
}
