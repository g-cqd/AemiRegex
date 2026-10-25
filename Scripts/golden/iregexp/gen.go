// Generates the I-Regexp (RFC 9485) fixtures from two independent oracles:
//
//   iregexp-grammar.jsonl  {"p": pattern, "valid": bool}: whether the pattern is in the RFC's ABNF (Figure 1, plus the "[^]" rule).
//                          The recogniser below was written from the ABNF text, not from the Swift implementation.
//   iregexp-golden.jsonl   for grammar-valid patterns, what Go's regexp says about the RFC's own mapping (section 5.4): `.` outside a
//                          class becomes [^\n\r]; `^` and `$` are escaped (the RFC does not, but XSD treats them as ordinary
//                          characters); whole-string matching is \A(?:...)\z. Rows: {"p","h","full": bool,"all": [[...]]} or {"p","error":true}.
//
// No recursion (docs/adr/0003): the recogniser keeps group depth in a counter, and the pattern generator builds level by level from
// pools. Deterministic: the seed is fixed. Run from the repository root:
//   go run Scripts/golden/iregexp/gen.go Tests/AemiRegexTests/Resources
package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// ---- The recogniser, from RFC 9485 Figure 1 ----

func normalChar(c rune) bool {
	return c <= 0x27 || c == ',' || c == '-' || (c >= 0x2F && c <= 0x3E) || (c >= 0x40 && c <= 0x5A) ||
		(c >= 0x5E && c <= 0x7A) || (c >= 0x7E && c <= 0xD7FF) || (c >= 0xE000 && c <= 0x10FFFF)
}

func ccChar(c rune) bool {
	return c <= 0x2C || (c >= 0x2E && c <= 0x5A) || (c >= 0x5E && c <= 0xD7FF) || (c >= 0xE000 && c <= 0x10FFFF)
}

// singleEsc reports whether s[i:] starts with SingleCharEsc, and its length.
func singleEsc(s []rune, i int) (int, bool) {
	if i+1 >= len(s) || s[i] != '\\' {
		return 0, false
	}
	e := s[i+1]
	if (e >= 0x28 && e <= 0x2B) || e == '-' || e == '.' || e == '?' || (e >= 0x5B && e <= 0x5E) || e == 'n' || e == 'r' || e == 't' ||
		(e >= 0x7B && e <= 0x7D) {
		return 2, true
	}
	return 0, false
}

var categories = map[string]bool{}

func init() {
	for _, c := range []string{"L", "Ll", "Lm", "Lo", "Lt", "Lu", "M", "Mc", "Me", "Mn", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps",
		"Z", "Zl", "Zp", "Zs", "S", "Sc", "Sk", "Sm", "So", "C", "Cc", "Cf", "Cn", "Co"} {
		categories[c] = true
	}
}

// catEsc reports whether s[i:] starts with \p{...} or \P{...} with a known category, and its length.
func catEsc(s []rune, i int) (int, bool) {
	if i+2 >= len(s) || s[i] != '\\' || (s[i+1] != 'p' && s[i+1] != 'P') || s[i+2] != '{' {
		return 0, false
	}
	j := i + 3
	for j < len(s) && s[j] != '}' {
		j++
	}
	if j >= len(s) || !categories[string(s[i+3:j])] {
		return 0, false
	}
	return j + 1 - i, true
}

// class parses charClassExpr at s[i:] ("[" ["^"] ("-" / CCE1) *CCE1 ["-"] "]"), rejecting "[^]". Returns its length.
func class(s []rune, i int) (int, bool) {
	j := i + 1
	if j < len(s) && s[j] == '^' {
		if j+1 < len(s) && s[j+1] == ']' {
			return 0, false // the RFC forbids [^]
		}
		j++
	}
	if j < len(s) && s[j] == '-' {
		j++
	} else if n, ok := cce1(s, j); ok {
		j += n
	} else {
		return 0, false
	}
	for {
		if j >= len(s) {
			return 0, false
		}
		if s[j] == ']' {
			return j + 1 - i, true
		}
		if s[j] == '-' && j+1 < len(s) && s[j+1] == ']' {
			j++
			continue
		}
		n, ok := cce1(s, j)
		if !ok {
			return 0, false
		}
		j += n
	}
}

// ccItem parses CCchar at s[i:] and returns its length.
func ccItem(s []rune, i int) (int, bool) {
	if i >= len(s) {
		return 0, false
	}
	if n, ok := singleEsc(s, i); ok {
		return n, true
	}
	if ccChar(s[i]) {
		return 1, true
	}
	return 0, false
}

// cce1 parses CCE1 = ( CCchar [ "-" CCchar ] ) / charClassEsc at s[i:].
func cce1(s []rune, i int) (int, bool) {
	if n, ok := catEsc(s, i); ok {
		return n, true
	}
	n, ok := ccItem(s, i)
	if !ok {
		return 0, false
	}
	if i+n < len(s) && s[i+n] == '-' {
		if m, ok := ccItem(s, i+n+1); ok {
			return n + 1 + m, true
		}
	}
	return n, true
}

func accepts(p string) bool {
	s := []rune(p)
	depth, i := 0, 0
	canQuantify := false // the last thing parsed was an atom with no quantifier yet
	for i < len(s) {
		c := s[i]
		switch {
		case c == '|':
			canQuantify = false
			i++
		case c == '(':
			depth++
			canQuantify = false
			i++
		case c == ')':
			if depth == 0 {
				return false
			}
			depth--
			canQuantify = true
			i++
		case c == '*' || c == '+' || c == '?':
			if !canQuantify {
				return false
			}
			canQuantify = false
			i++
		case c == '{':
			if !canQuantify {
				return false
			}
			j := i + 1
			d := 0
			for j < len(s) && s[j] >= '0' && s[j] <= '9' {
				j++
				d++
			}
			if d == 0 {
				return false
			}
			if j < len(s) && s[j] == ',' {
				j++
				for j < len(s) && s[j] >= '0' && s[j] <= '9' {
					j++
				}
			}
			if j >= len(s) || s[j] != '}' {
				return false
			}
			canQuantify = false
			i = j + 1
		case c == '.':
			canQuantify = true
			i++
		case c == '[':
			n, ok := class(s, i)
			if !ok {
				return false
			}
			canQuantify = true
			i += n
		case c == '\\':
			if n, ok := singleEsc(s, i); ok {
				i += n
			} else if n, ok := catEsc(s, i); ok {
				i += n
			} else {
				return false
			}
			canQuantify = true
		case normalChar(c):
			canQuantify = true
			i++
		default:
			return false
		}
	}
	return depth == 0
}

// ---- The RFC's mapping to RE2 (section 5.4), with ^ and $ escaped ----

func translate(p string) string {
	var b strings.Builder
	inClass := false
	s := []rune(p)
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\' && i+1 < len(s):
			b.WriteRune(c)
			b.WriteRune(s[i+1])
			i++
		case !inClass && c == '[':
			inClass = true
			b.WriteRune(c)
		case inClass && c == ']':
			inClass = false
			b.WriteRune(c)
		case !inClass && c == '.':
			b.WriteString(`[^\n\r]`)
		case !inClass && (c == '^' || c == '$'):
			b.WriteRune('\\')
			b.WriteRune(c)
		default:
			b.WriteRune(c)
		}
	}
	return b.String()
}

// ---- Pattern generator: level by level, no recursion ----

var rng = rand.New(rand.NewSource(0x9485))

func pick(items []string) string { return items[rng.Intn(len(items))] }

var cats = []string{"L", "Ll", "Lm", "Lo", "Lt", "Lu", "M", "Mc", "Me", "Mn", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Pe", "Pf", "Pi", "Po", "Ps",
	"Z", "Zl", "Zp", "Zs", "S", "Sc", "Sk", "Sm", "So", "Cc", "Cf", "Co"}

func leafAtom() string {
	switch rng.Intn(9) {
	case 0, 1, 2:
		return pick([]string{"a", "b", "é", "日", "A", "1", "-", ",", "^", "$", "/", ":", "_", " ", "€"})
	case 3:
		return "."
	case 4:
		return pick([]string{`\.`, `\*`, `\+`, `\?`, `\(`, `\)`, `\[`, `\]`, `\{`, `\}`, `\|`, `\\`, `\^`, `\-`, `\n`, `\r`, `\t`})
	case 5:
		return pick([]string{`\p{`, `\P{`}) + pick(cats) + "}"
	default:
		items := []string{"a-z", "0-9", "a", "b", "é", `\n`, `\-`, `\]`, `\p{L}`, `\p{Nd}`, "A-Z", "é-ü", "^", ".", "-"}
		var b strings.Builder
		b.WriteString("[")
		if rng.Intn(4) == 0 {
			b.WriteString("^")
		}
		if rng.Intn(5) == 0 {
			b.WriteString("-")
		}
		for i, n := 0, 1+rng.Intn(3); i < n; i++ {
			b.WriteString(pick(items))
		}
		if rng.Intn(5) == 0 {
			b.WriteString("-")
		}
		b.WriteString("]")
		return b.String()
	}
}

func quantified(atom string) string {
	if rng.Intn(3) != 0 {
		return atom
	}
	return atom + pick([]string{"*", "+", "?", "{2}", "{1,3}", "{0,2}", "{2,}", "{0}"})
}

func branch(pool []string) string {
	var b strings.Builder
	for i, n := 0, rng.Intn(4); i < n; i++ {
		b.WriteString(quantified(pool[rng.Intn(len(pool))]))
	}
	return b.String()
}

func alternation(pool []string) string {
	parts := make([]string, 1+rng.Intn(3))
	for i := range parts {
		parts[i] = branch(pool)
	}
	return strings.Join(parts, "|")
}

func generate(count int) []string {
	atoms := make([]string, 0, 64)
	for i := 0; i < 40; i++ {
		atoms = append(atoms, leafAtom())
	}
	out := make([]string, 0, count)
	for level := 0; level < 3; level++ { // groups are built from the pool of the previous level
		next := append([]string{}, atoms...)
		for i := 0; i < 20; i++ {
			next = append(next, "("+alternation(atoms)+")")
		}
		atoms = next
	}
	for len(out) < count {
		out = append(out, alternation(atoms))
	}
	return out
}

func haystacks() []string {
	fixed := []string{"", "a", "ab", "abc", "é", "日本", "a\nb", "a\rb", "\n", "1", "A1", "a-", "^", "$", "^$", "a.b", "()", "[a]", "٣", "€5", "ǅ", "a\u0301", "_", " "}
	pool := []string{"a", "b", "é", "日", "A", "1", "٣", "€", "ǅ", "\u0301", "\n", "\r", "^", "$", "-", " ", "!", "_", ","}
	out := append([]string{}, fixed...)
	for len(out) < 32 {
		var b strings.Builder
		for i, n := 0, rng.Intn(6); i < n; i++ {
			b.WriteString(pool[rng.Intn(len(pool))])
		}
		out = append(out, b.String())
	}
	return out
}

type grammarRow struct {
	P     string `json:"p"`
	Valid bool   `json:"valid"`
	// Compiles is set for grammar-valid patterns: whether Go compiles the RFC's mapping. The grammar allows a{3,2} and a{1001}, which no
	// implementation can run, so an implementation must reject them even though they are in the grammar. C, Cn and Cs are replaced by
	// Cc for this check only, because Go has no unassigned category.
	Compiles *bool `json:"compiles,omitempty"`
}

type goldenRow struct {
	P     string  `json:"p"`
	H     *string `json:"h,omitempty"`
	Full  *bool   `json:"full,omitempty"`
	All   [][]int `json:"all,omitempty"`
	Error bool    `json:"error,omitempty"`
}

func main() {
	dir := os.Args[1]
	gf, _ := os.Create(filepath.Join(dir, "iregexp-grammar.jsonl"))
	defer gf.Close()
	genc := json.NewEncoder(gf)

	// Grammar corpus: structured valid patterns, random token soup (mostly invalid), and hand-picked edge cases.
	tokens := []string{"a", "b", "é", "日", "^", "$", "-", ",", ".", "\\", "(", ")", "[", "]", "{", "}", "|", "*", "+", "?", "n", "r", "t", "p", "P", "L", "l", "u", "d", "0", "1", "2", ":", "/", "&", "~", "s", "w"}
	edge := []string{"", "a", "a|", "|a", "|", "()", "(|)", "a**", "a{2}{3}", "a{,2}", "a{2,}", "a{2,3}", "a{3,2}", "{2}", "*a", "(*a)", "[", "[]", "[^]", "[^]]", "[^a]", "[a-]", "[-a]", "[--a]", "[a--]", "[a-c-e]",
		"[a-\\p{L}]", "[\\p{L}-a]", "[\\p{L}a]", "[\\d]", "\\d", "\\s", "\\w", "\\S", "\\b", "\\p{L}", "\\p{Lu}", "\\p{Cs}", "\\p{Cn}", "\\p{IsBasicLatin}", "\\p{}", "\\p{L", "\\pL", "\\P{N}", "\\P{L}+", "\\.", "\\-", "\\]", "\\[", "\\^", "\\$", "\\/", "\\a", "\\1", "\\x41", "\\u0041",
		"^", "$", "^a$", "a{1001}", "(a", "a)", "a|b|c", "(a|b)*c", "[a-z]+", "[^\\n\\r]", ".", "a.b", "}", "{", "]", "a}", "a{", "a-b", "a,b", "[,]", "[.]", "[(]", "[a^]", "[\\n]", "[\\-]", "[\\]]", "[\\\\]", "[a\\-z]", "\u00e9", "\U0001F600", "\\\U0001F600", "[\U0001F600-\U0001F64F]"}
	rows := map[string]bool{}
	var order []string
	add := func(p string) {
		if _, seen := rows[p]; !seen {
			rows[p] = accepts(p)
			order = append(order, p)
		}
	}
	for _, p := range edge {
		add(p)
	}
	for _, p := range generate(3000) {
		add(p)
	}
	for len(order) < 8000 {
		var b strings.Builder
		for i, n := 0, 1+rng.Intn(9); i < n; i++ {
			b.WriteString(tokens[rng.Intn(len(tokens))])
		}
		add(b.String())
	}
	valid := 0
	for _, p := range order {
		row := grammarRow{P: p, Valid: rows[p]}
		if rows[p] {
			valid++
			probe := strings.NewReplacer(`{Cn}`, `{Cc}`, `{C}`, `{Cc}`).Replace(translate(p))
			_, err := regexp.Compile(`\A(?:` + probe + `)\z`)
			ok := err == nil
			row.Compiles = &ok
		}
		genc.Encode(row)
	}
	fmt.Fprintf(os.Stderr, "grammar: %d patterns, %d valid\n", len(order), valid)

	// Golden corpus: grammar-valid patterns, translated as the RFC says, run by Go.
	of, _ := os.Create(filepath.Join(dir, "iregexp-golden.jsonl"))
	defer of.Close()
	enc := json.NewEncoder(of)
	hs := haystacks()
	var corpus []string
	for _, p := range order {
		if rows[p] && !strings.Contains(p, `{C}`) && !strings.Contains(p, `{Cn}`) && !strings.Contains(p, `{Cs}`) && len(corpus) < 200 {
			corpus = append(corpus, p)
		}
	}
	compiled, rejected := 0, 0
	for _, p := range corpus {
		t := translate(p)
		whole, errW := regexp.Compile(`\A(?:` + t + `)\z`)
		search, errS := regexp.Compile(t)
		if errW != nil || errS != nil {
			enc.Encode(goldenRow{P: p, Error: true})
			rejected++
			continue
		}
		compiled++
		for i := range hs {
			h := hs[i]
			full := whole.MatchString(h)
			enc.Encode(goldenRow{P: p, H: &h, Full: &full, All: search.FindAllStringSubmatchIndex(h, -1)})
		}
	}
	fmt.Fprintf(os.Stderr, "golden: %d patterns compiled in Go, %d rejected by Go (semantic errors: ranges, repeat counts)\n", compiled, rejected)
}
