#!/usr/bin/env bash
# In-VM: prove the OPTIMIZING JIT compiles native pointer-width (8-byte) object references
# CORRECTLY for general code -- reference field loads, reference array loads (8-byte-scaled),
# null checks, reference parameters/returns -- by JIT-compiling hot methods and comparing the
# result against the interpreter oracle.
#
# This is the acceptance gate for the optimizing-compiler 64-bit-reference cascade (the
# DataType::IsWideType vs Is64BitType predicate split + register/spill/codegen width + the
# 64-bit JIT-root literals). JitRef MUST match between -Xint and JIT.
#
# JitBox is a SECOND, intentionally-harder case (autoboxing via the static IntegerCache.cache[]
# reference array + a static reference field + an interface call). It is now JIT-correct too, so
# it is also gated: JIT MUST equal the interpreter.
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

build() {  # <name>
  local n=$1 w=/tmp/$1-jitref
  rm -rf "$w"; mkdir -p "$w/classes"
  "$JDK/bin/javac" -d "$w/classes" "$HERE/$n.java"
  "$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$w" --min-api 26 "$w"/classes/$n*.class >/dev/null 2>&1
  echo "$w/classes.dex"
}
run() {  # <dex> <main> <extra-flags...>
  local dex=$1 main=$2; shift 2
  "$BIN" "$@" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map -Xmx2g \
    -cp "$dex" "$main" 2>&1
}

echo "--- compile JitRef + JitBox -> dex"
REF_DEX=$(build JitRef)
BOX_DEX=$(build JitBox)

echo "--- JitRef: optimizing JIT must equal the interpreter (acceptance gate)"
ref_int=$(run "$REF_DEX" JitRef -Xint | grep -oE "JITREF acc=[0-9]+" | tail -1)
ref_jit=$(run "$REF_DEX" JitRef       | grep -oE "JITREF acc=[0-9]+" | tail -1)
echo "    interpreter: $ref_int"
echo "    JIT:         $ref_jit"
if [ -z "$ref_int" ] || [ "$ref_int" != "$ref_jit" ]; then
  echo "80-jit-ref: FAIL (JIT reference codegen disagrees with interpreter: '$ref_jit' != '$ref_int')" >&2
  exit 1
fi

echo "--- JitBox: autoboxing / static-reference-array / interface dispatch -- JIT must equal interpreter"
box_int=$(run "$BOX_DEX" JitBox -Xint | grep -oE "JITBOX acc=[0-9]+" | tail -1)
box_jit=$(run "$BOX_DEX" JitBox | grep -oE "JITBOX acc=[0-9]+|SIGSEGV" | tail -1)
echo "    interpreter: $box_int"
echo "    JIT:         ${box_jit:-<no output>}"
if [ -z "$box_int" ]; then
  echo "80-jit-ref: FAIL (interpreter baseline for JitBox did not run)" >&2
  exit 1
fi
if [ "$box_jit" != "$box_int" ]; then
  echo "80-jit-ref: FAIL (JitBox JIT disagrees with interpreter: '$box_jit' != '$box_int')" >&2
  exit 1
fi
echo "80-jit-ref: PASS (JitRef + JitBox optimizing-JIT reference codegen == interpreter)"
exit 0
