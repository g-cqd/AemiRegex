struct SearchScratch {
    var forward: LazyDFA?
    var reverse: LazyDFA?
    var pike: PikeVM
    var counts = SearchCounts()
}
