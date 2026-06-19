#!/usr/bin/env bash
# In-VM: prove the OPTIMIZING JIT is reference-correct ABOVE 4 GiB.
#
# With -Xmx5g the managed heap maps high (>4 GiB), so every object reference is a native 8-byte
# value whose high bits are non-zero. Any JIT codegen / GC path that still handles a reference at
# 4-byte width truncates there. This test JIT-compiles hot reference-heavy methods on a >4 GiB heap
# and requires the result to equal the interpreter oracle (which is correct at every heap size).
#
# Covers the >4 GiB-specific truncation sites fixed in MILESTONE 18: the IfTable interface-check
# scan (instanceof/checkcast), the TLAB allocation klass_ store, virtual/interface dispatch class
# loads, and the GC write-barrier card-table index (object >> kCardShift). It is the acceptance
# gate for ">4 GiB JIT" -- the companion to 79/80 which gate the <=4 GiB JIT.
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

# Heap size that forces a >4 GiB (high) mapping. Override with XMX=... for a bigger run.
XMX=${XMX:-5g}

build() {  # <name> -> dex path
  local n=$1 w=/tmp/$1-jitbig
  rm -rf "$w"; mkdir -p "$w/classes"
  "$JDK/bin/javac" -d "$w/classes" "$HERE/$n.java"
  "$JDK/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --output "$w" --min-api 26 \
    "$w"/classes/$n*.class >/dev/null 2>&1
  echo "$w/classes.dex"
}
run() {  # <dex> <main> <extra-flags...>
  local dex=$1 main=$2; shift 2
  "$BIN" "$@" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map \
    -cp "$dex" "$main" 2>&1
}

# name:main:result-tag
CASES="JitRef:JitRef:JITREF JitBox:JitBox:JITBOX JitStream:JitStream:JITSTREAM"

rc=0
for c in $CASES; do
  name=${c%%:*}; rest=${c#*:}; main=${rest%%:*}; tag=${rest#*:}
  dex=$(build "$name")
  echo "--- $name @ -Xmx$XMX (>4 GiB heap): optimizing JIT must equal the interpreter"
  int=$(run "$dex" "$main" -Xint   -Xmx"$XMX" | grep -oE "$tag acc=[0-9]+" | tail -1)
  jit=$(run "$dex" "$main"         -Xmx"$XMX" | grep -oE "$tag acc=[0-9]+|SIGSEGV|fault addr" | tail -1)
  echo "    interpreter: ${int:-<no output>}"
  echo "    JIT:         ${jit:-<no output>}"
  if [ -z "$int" ]; then
    echo "    -> FAIL: interpreter baseline for $name did not run at -Xmx$XMX" >&2; rc=1; continue
  fi
  if [ "$int" != "$jit" ]; then
    echo "    -> FAIL: $name JIT disagrees with interpreter at >4 GiB ('$jit' != '$int')" >&2; rc=1
  fi
done

if [ "$rc" = 0 ]; then
  echo "81-jit-largeheap: PASS (optimizing JIT == interpreter for JitRef/JitBox/JitStream at -Xmx$XMX)"
else
  echo "81-jit-largeheap: FAIL (>4 GiB JIT reference codegen truncates -- see above)" >&2
fi
exit $rc
