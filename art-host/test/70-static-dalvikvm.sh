#!/usr/bin/env bash
# In-VM: prove the fully static dalvikvms works:
#  1. it is a statically linked ELF (ldd refuses it),
#  2. the Smoke workload runs (ICU locale data, tzdata, java.time),
#  3. CMC GC with real userfaultfd works,
#  4. crypto works via the statically linked conscrypt/boringssl
#     (minihub suites exercise it separately).
# Requires test/60-smoke-host-art.sh (Smoke dex) and art-server's
# test/40-smoke.sh (GcStress dex) to have run.
set -euo pipefail

AOSP=/opt/aosp/main-art
VM=$AOSP/out/host/linux-arm64/bin/dalvikvms

export ANDROID_HOST_OUT=$AOSP/out/host/linux-arm64
export ANDROID_ART_ROOT=$ANDROID_HOST_OUT
export ANDROID_ROOT=$ANDROID_HOST_OUT
export ANDROID_I18N_ROOT=$ANDROID_HOST_OUT/com.android.i18n
export ANDROID_TZDATA_ROOT=$ANDROID_HOST_OUT/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$ANDROID_HOST_OUT/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

echo "--- 1. statically linked"
file "$VM" | grep -q "statically linked"
! ldd "$VM" >/dev/null 2>&1

echo "--- 2. Smoke"
SMOKE_OUT=$("$VM" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
  -cp /tmp/host-art-smoke/dex/classes.dex Smoke)
echo "$SMOKE_OUT" | grep -q "SMOKE OK on aarch64"

echo "--- 3. CMC GC + userfaultfd"
WORK=/tmp/static-dalvikvm-gc
mkdir -p "$WORK"
strace -f -e trace=userfaultfd -o "$WORK/uffd.trace" \
  "$VM" -Xgc:CMC -verbose:gc -Xmx128m -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
  -cp /opt/android/chroot/data/local/tmp/smoke.dex GcStress \
  > "$WORK/gc.out" 2>&1
grep -q 'CollectorTypeCMC GC' "$WORK/gc.out"
grep -q 'concurrent mark compact GC freed' "$WORK/gc.out"
grep -q 'gcstress done threads=8' "$WORK/gc.out"
grep -E 'userfaultfd\(.*\) = [0-9]+' "$WORK/uffd.trace" >/dev/null

echo "static dalvikvms: $(du -h "$VM" | cut -f1) unstripped"
echo "70-static-dalvikvm: PASS"
