#!/usr/bin/env bash
# In-VM: regression gate for the JIT GC-stack-map / outgoing-argument frame-layout crash.
#
# A native 8-byte reference passed ON THE STACK occupies two machine slots (a DoubleStackSlot). The
# compiler used to size the outgoing-argument frame region from the dex out-vregs (a reference = 1
# vreg), so stack-passed reference args overflowed that region and clobbered adjacent reference SPILL
# slots; a concurrent CMC GC then tried to mark the clobbered primitive as a reference and aborted
# ("GC tried to mark invalid reference"). JitGcRoots calls an 11-reference-arg method in a hot,
# allocating loop so a GC fires at the call's safepoint while spilled references are live -- it
# crashed the JIT before the fix (reserved_out_slots_ now sized by machine width). The interpreter is
# the oracle; the JIT must match with no crash. Run under a small heap to force frequent GC.
set -uo pipefail

AOSP=/opt/aosp/main-art
H=$AOSP/out/host/linux-arm64
BIN=${BIN:-$H/bin/dalvikvm64}
export ANDROID_ART_ROOT=$H ANDROID_ROOT=$H
export ANDROID_I18N_ROOT=$H/com.android.i18n ANDROID_TZDATA_ROOT=$H/com.android.tzdata
export ANDROID_DATA=${ANDROID_DATA:-/tmp/host-art-data}
mkdir -p "$ANDROID_DATA"

B=$H/framework
BCP=$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar
JDK=$AOSP/prebuilts/jdk/jdk21/linux-arm64
HERE=$(cd "$(dirname "$0")" && pwd)
W=/tmp/host-art-jit-gcroots
rm -rf "$W"; mkdir -p "$W/classes"

"$JDK/bin/javac" -d "$W/classes" "$HERE/JitGcRoots.java"
"$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$W" --min-api 34 "$W"/classes/JitGcRoots*.class >/dev/null 2>&1

run() {  # <extra-flags...>  -- small heap forces frequent GC at the call safepoints
  "$BIN" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map -Xms256m -Xmx256m \
    "$@" -cp "$W/classes.dex" JitGcRoots 2>&1
}

int=$(run -Xint | grep -aoE 'JITGCROOTS acc=[0-9]+' | tail -1)
jit=$(run       | grep -aoE 'JITGCROOTS acc=[0-9]+|invalid reference|SIGSEGV|Aborted' | tail -1)
echo "    interpreter: ${int:-<no output>}"
echo "    JIT:         ${jit:-<no output>}"
if [ -z "$int" ]; then
  echo "83-jit-gcroots: FAIL (interpreter baseline did not run)" >&2; exit 1
fi
if [ "$int" != "$jit" ]; then
  echo "83-jit-gcroots: FAIL (JIT disagrees with interpreter / GC crash: '$jit' != '$int')" >&2; exit 1
fi
echo "83-jit-gcroots: PASS (stack-passed reference args + GC safepoint == interpreter, no GC crash)"
exit 0
