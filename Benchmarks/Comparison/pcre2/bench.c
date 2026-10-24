// Times PCRE2 with JIT over the corpus. Counting: after a match, continue at its end; after an empty match, continue one byte later
// (a simplification of PCRE2's retry rule, so counts on patterns that can match empty may differ from other engines).
#define PCRE2_CODE_UNIT_WIDTH 8
#include <dirent.h>
#include <pcre2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

typedef struct { unsigned char *data; size_t len; } File;
static File *files; static size_t nfiles, cap;

static void add(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) return;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(n ? n : 1); if (fread(buf, 1, n, f) != (size_t)n) { fclose(f); free(buf); return; }
    fclose(f);
    if (nfiles == cap) { cap = cap ? cap * 2 : 64; files = realloc(files, cap * sizeof(File)); }
    files[nfiles++] = (File){buf, (size_t)n};
}
static int cmp(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
static void walk(const char *dir) {
    DIR *d = opendir(dir); if (!d) return;
    char **names = NULL; size_t n = 0; struct dirent *e;
    while ((e = readdir(d))) { if (e->d_name[0] == '.') continue; names = realloc(names, ++n * sizeof(char *)); names[n - 1] = strdup(e->d_name); }
    closedir(d); qsort(names, n, sizeof(char *), cmp);
    for (size_t i = 0; i < n; i++) {
        char path[4096]; snprintf(path, sizeof path, "%s/%s", dir, names[i]);
        struct stat st; if (stat(path, &st)) continue;
        if (S_ISDIR(st.st_mode)) walk(path);
        else { size_t l = strlen(path); if (l > 6 && !strcmp(path + l - 6, ".swift")) add(path); }
        free(names[i]);
    }
    free(names);
}
static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static int dcmp(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return (x > y) - (x < y); }

int main(int argc, char **argv) {
    walk(argv[2]);
    if (getenv("CONCAT") && nfiles > 0) { /* one buffer: measures scan speed without per-call overhead */
        size_t total = 0; for (size_t i = 0; i < nfiles; i++) total += files[i].len;
        unsigned char *all = malloc(total); size_t at = 0;
        for (size_t i = 0; i < nfiles; i++) { memcpy(all + at, files[i].data, files[i].len); at += files[i].len; }
        files[0] = (File){all, total}; nfiles = 1;
    }
    FILE *w = fopen(argv[1], "r"); char line[1024];
    while (fgets(line, sizeof line, w)) {
        line[strcspn(line, "\n")] = 0; char *tab = strchr(line, '\t'); *tab = 0; const char *name = line, *pattern = tab + 1;
        int err; PCRE2_SIZE off;
        pcre2_code *re = pcre2_compile((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED, 0, &err, &off, NULL);
        if (!re) { fprintf(stderr, "compile failed: %s\n", pattern); continue; }
        int jit = pcre2_jit_compile(re, PCRE2_JIT_COMPLETE) == 0;
        pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
        double times[9]; size_t count = 0;
        for (int r = 0; r < 9; r++) {
            double t0 = now_ms(); count = 0;
            for (size_t i = 0; i < nfiles; i++) {
                size_t pos = 0;
                while (pos <= files[i].len) {
                    int rc = jit ? pcre2_jit_match(re, files[i].data, files[i].len, pos, 0, md, NULL)
                                 : pcre2_match(re, files[i].data, files[i].len, pos, 0, md, NULL);
                    if (rc < 0) break;
                    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md); count++;
                    pos = ov[1] == ov[0] ? ov[1] + 1 : ov[1];
                }
            }
            times[r] = now_ms() - t0;
        }
        qsort(times, 9, sizeof(double), dcmp);
        printf("PCRE2 %s,%s,%.2f,%zu\n", jit ? "JIT" : "interpreter", name, times[4], count);
        pcre2_match_data_free(md); pcre2_code_free(re);
    }
    return 0;
}
