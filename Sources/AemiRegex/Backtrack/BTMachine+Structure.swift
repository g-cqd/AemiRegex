extension BTMachine {
    /// Runs the instructions that open and close structure: calls, conditions, look-arounds and atomic groups.
    mutating func executeStructure(
        _ instruction: BTInstruction, pc: inout Int, pos: inout Int
    ) throws(BacktrackError) -> Step {
        var ok = true
        switch instruction.op {
            case .call:
                ok = try enterCall(group: Int(instruction.y), returnPC: pc + 1, pos: pos)
                pc += Int(instruction.x)
            case .condGroup:
                let group = Int(instruction.x)
                pc += slots[2 * group + 1] >= 0 ? 1 : Int(instruction.y)
            case .condRecursion:
                let inside =
                    currentFrame >= 0 && (instruction.x < 0 || callFrames[currentFrame].group == Int(instruction.x))
                pc += inside ? 1 : Int(instruction.y)
            case .lookStart:
                marks.append(stack.count)
                if instruction.x == 0 {
                    try push(.lookPositive, 0, pos)
                } else {
                    try push(.lookNegative, pc + Int(instruction.y), pos)
                }
                pc += 1
            case .lookEnd:
                guard let mark = marks.popLast() else { return .failed }
                switch instruction.x {
                    case 1:
                        undo(to: mark)
                        ok = false
                    case 5:
                        pos = stack[mark].b
                        undo(to: mark)
                        pc += Int(instruction.y)
                    default:
                        pos = stack[mark].b
                        close(mark)
                        pc += 1
                }
            case .atomicStart:
                marks.append(stack.count)
                try push(.atomicOpen, 0, pos)
                pc += 1
            case .atomicEnd:
                guard let mark = marks.popLast() else { return .failed }
                close(mark)
                pc += 1
            default:
                break
        }
        return ok ? .next : .failed
    }
}
