#!/usr/bin/env bash
# In-VM: JIT correctness acceptance test for native pointer-width references.
#
# Runs JitCorrectness (stream/lambda/method-ref/iterator/object-array/map-value code,
# called enough to be JIT-compiled) and checks results against known constants. The
# interpreter (-Xint) baseline and the optimizing JIT must BOTH pass: this is a hard
# acceptance gate for the optimizing-compiler 64-bit-reference work (now complete), so
# a JIT result that disagrees with the interpreter fails the build.
set -uo pipefail

AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
BIN=${BIN:-$H/bin/dalvikvm64}

export ANDROID_HOST_OUT=$H ANDROID_ART_ROOT=$H ANDROID_ROOT=$H
export ANDROID_I18N_ROOT=$H/com.android.i18n ANDROID_TZDATA_ROOT=$H/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$H/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar

HERE=$(cd "$(dirname "$0")" && pwd)
JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
WORK=/tmp/host-art-jit-correctness
mkdir -p "$WORK/classes"

echo "--- compile JitCorrectness.java -> dex"
"$JDK/bin/javac" -d "$WORK/classes" "$HERE/JitCorrectness.java"
"$JDK/bin/java" -cp "$H/framework/d8.jar" com.android.tools.r8.D8 \
  --output "$WORK" --min-api 26 "$WORK"/classes/JitCorrectness*.class

run() { "$BIN" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map \
          -Xmx2g "$@" -cp "$WORK/classes.dex" JitCorrectness 2>&1; }

echo "--- interpreter baseline (-Xint) -- must pass"
INT_OUT=$(run -Xint)
echo "$INT_OUT" | grep -q "JITCORRECTNESS OK" || {
  echo "79-jit-correctness: FAIL (interpreter baseline broken!)" >&2
  echo "$INT_OUT" | tail -3 >&2; exit 1; }
echo "    interpreter: OK"

echo "--- JIT (optimizing) -- hard acceptance gate; must equal the interpreter"
JIT_OUT=$(run)
if echo "$JIT_OUT" | grep -q "JITCORRECTNESS OK"; then
  echo "    JIT: OK"
  echo "79-jit-correctness: PASS"
  exit 0
else
  echo "    JIT: FAIL (optimizing-JIT reference codegen disagrees with the interpreter):"
  echo "$JIT_OUT" | grep -oiE "NullPointer.*|AssertionError.*|SIGSEGV|Exception in thread.*" | head -1 | sed 's/^/      /'
  echo "79-jit-correctness: FAIL"
  exit 1
fi
