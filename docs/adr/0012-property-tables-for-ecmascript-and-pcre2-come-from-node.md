---
status: accepted
date: 2026-10-25
---

# 0012 — The binary property and Script_Extensions tables come from node

## Context

ADR-0009 generates categories, scripts and case folding from Go's `unicode` package. ECMAScript and PCRE2 also have binary properties
(`\p{Alphabetic}`, `\p{Emoji}`), `Script_Extensions` and short aliases (`Alpha`, `Grek`), none of which Go has.

## Decision

`Scripts/unicode/gen-properties.js` writes `GeneratedPropertyTables.swift` by testing every code point against `node`'s own `\p{…}`: 53 binary
properties, the extensions of 174 scripts, 46 property aliases and 177 four-letter script codes (13,960 ranges). An alias is kept only if node
accepts it and it denotes the same set as its canonical name; a script code only if it denotes the same set as one script's extensions.

## Why node, and what it costs

- **Same oracle, same version.** ECMAScript patterns are checked against node, so tables derived from node cannot disagree with it:
  Unicode 17.0 in both (node 26.12.1, ICU 78.3), as in the Go tables. `libpcre2` 10.49 agrees on the 1,700 curated cases.
- **Two sources now.** A change of Unicode version needs both generators run, and they could drift: a test that compares the category
  and script tables with node would catch it; it is not written (open).
- **PCRE2 and ECMAScript read names differently,** and both are implemented from the oracle's answers, not from documentation: ECMAScript
  is exact and has `gc=`, `Assigned`, long category names; PCRE2 ignores case, spaces and underscores, has only short category codes
  plus `L&`, `Xan`, `Xwd`, `Xsp`, `Xps`, `Xuc`, reads a bare script name as Script or Script_Extensions, and widens only `Lu`, `Ll`, `Lt`
  under `i`. PCRE2's `\p{Bidi_Class=…}` has no data here and throws `.unsupported`.
