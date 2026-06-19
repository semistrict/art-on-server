#!/usr/bin/env bash
# In-VM: regression gate for the JIT ON-STACK-REPLACEMENT (OSR) reference-transfer bug in the
# native-8-byte-reference fork.
#
# OSR replaces a long-running INTERPRETED loop with the optimizing-compiled version mid-loop:
# Jit::MaybeDoOnStackReplacement copies the interpreter ShadowFrame's live dex registers -- including
# object references -- into a freshly built optimized (OSR) frame (Jit::PrepareForOsr) and jumps into
# compiled code at the matching loop header. In this fork a reference is a native pointer-width
# (8-byte) value, so a live reference above 4 GiB has non-zero high bits. The OSR vreg transfer used
# to read each reference dex-register as a 4-byte uint32_t and write only 4 bytes into the OSR frame's
# 8-byte reference slot, truncating the high bits -> a garbage pointer that crashed the OSR'd code or
# the next GC root walk. OSR was therefore DISABLED, forcing long loops to run in the slow switch
# interpreter. The fix reads the full 8-byte reference from the interpreter's References() side-array
# and, using the OSR stack map's reference mask to pick reference slots, writes all 8 bytes -- the
# sibling of the deopt vreg-transfer fix (see 84-jit-deopt). OSR is now enabled.
#
# JitOsr runs ONE invocation of a long counted loop (so the method is interpreted until the loop is
# hot, then OSR fires INTO it), holding object references live across the back-edge, dereferencing
# them every iteration and AFTER the loop. The loop work is a fixed deterministic function of its
# inputs, so a truncated reference transferred by OSR would crash or fold a wrong value and diverge
# from the interpreter oracle. The gate asserts JIT == -Xint at >4 GiB AND that OSR actually fired
# (verbose:jit "Jumping to ... JitOsr.hot"), so it cannot pass vacuously.
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
W=/tmp/host-art-jit-osr
rm -rf "$W"; mkdir -p "$W/classes"

"$JDK/bin/javac" -d "$W/classes" "$HERE/JitOsr.java"
"$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$W" --min-api 34 "$W"/classes/JitOsr*.class >/dev/null 2>&1

run() {  # <extra-flags...>
  "$BIN" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map \
    "$@" -cp "$W/classes.dex" JitOsr 2>&1
}

# Interpreter oracle (correct at every heap size; no OSR).
int=$(run -Xint -Xmx2g | grep -aoE 'JITOSR acc=-?[0-9]+' | tail -1)
# JIT at <=4 GiB and at >4 GiB. Capture OSR evidence at 6g to prove the OSR path is exercised.
jit2=$(run       -Xmx2g | grep -aoE 'JITOSR acc=-?[0-9]+|SIGSEGV|fault addr|Aborted' | tail -1)
jit6_full=$(run  -Xmx6g -verbose:jit 2>&1)
jit6=$(echo "$jit6_full" | grep -aoE 'JITOSR acc=-?[0-9]+|SIGSEGV|fault addr|Aborted' | tail -1)
osrs=$(echo "$jit6_full" | grep -aic 'Jumping to .*JitOsr.hot')

echo "    interpreter:   ${int:-<no output>}"
echo "    JIT @2g:       ${jit2:-<no output>}"
echo "    JIT @6g(>4G):  ${jit6:-<no output>}  (OSR entries into JitOsr.hot observed: $osrs)"
if [ -z "$int" ]; then
  echo "85-jit-osr: FAIL (interpreter baseline did not run)" >&2; exit 1
fi
if [ "$int" != "$jit2" ] || [ "$int" != "$jit6" ]; then
  echo "85-jit-osr: FAIL (JIT OSR disagrees with interpreter / crash: int=$int jit2g=$jit2 jit6g=$jit6)" >&2
  exit 1
fi
if [ "$osrs" -eq 0 ]; then
  echo "85-jit-osr: FAIL (OSR never fired into JitOsr.hot -- test is vacuous, the OSR path was not exercised)" >&2
  exit 1
fi
echo "85-jit-osr: PASS (OSR reference transfer == interpreter, no crash, OSR fired, <=4 GiB and >4 GiB)"
exit 0
