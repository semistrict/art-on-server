#!/usr/bin/env bash
# In-VM: prove the Concurrent Mark-Compact GC runs with real userfaultfd on
# the NATIVELY BUILT host ART (no chroot):
#  1. runtime must report CollectorTypeCMC,
#  2. a concurrent mark compact cycle must complete,
#  3. the process must make a successful userfaultfd(2) syscall.
# Reuses the GcStress dex built by art-server's test/40-smoke.sh.
set -euo pipefail

ART_HOST="${ART_HOST:-/Users/ramon/src/art-host}"
RUN="$ART_HOST/bin/host-art-run.sh"
SMOKE_DEX=/opt/android/chroot/data/local/tmp/smoke.dex
WORK=/tmp/host-art-gc-verify
mkdir -p "$WORK"

[ -f "$SMOKE_DEX" ] || { echo "run art-server test/40-smoke.sh first" >&2; exit 1; }

strace -f -e trace=userfaultfd -o "$WORK/uffd.trace" \
  bash "$RUN" -Xgc:CMC -verbose:gc -Xmx128m -cp "$SMOKE_DEX" GcStress \
  > "$WORK/gc-verify.out" 2>&1

grep -q 'CollectorTypeCMC GC' "$WORK/gc-verify.out"
grep -q 'concurrent mark compact GC freed' "$WORK/gc-verify.out"
grep -q 'gcstress done threads=8' "$WORK/gc-verify.out"
grep -E 'userfaultfd\(.*\) = [0-9]+' "$WORK/uffd.trace" >/dev/null

echo "CMC evidence:"
grep -m1 'CollectorTypeCMC GC' "$WORK/gc-verify.out" | sed 's/^/  /'
grep -m1 -E 'userfaultfd\(.*\) = [0-9]+' "$WORK/uffd.trace" | sed 's/^/  /'
grep 'concurrent mark compact GC freed' "$WORK/gc-verify.out" | tail -3 | sed 's/^/  /'
echo "65-gc-verify-host: PASS"
