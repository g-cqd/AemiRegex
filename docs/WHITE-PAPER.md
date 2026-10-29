# AemiRegex — Project White Paper

The rules this project runs on. **Paste this at the start of every iteration.** An iteration that cannot satisfy a rule below stops and
fixes the rule, or asks to change it in writing. It does not quietly proceed. Principles live here and never a log: the log is the diary.

## What this is

A regular-expression engine for Swift, and the generic tool the ecosystem's other packages should use instead of `NSRegularExpression`
or Swift's `Regex`. Consumers are plausible and named: AemiJSON (`SchemaPattern`, JSONPath), `ask` (roadmap 0059 there), and any package
that searches text. The test for living here and not in a consumer is whether a second consumer is plausible, not whether one exists.

## The evidence rule

Every claim is named, given a probe that could fail, run, and recorded in the diary before it is acted on. Three consequences:

- **A probe that cannot fail is not a probe.** A comparison that is not fair is worse than none: the first Teddy probe left both loops
  un-unrolled and understated the gap by about 2x (diary 2026-10-24-01). Check that the probe can show the thing it is for.
- **A test that has never failed proves nothing.** A new gate is broken on purpose once, to prove it fires. A literal matcher that no
  search ever called passed every test, because the DFA gives the same answers; a counter now says which engine answered.
- **Unprobed claims are written as open questions, never as facts.** This includes what another engine does internally.

## Safety is the first goal and a property of the algorithm

Order of goals: correctness, then safety, then speed. Speed never buys back either.

**Linear time by construction.** The default engine has no backtracking: matching time is O(pattern x input) for every pattern, so no
attacker-supplied pattern or input can make a search exponential (ADR-0001). Backreferences, lookaround, atomic groups and possessive
quantifiers cannot run that way and are rejected in the default engine. Covering them is a separate, opt-in engine with a step budget
(ADR-0006); it never changes what the default engine promises.

**Every cost has a limit.** Pattern length, nesting depth, program size, repetition count, capture groups, thread-table entries and
DFA cache bytes are limits with a typed error. A pattern over a limit is refused; it never allocates what it was not given.

**No recursion, anywhere.** Not in the parser, the compiler, the engines, the tests, the scripts. A depth that attacker input controls
is a call-stack overflow, and an unbounded loop is an infinite one, so work goes on an explicit stack and every loop has a bound that
is a limit or a budget (ADR-0003). Generators build level by level, not by calling themselves.

**`unsafe` is confined, justified, and netted** (ADR-0005). Unchecked indexing lives in a few named functions with their invariants
written above them and debug assertions inside. A result that comes back from C is checked, and a violated invariant stops the program:
nothing downstream is trusted. No `-Ounchecked`, no disabled bounds or overflow checks, ever.

**Malformed input is a case, not an edge.** Haystacks are bytes. Invalid UTF-8, truncated and overlong sequences, surrogates and every
byte value are tested against a bounds-checked reference. A match never starts inside a valid scalar and never lies outside the input.

## Speed is a number

**Every change that can affect performance is benchmarked,** before and after, same harness, release build, median and spread. The
comparison is not with Swift's own engines: it is with the fastest available (Rust `regex`, PCRE2 with JIT, Go), per file and on one
buffer, on a frozen corpus (`Scripts/bench-compare.sh`). The standing is **third**: faster than Go, ICU and Swift Regex, slower than Rust
and mostly than PCRE2-JIT. "Fastest" is not a word this project uses until the numbers say it.

**Profile before changing.** Three times in one day a plausible cause was wrong: the scan was not the cost, then verification was not,
then the batch size was. A change that moves no number is reverted.

## Compliance is measured against an oracle

A dialect is compliant when an independent implementation agrees with it on a stated corpus, in CI, and the differences are listed:
Go for RE2 syntax, `pcre2test` for PCRE2, `node` for ECMAScript, the RFC's own grammar for I-Regexp, ICU only where ICU agrees with the
norm (it differs from RE2 on `\b`, `$` and multiline `^`). A divergence is recorded with the oracle's answer, never discovered by a user.
Expected values come from the oracle, not from the author.

## Dependencies

The engine depends on Aemi, the family it belongs to, and on nothing else; no Foundation (ADR-0013). Its byte kernels (the multi-literal
kernel, which Swift cannot express, under the bar of ADR-0004), UTF-8 reading, scratch pool and generated Unicode data are Aemi's, so the
family keeps one copy of each. Anything else added is an architectural decision recorded as an ADR, with the alternatives compared.

## Documentation law

Four directories, enforced by `DocumentationLayoutTests`.

| Path | Rule |
|---|---|
| `docs/WHITE-PAPER.md` | Principles, never a log. Capped at 200 lines. |
| `docs/adr/NNNN-title.md` | One decision per file, `accepted` or `superseded`. A decision changed by evidence becomes a **new** ADR that supersedes the old; the chain names itself in both directions. |
| `docs/roadmap/NNNN-title.md` | One claimable unit of work per file with `status:` and `blocked-by:`. A blocker must exist and must not be done. |
| `docs/diary/YYYY-MM-DD-NN.md` | The working log and where probe history lives. 256 lines; roll over. |

`docs/research/` holds dated notes with their probe sources; `docs/DESIGN.md` describes the architecture as built.

## Process

**Test first, and see it fail for the right reason.** Red is a run, not a compile error: a stub that returns the wrong answer. A test that
passes on a stub is rewritten.

**Mutation against a proven-green baseline.** Break the code in the way the test is for and watch it fail. Restore from a copy, not from
`git checkout`, which discards uncommitted work.

**Atomic commits that say why.** The diff says what. A pre-existing problem found on the way is a roadmap entry, not a silent repair.
