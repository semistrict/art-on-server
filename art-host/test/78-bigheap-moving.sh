#!/usr/bin/env bash
# In-VM: prove the concurrent mark-compact collector compacts a moving space holding
# MORE THAN 4 GiB of live SMALL objects, with native pointer-width references.
#
# This is the common-case counterpart to 74-largeobj-gc (which exercises the
# large-object space): a graph of tens of millions of small objects lives in the
# bump-pointer (moving) space and is relocated by concurrent compaction. The CMC
# collector's per-chunk cumulative offsets (chunk_info_vec_) and per-page from-space
# offsets (moving_pages_status_) were 32-bit and silently truncated past 4 GiB of
# live data, corrupting the heap; both are now native pointer width. We run with
# heap verification (preverify,postverify) so any relocation corruption aborts.
set -euo pipefail

AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
BIN=${BIN:-$H/bin/dalvikvm64}

export ANDROID_HOST_OUT=$H
export ANDROID_ART_ROOT=$H
export ANDROID_ROOT=$H
export ANDROID_I18N_ROOT=$H/com.android.i18n
export ANDROID_TZDATA_ROOT=$H/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$H/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

# The moving-space heap exceeds host RAM+swap overcommit on small machines; skip
# cleanly there rather than failing (the cap-removal is what is under test).
TARGET_GIB=${TARGET_GIB:-5}
XMX=${XMX:-10g}
AVAIL_KIB=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$AVAIL_KIB" -lt $((TARGET_GIB * 1024 * 1024 + 2 * 1024 * 1024)) ]; then
  echo "78-bigheap-moving: SKIP (need ~$((TARGET_GIB + 2)) GiB free, have $((AVAIL_KIB / 1024 / 1024)) GiB)"
  exit 0
fi

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/HeapStress.java"
JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
WORK=/tmp/host-art-bigheap-moving
mkdir -p "$WORK/classes"

echo "--- compile HeapStress.java -> dex"
"$JDK/bin/javac" -d "$WORK/classes" "$SRC"
"$JDK/bin/java" -cp "$H/framework/d8.jar" com.android.tools.r8.D8 \
  --output "$WORK" --min-api 26 "$WORK"/classes/HeapStress*.class

echo "--- run HeapStress $TARGET_GIB GiB (-Xint, -Xmx$XMX, CMC + heap verification)"
OUT=$("$BIN" -Xint -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
  -Xgc:CMC,preverify,postverify -XX:LargeObjectSpace=map -Xmx"$XMX" \
  -cp "$WORK/classes.dex" HeapStress "$TARGET_GIB" 2>&1)
echo "$OUT" | grep -oiE "HEAPSTRESS OK: verified [0-9]+ nodes after GC, peak heap ~[0-9]+ MiB" | tail -1
if echo "$OUT" | grep -qiE "Heap corruption|post_compact|SIGSEGV"; then
  echo "78-bigheap-moving: FAIL (GC corruption / crash above 4 GiB)" >&2
  echo "$OUT" | grep -iE "Heap corruption|post_compact|Check failed|fault addr" | head -3 >&2
  exit 1
fi
echo "$OUT" | grep -q "HEAPSTRESS OK"
echo "78-bigheap-moving: PASS"
