// Generates pattern/subject cases for one dialect, asks the dialect's oracle for the expected match, and prints JSONL:
// A case the oracle cannot answer (a match limit, or V8 starting inside a surrogate pair) is dropped and counted on stderr.
//   {"p":pattern,"s":subject,"f":flags,"r":null | "error" | [[start,end]|null, ...]}  (UTF-8 byte offsets)
// Usage: node backtrack-fixtures.js ecma|pcre2 [cases] [seed] > fixture.jsonl
//        node backtrack-fixtures.js ecma|pcre2 curated curated.json > fixture.jsonl   (the hand-picked patterns of curated.json)
// ecma: node's RegExp with flags "du" + f.   pcre2: libpcre2 in UTF mode, via the harness pcre2-oracle.c (built into $TMPDIR).
// No recursion: expressions are built round by round from a pool.
'use strict';
const { execFileSync } = require('node:child_process');
const os = require('node:os');
const path = require('node:path');

const dialect = process.argv[2];
const curated = process.argv[3] === 'curated';
const total = curated ? 0 : Number(process.argv[3] || 3000);
let seed = curated ? 1 : Number(process.argv[4] || 20261025) >>> 0;
if (dialect !== 'ecma' && dialect !== 'pcre2') throw new Error('dialect must be ecma or pcre2');
const pcre = dialect === 'pcre2';

function rand() { // mulberry32
  seed = (seed + 0x6D2B79F5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (xs) => xs[Math.floor(rand() * xs.length)];
const chance = (p) => rand() < p;

// An expression: text, whether a quantifier may follow it directly, and its length in scalars when fixed (null otherwise).
const atom = (text, len = 1) => ({ text, atom: true, len });
const atoms = [
  atom('a'), atom('b'), atom('c'), atom('A'), atom('é'), atom('😀'), atom('.'), atom('[ab]'), atom('[^a]'), atom('[a-c]'),
  atom('\\w'), atom('\\W'), atom('\\d'), atom('\\s'), atom('\\p{Lu}'), atom('@R@', null),
  { text: '\\b', atom: false, len: 0 }, { text: '\\B', atom: false, len: 0 },
  { text: '^', atom: false, len: 0 }, { text: '$', atom: false, len: 0 },
];
atoms.push(atom('\\p{Alphabetic}'), atom('\\P{Lowercase}'), atom('\\p{Emoji}'));
if (pcre) atoms.push(atom('\\p{Greek}'), atom('\\p{Xan}'), atom('\\p{Common}'));
if (!pcre) atoms.push(atom('\\p{scx=Latin}'), atom('\\p{Script=Greek}'), atom('\\p{ID_Start}'));
if (pcre) atoms.push({ text: '\\A', atom: false, len: 0 }, { text: '\\z', atom: false, len: 0 }, { text: '\\Z', atom: false, len: 0 });
if (pcre) atoms.push(atom('\\h'), atom('\\R', null), atom('\\N'), atom('@G@', null));

const wrap = (e) => (e.atom ? e.text : `(?:${e.text})`);
const sum = (a, b) => (a === null || b === null ? null : a + b);
const quantifiers = ['*', '+', '?', '{1,2}', '{2}', '{0,2}', '*?', '+?', '??', '{1,2}?'];
if (pcre) quantifiers.push('*+', '++', '?+');

const makers = [
  (pool) => { const a = pick(pool), b = pick(pool); return { text: a.text + b.text, atom: false, len: sum(a.len, b.len) }; },
  (pool) => { const a = pick(pool), b = pick(pool), c = pick(pool); return { text: a.text + b.text + c.text, atom: false, len: sum(sum(a.len, b.len), c.len) }; },
  (pool) => { const a = pick(pool), b = pick(pool); return { text: `${a.text}|${b.text}`, atom: false, len: a.len === b.len ? a.len : null, alt: true }; },
  (pool) => { const a = pick(pool); return { text: `(${a.text})`, atom: true, len: a.len }; },
  (pool) => { const a = pick(pool); return { text: `(?:${a.text})`, atom: true, len: a.len }; },
  (pool) => { const a = pick(pool); return { text: wrap(a) + pick(quantifiers), atom: true, len: null, quantified: true }; },
  (pool) => { const a = pick(pool); return { text: `(?=${a.text})`, atom: false, len: 0 }; },
  (pool) => { const a = pick(pool); return { text: `(?!${a.text})`, atom: false, len: 0 }; },
  (pool) => { const a = pick(pool.filter((e) => !pcre || e.len !== null)); return a ? { text: `(?<=${a.text})`, atom: false, len: 0 } : pick(pool); },
  (pool) => { const a = pick(pool.filter((e) => !pcre || e.len !== null)); return a ? { text: `(?<!${a.text})`, atom: false, len: 0 } : pick(pool); },
];
if (pcre) makers.push((pool) => { const a = pick(pool); return { text: `(?>${a.text})`, atom: true, len: null }; });
if (pcre) {
  // Conditionals on a group number, on a look-around, and on being inside a call.
  makers.push((pool) => { const a = pick(pool), b = pick(pool); return { text: `(?(@C@)${a.text}|${b.text})`, atom: true, len: null }; });
  makers.push((pool) => { const a = pick(pool); return { text: `(?(@C@)${a.text})`, atom: true, len: null }; });
  makers.push((pool) => { const a = pick(pool), b = pick(pool), c = pick(pool); return { text: `(?(?=${a.text})${b.text}|${c.text})`, atom: true, len: null }; });
  makers.push((pool) => { const a = pick(pool), b = pick(pool); return { text: `(?(R)${a.text}|${b.text})`, atom: true, len: null }; });
}

function buildPattern() {
  const pool = atoms.slice();
  const rounds = 2 + Math.floor(rand() * 4);
  let last = pick(pool);
  for (let i = 0; i < rounds; i++) {
    last = pick(makers)(pool);
    pool.push(last);
  }
  let text = last.text;
  // A group's alternation must not leak: top-level alternation is fine as is.
  let groups = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '\\') { i++; continue; }
    if (text[i] === '[') { while (i < text.length && text[i] !== ']') { if (text[i] === '\\') i++; i++; } continue; }
    if (text[i] === '(' && text[i + 1] !== '?') groups++;
  }
  text = text.replace(/@C@/g, () => (groups > 0 ? String(1 + Math.floor(rand() * groups)) : 'R'));
  text = text.replace(/@G@/g, () => (groups > 0 && chance(0.8) ? `(?${1 + Math.floor(rand() * groups)})` : '(?R)'));
  text = text.replace(/@R@/g, () => (groups > 0 ? `\\${1 + Math.floor(rand() * groups)}` : 'a'));
  return text;
}

const subjectAlphabet = ['a', 'a', 'a', 'b', 'b', 'c', 'A', 'B', ' ', '1', 'é', '😀', '\n', '_'];
function buildSubject() {
  const n = Math.floor(rand() * 9);
  let s = '';
  for (let i = 0; i < n; i++) s += pick(subjectAlphabet);
  return s;
}

const cases = [];
if (curated) {
  const list = JSON.parse(require('node:fs').readFileSync(process.argv[4], 'utf8'));
  for (const [p, subjects, f] of list) for (const s of subjects) cases.push({ p, s, f });
}
while (cases.length < total) {
  const p = buildPattern();
  const f = (chance(0.2) ? pick(['i', 'm', 's', 'im', 'is']) : '') + (chance(0.2) ? 'g' : '');
  const subjects = 1 + Math.floor(rand() * 3);
  for (let i = 0; i < subjects && cases.length < total; i++) cases.push({ p, s: buildSubject(), f });
}

function utf8Offsets(s) { // UTF-16 index -> UTF-8 byte offset
  const offsets = new Array(s.length + 1);
  let bytes = 0;
  for (let i = 0; i < s.length; i++) {
    offsets[i] = bytes;
    const c = s.charCodeAt(i);
    if (c < 0x80) bytes += 1;
    else if (c < 0x800) bytes += 2;
    else if (c >= 0xD800 && c <= 0xDBFF) { bytes += 4; offsets[i + 1] = bytes; i++; continue; }
    else bytes += 3;
  }
  offsets[s.length] = bytes;
  return offsets;
}

function midPair(text, index) { // whether `index` is between the two halves of a surrogate pair
  const code = text.charCodeAt(index);
  return index > 0 && code >= 0xDC00 && code <= 0xDFFF && text.charCodeAt(index - 1) >= 0xD800 && text.charCodeAt(index - 1) <= 0xDBFF;
}

function runEcma(c) {
  let re;
  try { re = new RegExp(c.p, 'du' + c.f.replace('g', '')); } catch { return 'error'; }
  const off = utf8Offsets(c.s);
  const convert = (m) => m.indices.map((pair) => (pair ? [off[pair[0]], off[pair[1]]] : null));
  if (c.f.includes('g')) {
    const all = [...c.s.matchAll(new RegExp(c.p, 'du' + c.f))];
    // V8 can report a match that starts between the two halves of a surrogate pair; a UTF-8 text has no such position.
    if (all.some((m) => midPair(c.s, m.index))) return 'limit';
    return all.map(convert);
  }
  const m = re.exec(c.s);
  if (!m) return null;
  if (midPair(c.s, m.index)) return 'limit';
  return convert(m);
}

function runPcre(all) {
  const bin = path.join(os.tmpdir(), 'aemiregex-pcre2-oracle');
  execFileSync('cc', ['-O1', '-I/opt/homebrew/include', '-L/opt/homebrew/lib', '-lpcre2-8', '-o', bin, path.join(__dirname, 'pcre2-oracle.c')]);
  const hex = (s) => Buffer.from(s, 'utf8').toString('hex');
  const input = all.map((c) => `${c.f || '-'}\t${hex(c.p)}\t${hex(c.s)}`).join('\n') + '\n';
  const out = execFileSync(bin, { input, maxBuffer: 1 << 28 }).toString('utf8').split('\n');
  return all.map((c, i) => {
    const line = out[i];
    if (line === 'error') return 'error';
    if (line === 'limit') return 'limit';
    const body = line.split('\t')[1];
    if (body.endsWith('\r')) return 'limit';
    const groups = (text) => text.split(';').map((pair) => { const [a, b] = pair.split(',').map(Number); return a < 0 ? null : [a, b]; });
    if (all[i].f.includes('g')) return body ? body.split('|').map(groups) : [];
    return body ? groups(body) : null;
  });
}

const results = pcre ? runPcre(cases) : cases.map(runEcma);
const lines = [];
let dropped = 0;
cases.forEach((c, i) => {
  if (results[i] === 'limit') dropped++;
  else lines.push(JSON.stringify({ p: c.p, s: c.s, f: c.f, r: results[i] }));
});
process.stderr.write(`${lines.length} cases, ${dropped} dropped (oracle limit or a match inside a surrogate pair)\n`);
process.stdout.write(lines.join('\n') + '\n');
