#!/usr/bin/env bash
# In-VM: prove the arm64 optimizing-JIT INTRINSIC + stub + calling-convention reference paths are
# correct with native 8-byte references, at BOTH <=4 GiB and >4 GiB heaps.
#
# JitIntrinsics covers the hand-written arm64 intrinsics that the main field/array codegen does not:
# Object[] System.arraycopy, Thread.currentThread(), java.lang.ref.Reference get()/refersTo(),
# AtomicReference/VarHandle compareAndSet/getAndSet (the VarHandle access-mode + var-type + subtype
# checks), String.equals, and checked Object[] stores (the art_quick_aput_obj slow path).
# JitManyArgs covers references passed in the OUTGOING STACK-ARG area (more reference args than GP
# argument registers), both via a direct JIT call and via reflection (ArtMethod::Invoke /
# QuickArgumentVisitor) -- a 4-byte stack slot or a 1-vs-2-slot layout mismatch corrupts a reference
# there even at <=4 GiB.
#
# These exercise the sites widened in MILESTONE 19. The interpreter (-Xint) is the oracle; the JIT
# must match at every heap size. (Companion to 79/80/81, which cover the general field/array/dispatch
# JIT paths.)
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

build() {  # <name> -> dex path
  local n=$1 w=/tmp/$1-jitintr
  rm -rf "$w"; mkdir -p "$w/classes"
  "$JDK/bin/javac" -d "$w/classes" "$HERE/$n.java"
  "$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$w" --min-api 34 \
    "$w"/classes/$n*.class >/dev/null 2>&1
  echo "$w/classes.dex"
}
run() {  # <dex> <main> <flags...>
  local dex=$1 main=$2; shift 2
  "$BIN" "$@" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map \
    -cp "$dex" "$main" 2>&1
}

rc=0
# name:main:tag
for c in "JitIntrinsics:JitIntrinsics:JITINTRINSICS" "JitManyArgs:JitManyArgs:JITMANYARGS"; do
  name=${c%%:*}; rest=${c#*:}; main=${rest%%:*}; tag=${rest#*:}
  dex=$(build "$name")
  int=$(run "$dex" "$main" -Xint -Xmx5g | grep -oE "$tag acc=[0-9]+" | tail -1)
  jit5=$(run "$dex" "$main"      -Xmx5g | grep -oE "$tag acc=[0-9]+|SIGSEGV|fault addr" | tail -1)
  jit2=$(run "$dex" "$main"      -Xmx2g | grep -oE "$tag acc=[0-9]+|SIGSEGV|fault addr" | tail -1)
  echo "--- $name: interpreter=$int  JIT@5g=$jit5  JIT@2g=$jit2"
  if [ -z "$int" ]; then
    echo "    -> FAIL: interpreter baseline for $name did not run" >&2; rc=1; continue
  fi
  if [ "$int" != "$jit5" ] || [ "$int" != "$jit2" ]; then
    echo "    -> FAIL: $name JIT disagrees with interpreter (int=$int jit5g=$jit5 jit2g=$jit2)" >&2; rc=1
  fi
done

if [ "$rc" = 0 ]; then
  echo "82-jit-intrinsics: PASS (intrinsic + stub + stack-arg reference codegen == interpreter at <=4 GiB and >4 GiB)"
else
  echo "82-jit-intrinsics: FAIL (a JIT intrinsic/stub/calling-convention reference path is wrong -- see above)" >&2
fi
exit $rc
