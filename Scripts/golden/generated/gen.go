// Generates Tests/AemiRegexTests/Resources/re2-generated.jsonl: random patterns (with assertions, flags, lazy and counted
// repetition, nested groups) and random haystacks, each with the answer Go's regexp gave. Deterministic: the seed is fixed.
// Run from the repository root:  go run Scripts/golden/generated/gen.go > Tests/AemiRegexTests/Resources/re2-generated.jsonl
package main

import (
	"encoding/json"
	"fmt"
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

// A pattern is built level by level, not by functions that call each other (docs/adr/0003): level 0 is a pool of leaf atoms, each later
// level adds groups whose bodies are alternations drawn from the pool below, and a pattern is an alternation from the final pool.

func leaf() string {
	switch rng.Intn(6) {
	case 0, 1:
		return pick([]string{"a", "b", "c", "é"})
	case 2:
		return "."
	case 3:
		return pick([]string{"[ab]", "[^a]", "[a-c]", "[^bc]", `\w`, `\W`, `\s`, `[é-ü]`})
	case 4:
		return pick([]string{"a", "b", "c"})
	default:
		return pick([]string{`\b`, `\B`, "(?m:^)", "(?m:$)", "^", "$", `\A`, `\z`})
	}
}

func piece(pool []string) string {
	a := pool[rng.Intn(len(pool))]
	if rng.Intn(3) != 0 {
		return a
	}
	return a + pick([]string{"*", "+", "?", "*?", "+?", "??", "{2}", "{1,2}", "{0,2}?"})
}

func sequence(pool []string) string {
	var b strings.Builder
	for i, n := 0, 1+rng.Intn(4); i < n; i++ {
		b.WriteString(piece(pool))
	}
	return b.String()
}

func alternation(pool []string) string {
	parts := make([]string, 1+rng.Intn(3))
	for i := range parts {
		parts[i] = sequence(pool)
	}
	return strings.Join(parts, "|")
}

// pools returns the final pool: leaves, then two levels of groups.
func pools() []string {
	atoms := make([]string, 0, 160)
	for i := 0; i < 30; i++ {
		atoms = append(atoms, leaf())
	}
	for level := 0; level < 2; level++ {
		below := append([]string{}, atoms...)
		for i := 0; i < 60; i++ {
			inner := alternation(below)
			atoms = append(atoms, fmt.Sprintf(pick([]string{"(%s)", "(?:%s)", "(?i:%s)"}), inner))
		}
	}
	return atoms
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
	atoms := pools()
	for written := 0; written < 2000; {
		pattern := alternation(atoms)
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
