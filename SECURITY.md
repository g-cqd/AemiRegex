# Security Policy

## Scope

`AemiRegex` compiles and executes untrusted regular expressions without backtracking (eliminating ReDoS) and enforces explicit compile-time resource budgets via `Pattern.Limits`. No network access is performed.

## Supported Versions

Security fixes land on `main` and the latest tagged release (when releases are published). Pin a specific tag or commit revision for reproducible builds.

## Reporting a Vulnerability

Report security issues privately via [GitHub Security Advisories](https://github.com/g-cqd/AemiRegex/security/advisories/new). Do not open public issues with exploit details or sensitive material. Include the commit or version, platform, and a minimal reproduction.
