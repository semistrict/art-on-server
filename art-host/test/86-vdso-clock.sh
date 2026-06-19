#!/usr/bin/env bash
# VDSO clock_gettime regression gate.
#
# The arm64 Linux VDSO exports its symbols only via DT_GNU_HASH (no SysV
# DT_HASH). Stock musl's __vdsosym only parsed DT_HASH, so symbol resolution
# failed and clock_gettime/gettimeofday fell back to a real syscall (~230
# ns/call). The fix (patches/external__musl/0001-vdso-gnu-hash-symbol-resolution)
# teaches __vdsosym to read DT_GNU_HASH, restoring the VDSO fast path (~25
# ns/call) — which matters because System.nanoTime() is on hot loops.
#
# This gate builds the micro-benchmark against the soong-built libc_musl.so and
# asserts the VDSO fast path. A syscall fallback (~230 ns) trips the threshold.
set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"

bash "$REPO/test/build_clock_gettime_bench.sh" "$REPO/test/clock_gettime_bench.c" >/dev/null
out=$(/tmp/cgt_musl 5000000)
echo "  $out"
ns=$(echo "$out" | sed -E 's/.* ([0-9.]+) ns\/call/\1/')

# VDSO ~20-35 ns, syscall ~230 ns. Gate at 80 ns to cleanly separate the two.
if awk "BEGIN{exit !($ns < 80)}"; then
  echo "86-vdso-clock: OK (${ns} ns/call — kernel VDSO fast path)"
else
  echo "86-vdso-clock: FAIL (${ns} ns/call — clock_gettime fell back to a syscall)" >&2
  exit 1
fi
