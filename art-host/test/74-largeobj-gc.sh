#!/usr/bin/env bash
# In-VM: prove the large-object space works under the concurrent mark-compact GC
# on a sub-4 GiB heap in the default (JIT) execution mode.
#
# Regression test for the large-heap fork's heap-layout work: the LOS must be
# placed on the same side of the 4 GiB line as the main heap, because the
# mark-compact collector indexes large objects through a bitmap sized for the
# heap's range. A high LOS with a low main heap crashed in
# MarkCompact::MarkZygoteLargeObjects; this test allocates and GC-churns large
# objects in a <=4 GiB (low) heap with the JIT enabled and verifies they survive
# compaction uncorrupted.
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

HERE=$(cd "$(dirname "$0")" && pwd)
JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
WORK=/tmp/host-art-largeobj
mkdir -p "$WORK/classes"

echo "--- compile LargeObjGc.java -> dex (javac + d8 on the host JDK)"
"$JDK/bin/javac" -d "$WORK/classes" "$HERE/LargeObjGc.java"
"$JDK/bin/java" -cp "$H/framework/d8.jar" com.android.tools.r8.D8 \
  --output "$WORK" --min-api 26 "$WORK/classes/LargeObjGc.class"

# Default (JIT) execution mode, CMC GC, <=4 GiB heap: large objects must land in
# the low LOS, GC must run repeatedly, and every retained array must verify.
echo "--- run LargeObjGc (default JIT mode, -Xmx2g, CMC, LargeObjectSpace=map)"
OUT=$("$BIN" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat \
  -Xgc:CMC -XX:LargeObjectSpace=map -Xmx2g \
  -cp "$WORK/classes.dex" LargeObjGc 768 16 2>&1)
echo "$OUT" | grep -vE "^06-|dalvikvm64:|mark_compact|tzdata|ICU|succeeded|APEX|u_set" | tail -2
echo "$OUT" | grep -q "LARGEOBJ OK"

echo "74-largeobj-gc: PASS"
