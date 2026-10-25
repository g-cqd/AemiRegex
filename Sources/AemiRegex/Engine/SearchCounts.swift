/// How many searches each engine answered, kept so a test can tell which engine ran (an answer alone cannot: the engines agree).
struct SearchCounts: Equatable, Sendable {
    var literal = 0
    var dfa = 0
    var pike = 0
}
