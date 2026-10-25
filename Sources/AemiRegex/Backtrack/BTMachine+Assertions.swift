extension BTMachine {
    /// Whether `assertion` holds at `pos`.
    func holds(_ assertion: BTAssertion, in bytes: ByteBuffer, at pos: Int) -> Bool {
        switch assertion {
            case .beginText: return pos == 0
            case .endText: return pos == bytes.count
            case .endTextBeforeFinalNewline:
                return pos == bytes.count || (pos == bytes.count - 1 && bytes[pos] == 0x0A)
            case .beginLine:
                if pos == 0 { return true }
                guard let before = ScalarReader.scalar(in: bytes, before: pos), lineTerminators.contains(before.value)
                else {
                    return false
                }
                // PCRE2 does not start a line after a newline that ends the text; ECMAScript does.
                return program.dialect == .ecmaScript || pos < bytes.count
            case .endLine:
                if pos == bytes.count { return true }
                guard let after = ScalarReader.scalar(in: bytes, at: pos) else { return false }
                return lineTerminators.contains(after.value)
            case .wordBoundary: return isWord(before: pos, in: bytes) != isWord(after: pos, in: bytes)
            case .notWordBoundary: return isWord(before: pos, in: bytes) == isWord(after: pos, in: bytes)
        }
    }

    private func isWord(before pos: Int, in bytes: ByteBuffer) -> Bool {
        pos > 0 && Self.isWordByte(bytes[pos - 1])
    }

    private func isWord(after pos: Int, in bytes: ByteBuffer) -> Bool {
        pos < bytes.count && Self.isWordByte(bytes[pos])
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (0x30 ... 0x39).contains(byte) || (0x41 ... 0x5A).contains(byte) || (0x61 ... 0x7A).contains(byte)
            || byte == 0x5F
    }
}
