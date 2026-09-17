/* Benchmark: one-shot raw-deflate decompression with zlib.
 *
 * usage: bench_zlib INPUT OUT_CAP ITERS
 * prints: produced bytes, best wall time per iteration, MB/s (output)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>

static double now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
    if (argc != 4) { fprintf(stderr, "usage: %s INPUT OUT_CAP ITERS\n", argv[0]); return 2; }

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 2; }
    fseek(f, 0, SEEK_END);
    long in_len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *in = malloc(in_len);
    if (fread(in, 1, in_len, f) != (size_t)in_len) { perror("read"); return 2; }
    fclose(f);

    long out_cap = atol(argv[2]);
    int iters = atoi(argv[3]);
    unsigned char *out = malloc(out_cap);

    z_stream strm;
    memset(&strm, 0, sizeof strm);
    if (inflateInit2(&strm, -15) != Z_OK) { fprintf(stderr, "init\n"); return 2; }

    long produced = 0;
    double best = 1e30;
    for (int i = 0; i < iters; i++) {
        double t0 = now();
        inflateReset(&strm);
        strm.next_in = in;   strm.avail_in = in_len;
        strm.next_out = out; strm.avail_out = out_cap;
        int rc = inflate(&strm, Z_FINISH);
        double dt = now() - t0;
        if (rc != Z_STREAM_END) { fprintf(stderr, "inflate rc=%d\n", rc); return 1; }
        produced = (long)strm.total_out;
        if (dt < best) best = dt;
    }
    printf("zlib      produced=%ld best=%.6fs %.1f MB/s\n",
           produced, best, produced / best / 1e6);
    return 0;
}
