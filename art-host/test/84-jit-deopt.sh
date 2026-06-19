#!/usr/bin/env bash
# In-VM: regression gate for the JIT DEOPTIMIZATION reference-transfer crash in the
# native-8-byte-reference fork.
#
# Deoptimization copies an optimized (JIT) frame's dex-register values -- including object
# references -- into an interpreter ShadowFrame via the precise CodeInfo dex-register map. In this
# fork a reference is a native pointer-width (8-byte) value, so a live reference whose heap address
# is above 4 GiB has non-zero high bits. The deopt frame builder
# (QuickExceptionHandler::HandleOptimizingDeoptimization) read each reference dex-register as a
# 4-byte uint32_t -- truncating the high bits -- and fed the bad pointer to SetVRegReference,
# crashing in DeoptimizeSingleFrame (fault addr was a truncated 32-bit value) or, downstream, in the
# GC root walk. This is the sibling of the OSR vreg transfer, which was disabled for the same
# reason. The fix reads references at full 8-byte width (StackReference on the stack, GetGPRAddress
# for registers) before SetVRegReference.
#
# JitDeopt forces a single-frame deopt FROM COMPILED CODE DETERMINISTICALLY and cheaply (no OOM, no
# GC, no thread race) via a MONOMORPHIC INLINE CACHE: hot() is JIT-compiled while it only ever sees
# a Circle receiver for s.area(), so that call site is compiled with a Circle-only inline cache
# guarded by an HDeoptimize; then hot() is called with a Square receiver, the type guard fails, and
# the optimized frame deoptimizes single-frame with object references live. On the buggy runtime
# this crashes in DeoptimizeSingleFrame every run. The interpreter (-Xint) is the oracle; the JIT
# must match with no crash, at both <=4 GiB and >4 GiB heaps. The gate also asserts the deopt
# actually fired (verbose:deopt) so it cannot pass vacuously.
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
W=/tmp/host-art-jit-deopt
rm -rf "$W"; mkdir -p "$W/classes"

"$JDK/bin/javac" -d "$W/classes" "$HERE/JitDeopt.java"
"$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$W" --min-api 34 "$W"/classes/JitDeopt*.class >/dev/null 2>&1

run() {  # <extra-flags...>
  "$BIN" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map \
    "$@" -cp "$W/classes.dex" JitDeopt 2>&1
}

# Interpreter oracle (correct at every heap size; no deopt).
int=$(run -Xint -Xmx2g | grep -aoE 'JITDEOPT acc=-?[0-9]+' | tail -1)
# JIT at <=4 GiB and at >4 GiB. Capture deopt evidence at 6g to prove the deopt path is exercised.
jit2=$(run       -Xmx2g | grep -aoE 'JITDEOPT acc=-?[0-9]+|SIGSEGV|fault addr|Aborted' | tail -1)
jit6_full=$(run  -Xmx6g -verbose:deopt 2>&1)
jit6=$(echo "$jit6_full" | grep -aoE 'JITDEOPT acc=-?[0-9]+|SIGSEGV|fault addr|Aborted' | tail -1)
deopts=$(echo "$jit6_full" | grep -aic 'Deoptimizing stack\|Single-frame deopting')

echo "    interpreter:   ${int:-<no output>}"
echo "    JIT @2g:       ${jit2:-<no output>}"
echo "    JIT @6g(>4G):  ${jit6:-<no output>}  (single-frame deopts observed: $deopts)"
if [ -z "$int" ]; then
  echo "84-jit-deopt: FAIL (interpreter baseline did not run)" >&2; exit 1
fi
if [ "$int" != "$jit2" ] || [ "$int" != "$jit6" ]; then
  echo "84-jit-deopt: FAIL (JIT deopt disagrees with interpreter / crash: int=$int jit2g=$jit2 jit6g=$jit6)" >&2
  exit 1
fi
if [ "$deopts" -eq 0 ]; then
  echo "84-jit-deopt: FAIL (no single-frame deopt fired -- test is vacuous, the deopt path was not exercised)" >&2
  exit 1
fi
echo "84-jit-deopt: PASS (single-frame deopt reference transfer == interpreter, no crash, <=4 GiB and >4 GiB)"
exit 0
