/// What the DFA pipeline needs beyond the forward program: the reversed program and the byte classes of both.
struct DFAPlan: Sendable {
    let reverse: Program
    let forwardClasses: ByteClasses
    let reverseClasses: ByteClasses
}
