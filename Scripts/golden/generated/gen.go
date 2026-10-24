// Generates Tests/AemiRegexTests/Resources/re2-generated.jsonl: random patterns (with assertions, flags, lazy and counted
// repetition, nested groups) and random haystacks, each with the answer Go's regexp gave. Deterministic: the seed is fixed.
// Run from the repository root:  go run Scripts/golden/generated/gen.go > Tests/AemiRegexTests/Resources/re2-generated.jsonl
package main

import (
	"encoding/json"
	"math/rand"
	"os"
	"regexp"
	"strings"
)

type row struct {
	P   string  `json:"p"`
	H   *string `json:"h,omitempty"`
	All [][]int `json:"all,omitempty"`
}

var rng = rand.New(rand.NewSource(0xA3E12026))

func pick(items []string) string { return items[rng.Intn(len(items))] }

func atom(depth int) string {
	limit := 9
	if depth <= 0 {
		limit = 6
	}
	switch rng.Intn(limit) {
	case 0, 1:
		return pick([]string{"a", "b", "c", "é"})
	case 2:
		return "."
	case 3:
		return pick([]string{"[ab]", "[^a]", "[a-c]", "[^bc]", `\w`, `\W`, `\s`, `[é-ü]`})
	case 4:
		return pick([]string{"a", "b", "c"})
	case 5:
		return pick([]string{`\b`, `\B`, "(?m:^)", "(?m:$)", "^", "$", `\A`, `\z`})
	case 6:
		return "(" + alternation(depth-1) + ")"
	case 7:
		return "(?:" + alternation(depth-1) + ")"
	default:
		return "(?i:" + alternation(depth-1) + ")"
	}
}

func piece(depth int) string {
	a := atom(depth)
	if rng.Intn(3) != 0 {
		return a
	}
	return a + pick([]string{"*", "+", "?", "*?", "+?", "??", "{2}", "{1,2}", "{0,2}?"})
}

func sequence(depth int) string {
	var b strings.Builder
	for i, n := 0, 1+rng.Intn(4); i < n; i++ {
		b.WriteString(piece(depth))
	}
	return b.String()
}

func alternation(depth int) string {
	parts := make([]string, 1+rng.Intn(3))
	for i := range parts {
		parts[i] = sequence(depth)
	}
	return strings.Join(parts, "|")
}

func haystack() string {
	alphabet := []rune("abcAB _\né")
	n := rng.Intn(13)
	out := make([]rune, n)
	for i := range out {
		out[i] = alphabet[rng.Intn(len(alphabet))]
	}
	return string(out)
}

func main() {
	enc := json.NewEncoder(os.Stdout)
	for written := 0; written < 2000; {
		pattern := alternation(2)
		re, err := regexp.Compile(pattern)
		if err != nil {
			continue
		}
		for i := 0; i < 4; i++ {
			h := haystack()
			enc.Encode(row{P: pattern, H: &h, All: re.FindAllStringSubmatchIndex(h, -1)})
		}
		written++
	}
}
