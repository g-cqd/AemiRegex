/// What one search strategy says: the answer, which may be "no match", or that it could not answer and the next strategy must run.
enum SearchAttempt {
    case answer(Match?)
    case gaveUp
}
