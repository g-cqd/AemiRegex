import Testing

@testable import AemiRegex

/// `ByteBuffer` is declared `@safe`: its only way to read is a subscript that checks the index in release builds too. A claim like that is
/// only worth what a test of the trap is worth, so the out-of-range reads are run in a child process that must die.
struct ByteBufferTests {
    @Test func `reads inside the buffer return the bytes`() {
        let bytes: [UInt8] = [10, 20, 30]
        bytes.withUnsafeBufferPointer { raw in
            let buffer = ByteBuffer(raw)
            #expect(buffer.count == 3)
            #expect(buffer[0] == 10 && buffer[1] == 20 && buffer[2] == 30)
        }
    }

    @Test func `a read one past the end stops the program`() async {
        await #expect(processExitsWith: .failure) {
            let bytes: [UInt8] = [1, 2, 3]
            bytes.withUnsafeBufferPointer { raw in _ = ByteBuffer(raw)[3] }
        }
    }

    @Test func `a negative read stops the program`() async {
        await #expect(processExitsWith: .failure) {
            let bytes: [UInt8] = [1, 2, 3]
            bytes.withUnsafeBufferPointer { raw in _ = ByteBuffer(raw)[-1] }
        }
    }

    @Test func `any read of an empty buffer stops the program`() async {
        await #expect(processExitsWith: .failure) {
            let bytes: [UInt8] = []
            bytes.withUnsafeBufferPointer { raw in _ = ByteBuffer(raw)[0] }
        }
    }
}
