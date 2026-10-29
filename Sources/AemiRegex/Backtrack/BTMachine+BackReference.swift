internal import AemiKernel
internal import AemiUnicode

extension BTMachine {
    /// Consumes the text group `x` captured. A group that did not capture matches empty in ECMAScript and fails in PCRE2.
    func reference(_ instruction: BTInstruction, in bytes: CheckedBytes, at pos: inout Int) throws(BacktrackError)
        -> Bool
    {
        let group = Int(instruction.x)
        let (open, close) = (slots[2 * group], slots[2 * group + 1])
        guard open >= 0, close >= open else { return program.dialect == .ecmaScript }
        let foldCase = instruction.y == 1
        var captured = instruction.backward ? close : open
        var text = pos
        while instruction.backward ? captured > open : captured < close {
            let wanted =
                instruction.backward
                ? UTF8Scalar.scalar(bytes, before: captured) : UTF8Scalar.scalar(bytes, at: captured)
            let seen =
                instruction.backward
                ? UTF8Scalar.scalar(bytes, before: text) : UTF8Scalar.scalar(bytes, at: text)
            guard let wanted, let seen, Self.equal(wanted.value, seen.value, foldCase: foldCase) else { return false }
            captured += instruction.backward ? -wanted.width : wanted.width
            text += instruction.backward ? -seen.width : seen.width
        }
        pos = text
        return true
    }

    private static func equal(_ a: UInt32, _ b: UInt32, foldCase: Bool) -> Bool {
        if a == b { return true }
        guard foldCase, let orbit = CaseFolding.simpleOrbit(of: a) else { return false }
        return orbit.contains(b)
    }
}
