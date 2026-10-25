---
status: not-started
blocked-by: []
date: 2026-10-25
---

# 0012 — Structure gates, and the first CI run

`ask` gates one top-level type per file and a file-length cap with a ratchet baseline (ADR-0021 there). Here `LazyDFA.swift` is over 300
lines and some files hold several types; add the gate with a baseline that shrinks and never grows. The workflow in `.github/workflows` was
written locally and has never run: push, read the first run, fix what it says (the shared Aemi workflow's inputs are unverified).
