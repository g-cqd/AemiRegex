/// A borrowed run of bytes, read with a bounds check on every access, in release builds too.
///
/// The searches take a buffer so that a `[UInt8]` and a `String`'s UTF-8 are searched in place, without a copy. The Pike VM reads through
/// this type: it is the bounds-checked reference the faster engines are tested against, and it stays bounds-checked. The DFA, the prefilter
/// and the literal matcher take the underlying pointer (``buffer``) and carry their own invariants.
///
/// `@safe` states the interface is memory safe: the only way to read through it is the checked subscript. The buffer must outlive the value;
/// both are created inside a `withUnsafeBufferPointer`-style scope and never stored.
@safe struct ByteBuffer {
    /// The underlying bytes, for the code that does its own bounds reasoning. Using it is unsafe; ``count`` and the subscript are not.
    @unsafe let buffer: UnsafeBufferPointer<UInt8>

    init(_ buffer: UnsafeBufferPointer<UInt8>) { unsafe self.buffer = buffer }

    var count: Int { unsafe buffer.count }

    /// The byte at `index`. Stops the program if the index is outside the buffer.
    subscript(index: Int) -> UInt8 {
        let size = unsafe buffer.count
        precondition(index >= 0 && index < size, "byte index \(index) outside a buffer of \(size)")
        return unsafe buffer[index]
    }
}
