/* Reads lines "flags<TAB>hex(pattern)<TAB>hex(subject)" and prints "ok<TAB>s,e;s,e;..." (-1,-1 for an unset group),
 * "error", or "limit", using libpcre2 in UTF mode with LF newlines. Byte offsets. No recursion. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int unhex(const char *hex, unsigned char *out, size_t max) {
    size_t n = strlen(hex) / 2;
    if (n > max) return -1;
    for (size_t i = 0; i < n; i++) {
        unsigned int v;
        if (sscanf(hex + 2 * i, "%2x", &v) != 1) return -1;
        out[i] = (unsigned char)v;
    }
    return (int)n;
}

int main(void) {
    static char line[1 << 20];
    static unsigned char pattern[1 << 18], subject[1 << 18];
    pcre2_compile_context *cctx = pcre2_compile_context_create(NULL);
    pcre2_set_newline(cctx, PCRE2_NEWLINE_LF);
    pcre2_match_context *mctx = pcre2_match_context_create(NULL);
    pcre2_set_match_limit(mctx, 2000000);
    while (fgets(line, sizeof line, stdin)) {
        char *flags = strtok(line, "\t\n");
        char *hp = strtok(NULL, "\t\n");
        char *hs = strtok(NULL, "\t\n");
        if (!flags) continue;
        if (!hp) hp = "";
        if (!hs) hs = "";
        int pn = unhex(hp, pattern, sizeof pattern), sn = unhex(hs, subject, sizeof subject);
        uint32_t options = PCRE2_UTF;
        for (const char *f = flags; *f; f++) {
            if (*f == 'i') options |= PCRE2_CASELESS;
            if (*f == 'm') options |= PCRE2_MULTILINE;
            if (*f == 's') options |= PCRE2_DOTALL;
            if (*f == 'x') options |= PCRE2_EXTENDED;
        }
        int err;
        PCRE2_SIZE erroff;
        pcre2_code *re = pcre2_compile(pattern, pn, options, &err, &erroff, cctx);
        if (!re) { puts("error"); continue; }
        pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
        int global = strchr(flags, 'g') != NULL;
        uint32_t count = pcre2_get_ovector_count(md);
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        size_t offset = 0;
        uint32_t opts = 0;
        int matches = 0, failed = 0;
        printf("ok\t");
        for (;;) {
            int rc = pcre2_match(re, subject, sn, offset, opts, md, mctx);
            if (rc == PCRE2_ERROR_NOMATCH) {
                /* pcre2test /g: after an empty match, try again at the same place for a non-empty one, then move one character on. */
                if (global && opts != 0 && offset < (size_t)sn) {
                    offset++;
                    while (offset < (size_t)sn && (subject[offset] & 0xC0) == 0x80) offset++;
                    opts = 0;
                    continue;
                }
                break;
            }
            if (rc < 0) { failed = 1; break; }
            if (matches++ > 0) putchar('|');
            for (uint32_t i = 0; i < count; i++) {
                if (ov[2 * i] == PCRE2_UNSET) printf("-1,-1");
                else printf("%zu,%zu", (size_t)ov[2 * i], (size_t)ov[2 * i + 1]);
                if (i + 1 < count) putchar(';');
            }
            if (!global || matches >= 200) break;
            opts = ov[1] == ov[0] ? (PCRE2_NOTEMPTY_ATSTART | PCRE2_ANCHORED) : 0;
            offset = ov[1];
        }
        if (failed) printf("\r"); /* a marker the caller turns into "limit" */
        putchar('\n');
        pcre2_match_data_free(md);
        pcre2_code_free(re);
    }
    return 0;
}
