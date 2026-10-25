/// Compiles a ``BTSyntaxTree`` to a ``BTProgram``. The walk is post-order over an explicit work stack, so no tree can overflow the call stack.
struct BTCompiler {
    let tree: BTSyntaxTree
    let dialect: BacktrackingPattern.Dialect
    let limits: Pattern.Limits
    var registerCount = 0
    /// The lengths of the groups compiled so far, so a PCRE2 look-behind can size a back reference to one.
    var groupLengths: [Int: (min: Int, max: Int?)] = [:]

    private struct Work {
        var node: Int
        var backward: Bool
        var expanded: Bool
    }

    static func compile(
        _ tree: BTSyntaxTree, dialect: BacktrackingPattern.Dialect, limits: Pattern.Limits
    ) throws(PatternError) -> BTProgram {
        var compiler = BTCompiler(tree: tree, dialect: dialect, limits: limits)
        var code = try compiler.run()
        try patchCalls(in: &code)
        code.append(BTInstruction(.match))
        return BTProgram(
            code: ContiguousArray(code), sets: tree.sets, captureCount: tree.captureCount,
            registerCount: compiler.registerCount, dialect: dialect, names: tree.names)
    }

    private mutating func run() throws(PatternError) -> [BTInstruction] {
        var work = [Work(node: tree.root, backward: false, expanded: false)]
        var results: [BTFragment] = []
        while let item = work.popLast() {
            let node = tree.nodes[item.node]
            let operands = operandNodes(of: node)
            let count = operands.count
            if !item.expanded, count > 0 {
                work.append(Work(node: item.node, backward: item.backward, expanded: true))
                var childBackward = item.backward
                // ECMAScript reads a look-behind backwards; PCRE2 steps back and reads it forwards.
                if case .look(let behind, _) = node.kind { childBackward = behind && dialect == .ecmaScript }
                for child in operands.reversed() {
                    work.append(Work(node: child, backward: childBackward, expanded: false))
                }
                continue
            }
            let children = Array(results.suffix(count))
            results.removeLast(count)
            let fragment = try emit(node, children, backward: item.backward)
            guard fragment.code.count <= limits.maxProgramSize else { throw .limit(.programSize) }
            results.append(fragment)
        }
        return results.last?.code ?? []
    }

    /// The nodes whose code a node is built from: its children, except that a PCRE2 look-behind is built from the branches of its body,
    /// because each branch has its own length.
    private func operandNodes(of node: BTNode) -> [Int] {
        guard case .look(let behind, _) = node.kind, behind, dialect == .pcre2,
            case .alternation = tree.nodes[node.children[0]].kind
        else { return node.children }
        return tree.nodes[node.children[0]].children
    }

    private mutating func emit(
        _ node: BTNode, _ children: [BTFragment], backward: Bool
    ) throws(PatternError) -> BTFragment {
        switch node.kind {
            case .empty:
                return BTFragment(code: [], canBeEmpty: true, groups: nil)
            case .fail:
                return BTFragment(code: [BTInstruction(.fail)], canBeEmpty: false, groups: nil)
            case .keep:
                return BTFragment(code: [BTInstruction(.keep)], canBeEmpty: true, groups: nil)
            case .call(let group):
                return call(group: group)
            case .namedCall(let name):
                guard let group = tree.names[name]?.first else { throw .syntax(.invalidGroupName, offset: 0) }
                return call(group: group)
            case .conditional(let condition):
                return try conditional(condition, children)
            case .set(let index):
                let ranges = tree.sets[index].scalars.ranges
                if ranges.count == 1, let only = ranges.first, only.lowerBound == only.upperBound {
                    return BTFragment(
                        code: [BTInstruction(.char, backward: backward, Int(only.lowerBound))], canBeEmpty: false,
                        groups: nil, minLength: 1, maxLength: 1)
                }
                return BTFragment(
                    code: [BTInstruction(.set, backward: backward, index)], canBeEmpty: false, groups: nil,
                    minLength: 1,
                    maxLength: 1)
            case .assertion(let assertion):
                return BTFragment(
                    code: [BTInstruction(.assertion, Int(assertion.rawValue))], canBeEmpty: true, groups: nil)
            case .backReference(let group, let ignoreCase):
                return reference(group: group, ignoreCase: ignoreCase, backward: backward)
            case .namedBackReference(let name, let ignoreCase):
                guard let groups = tree.names[name] else { throw .syntax(.invalidGroupName, offset: 0) }
                return reference(groups: groups, ignoreCase: ignoreCase, backward: backward)
            case .group(let capture):
                let body = children[0]
                let (open, close) = backward ? (2 * capture + 1, 2 * capture) : (2 * capture, 2 * capture + 1)
                // PCRE2 closes a group with a mark that lets a subroutine call to the group return.
                let closing = BTInstruction(.save, close, dialect == .pcre2 ? 1 : 0)
                let own = capture ..< capture + 1
                groupLengths[capture] = (body.minLength, body.maxLength)
                return BTFragment(
                    code: [BTInstruction(.save, open)] + body.code + [closing],
                    canBeEmpty: body.canBeEmpty, groups: BTFragment.merged(body.groups, own),
                    minLength: body.minLength, maxLength: body.maxLength)
            case .concatenation:
                return BTFragment.joining(children, backward: backward)
            case .alternation:
                return alternation(children)
            case .repetition(let min, let max, let mode):
                return try repetition(children[0], min: min, max: max, mode: mode)
            case .look(let behind, let negative):
                let body = behind && dialect == .pcre2 ? try pcreLookbehindBody(children) : children[0]
                let code =
                    [BTInstruction(.lookStart, negative ? 1 : 0, body.code.count + 2)] + body.code
                    + [BTInstruction(.lookEnd, negative ? 1 : 0)]
                return BTFragment(code: code, canBeEmpty: true, groups: body.groups)
            case .atomic:
                let body = children[0]
                return BTFragment(
                    code: [BTInstruction(.atomicStart)] + body.code + [BTInstruction(.atomicEnd)],
                    canBeEmpty: body.canBeEmpty, groups: body.groups, minLength: body.minLength,
                    maxLength: body.maxLength)
        }
    }

    /// A subroutine call whose target is filled in once the whole program exists (see ``patchCalls(in:)``). Its length is unknown.
    private func call(group: Int) -> BTFragment {
        BTFragment(code: [BTInstruction(.call, 0, group)], canBeEmpty: true, groups: nil, minLength: 0, maxLength: nil)
    }

    /// A back reference by name. When several groups share the name, the one that took part is used; if none did, ECMAScript matches empty.
    private func reference(groups: [Int], ignoreCase: Bool, backward: Bool) -> BTFragment {
        guard groups.count > 1 else { return reference(group: groups[0], ignoreCase: ignoreCase, backward: backward) }
        var tail: [BTInstruction] = []
        for group in groups.reversed() {
            let use = reference(group: group, ignoreCase: ignoreCase, backward: backward).code
            tail =
                [BTInstruction(.condGroup, group, use.count + 2)] + use + [BTInstruction(.jump, tail.count + 1)] + tail
        }
        return BTFragment(code: tail, canBeEmpty: true, groups: nil, minLength: 0, maxLength: nil)
    }

    private func reference(group: Int, ignoreCase: Bool, backward: Bool) -> BTFragment {
        // A group not compiled yet is unset when a forward-reading look-behind reaches the reference, so it consumes nothing.
        let length = groupLengths[group] ?? (0, 0)
        return BTFragment(
            code: [BTInstruction(.backReference, backward: backward, group, ignoreCase ? 1 : 0)], canBeEmpty: true,
            groups: nil, minLength: length.min, maxLength: length.max)
    }

    /// `a|b|c`: each branch is tried in order, and the first that leads to a match wins.
    func alternation(_ branches: [BTFragment]) -> BTFragment {
        let total = branches.reduce(0) { $0 + $1.code.count } + 2 * (branches.count - 1)
        var code: [BTInstruction] = []
        code.reserveCapacity(total)
        var groups: Range<Int>?
        for (index, branch) in branches.enumerated() {
            groups = BTFragment.merged(groups, branch.groups)
            if index == branches.count - 1 {
                code += branch.code
            } else {
                code.append(BTInstruction(.split, 1, branch.code.count + 2))
                code += branch.code
                code.append(BTInstruction(.jump, total - code.count))
            }
        }
        return BTFragment(
            code: code, canBeEmpty: branches.contains { $0.canBeEmpty }, groups: groups,
            minLength: branches.map(\.minLength).min() ?? 0,
            maxLength: branches.reduce(0 as Int?) { longest, branch in
                longest.flatMap { top in branch.maxLength.map { max(top, $0) } }
            })
    }
}
