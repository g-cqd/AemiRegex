---
status: accepted
date: 2026-10-25
---

# 0010 — Structure is a gate: one type per file, and a line cap

## Context

`ask` gates the shape of its sources (its ADR-0021) because formatting and metric lints measure a file and never what it contains: a file
with four types passes them all. This repository had nine such files after two days of fast work: four over 250 lines and five that
declared several types.

## Decision

`SourceStructureTests` fails if a Swift file in `Sources` or `Tests` has more than 250 lines, declares more than one top-level type, or is
not named for what it declares (`Type.swift`, `Type+Feature.swift`; `extension Outer.Inner` in `Outer+Inner+Feature.swift`). Generated files
(`Generated*`) are exempt. There is **no baseline**: the nine violations were fixed, so the gate starts at zero and any new one fails.
Splitting a type across files widens `private` members it shares to internal; nothing was made `public` for the split.

## Evidence

- Before: 4 files over the cap and 5 with several types (a measured list, not an estimate). After: none; 108 tests pass.
- The gate is broken on purpose in the ways it must catch (a second type, a file named for another type, a file past the cap, a nested
  extension named wrongly) and in the ways it must allow (a nested extension named correctly, a type named only in a comment or a string).
  Putting a second type into a file and 260 lines into another each turn the repository check red.

## Consequences

The gate reads declarations by line (comments and strings blanked), so a type declared on an indented line, or two on one line, escapes it.
It is a guard like `NoRecursionTests`, not a parser. Splitting `LazyDFA` made its hot loops an extension in another file, which widened
their access to six members; the unchecked-indexing invariant comment moved with the code.
