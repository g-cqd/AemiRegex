// Generates Tests/AemiRegexTests/Resources/re2-golden.jsonl from Go's regexp package (RE2 semantics).
// Run from the repository root:  go run Scripts/golden/gen.go > Tests/AemiRegexTests/Resources/re2-golden.jsonl
// Go is the independent oracle: a case is only checked in with the answer Go gave, never one written by hand.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
)

var patterns = []string{
	`a`, `abc`, ``, `a|b`, `a|ab|abc`, `ab|a`, `(a|ab)(c|bcd)(d*)`, `.`, `a.c`, `a.*b`, `a.*?b`,
	`a+`, `a+?`, `a*`, `a*?`, `a?`, `a??`, `a{2}`, `a{2,}`, `a{2,3}`, `a{2,3}?`, `a{0}`, `a{0,1}`, `(a){2}`,
	`(a*)*`, `(a*)+`, `(a|b)*c`, `(?:a|b)+`, `((a)|(b))+`, `(a+)(b+)?`, `(a*)(b*)`, `(a|)+`, `(|a)+`, `(a?)*`, `()`, `a|`, `|a`,
	`^abc`, `abc$`, `^$`, `(?m)^abc$`, `(?m)^`, `(?m)$`, `(?s).`, `(?s).*`, `.*`, `.+`, `x*`,
	`(?i)abc`, `(?i:a)b`, `a(?i)b`, `(?i)a(?-i)b`, `(?i)[a-c]+`, `(?U)a+`, `(?U)a+?`,
	`[abc]`, `[^abc]`, `[a-c-]`, `[]a]`, `[^]a]`, `[a\-z]`, `[\d\s]+`, `[^\d]`, `[a-c[:digit:]]+`,
	`\d+`, `\w+`, `\s+`, `\D\W\S`, `\bfoo\b`, `\Bo`, `\b`, `\B`, `\Afoo`, `foo\z`, `[[:alpha:]]+`, `[[:^digit:]]`,
	`\x41`, `\x{263a}`, `\n\t`, `\.`, `\\`, `\Qa.b\E`, `\-`, `(?P<n>a)b`, `(?<n>a)b`, `(?P<x>a)(?P<y>b)?`,
	`é`, `[é]`, `[^a]`, `[é-ü]+`, `日本`, `.é`, `[^é]`, `\x{10FFFF}|\x{80}`,
	`(a+)+b`, `(a|aa)+$`, `((a*)*)*`, `(a{2}){3}`, `(?:a{1,2}){2,3}`, `a{1000}`, `\s*foo\s*`, `(\w+)\s(\w+)`, `^(\w+)@(\w+)\.com$`,
}

var haystacks = []string{
	``, `a`, `b`, `abc`, `aaa`, `aab`, `abab`, `baaac`, `foo bar`, "foo\nbar\n", "a\n\nb", `héllo wörld`,
	`日本語 abc`, `xéx`, `ABC aBc`, `123 abc_9`, `aaabbb`, `abcd`, "\u263a", `a-z]`, `foo`, `bob@example.com`,
	"\U0010ffff\u0080",
}

var invalid = []string{
	`(`, `)`, `a)`, `[a`, `[z-a]`, `*`, `a**`, `+a`, `?`, `a{2,1}`, `a{1001}`, `\8`, `(?z)`,
	`(?P<>a)`, `\`, `[[:foo:]]`, `x{2}{3}`, `(?i`, `(?`, `\x{110000}`, `\xZ`, `[a-\d]`, `(?P<n`, `a|*`, `(*)`, `\pX`, `a++`, `a*+`, `(?=a)`, `(?!a)`, `(?<=a)`, `\1`,
}

type row struct {
	P     string    `json:"p"`
	H     *string   `json:"h,omitempty"`
	All   [][]int   `json:"all,omitempty"`
	Error bool      `json:"error,omitempty"`
}

func main() {
	enc := json.NewEncoder(os.Stdout)
	bad := false
	for _, p := range patterns {
		re, err := regexp.Compile(p)
		if err != nil {
			fmt.Fprintf(os.Stderr, "valid pattern rejected by Go: %q: %v\n", p, err)
			os.Exit(1)
		}
		for i := range haystacks {
			h := haystacks[i]
			enc.Encode(row{P: p, H: &h, All: re.FindAllStringSubmatchIndex(h, -1)})
		}
	}
	for _, p := range invalid {
		if _, err := regexp.Compile(p); err == nil {
			fmt.Fprintf(os.Stderr, "invalid pattern accepted by Go: %q\n", p)
			bad = true
			continue
		}
		enc.Encode(row{P: p, Error: true})
	}
	if bad {
		os.Exit(1)
	}
}
