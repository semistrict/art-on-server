/*
 * clock_gettime_bench.c — measure ns/call of clock_gettime(CLOCK_MONOTONIC).
 *
 * Used to diagnose / verify the host-musl VDSO path for ART on arm64.
 * If clock_gettime resolves the kernel VDSO symbol it costs ~20-35 ns/call;
 * if it falls back to a real syscall it costs hundreds of ns/call.
 *
 * Build it against the SAME libc the host ART runtime uses:
 *   - glibc build  -> baseline (VDSO works): ~23 ns/call
 *   - host-musl build linked against the soong-built libc_musl.so
 *
 * See build_clock_gettime_bench.sh for the host-musl link recipe.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdint.h>

int main(int argc, char **argv) {
    long iters = 20000000L;
    if (argc > 1) iters = strtol(argv[1], NULL, 10);

    struct timespec ts;
    /* warm up + force the VDSO/syscall resolution to happen */
    clock_gettime(CLOCK_MONOTONIC, &ts);

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    /* prevent the loop being optimized away */
    volatile uint64_t sink = 0;
    for (long i = 0; i < iters; i++) {
        clock_gettime(CLOCK_MONOTONIC, &ts);
        sink += (uint64_t)ts.tv_nsec;
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    (void)sink;

    double ns = (double)(end.tv_sec - start.tv_sec) * 1e9
              + (double)(end.tv_nsec - start.tv_nsec);
    printf("clock_gettime(CLOCK_MONOTONIC): %ld calls, %.2f ns/call\n",
           iters, ns / (double)iters);
    return 0;
}
