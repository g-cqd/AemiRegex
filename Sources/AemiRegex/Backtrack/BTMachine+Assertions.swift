internal import AemiKernel
internal import AemiUnicode

extension BTMachine {
    /// Whether `assertion` holds at `pos`.
    func holds(_ assertion: BTAssertion, in bytes: CheckedBytes, at pos: Int) -> Bool {
        switch assertion {
            case .beginText: return pos == 0
            case .endText: return pos == bytes.count
            case .endTextBeforeFinalNewline:
                return pos == bytes.count || (pos == bytes.count - 1 && bytes[pos] == 0x0A)
            case .beginLine:
                if pos == 0 { return true }
                guard let before = UTF8Scalar.scalar(bytes, before: pos), lineTerminators.contains(before.value)
                else {
                    return false
                }
                // PCRE2 does not start a line after a newline that ends the text; ECMAScript does.
                return program.dialect == .ecmaScript || pos < bytes.count
            case .endLine:
                if pos == bytes.count { return true }
                guard let after = UTF8Scalar.scalar(bytes, at: pos) else { return false }
                return lineTerminators.contains(after.value)
            case .wordBoundary: return isWord(before: pos, in: bytes) != isWord(after: pos, in: bytes)
            case .notWordBoundary: return isWord(before: pos, in: bytes) == isWord(after: pos, in: bytes)
            case .wordBoundaryFolded:
                return isWord(before: pos, in: bytes, folded: true) != isWord(after: pos, in: bytes, folded: true)
            case .notWordBoundaryFolded:
                return isWord(before: pos, in: bytes, folded: true) == isWord(after: pos, in: bytes, folded: true)
        }
    }

    private func isWord(before pos: Int, in bytes: CheckedBytes, folded: Bool = false) -> Bool {
        guard pos > 0 else { return false }
        if Self.isWordByte(bytes[pos - 1]) { return true }
        return folded && UTF8Scalar.scalar(bytes, before: pos).map { Self.isFoldedWord($0.value) } == true
    }

    private func isWord(after pos: Int, in bytes: CheckedBytes, folded: Bool = false) -> Bool {
        guard pos < bytes.count else { return false }
        if Self.isWordByte(bytes[pos]) { return true }
        return folded && UTF8Scalar.scalar(bytes, at: pos).map { Self.isFoldedWord($0.value) } == true
    }

    private static func isFoldedWord(_ scalar: UInt32) -> Bool { scalar == 0x17F || scalar == 0x212A }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
            || byte == 0x5F
    }
}
