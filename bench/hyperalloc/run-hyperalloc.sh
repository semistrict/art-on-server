#!/usr/bin/env bash
# In-VM: Amazon Heapothesys/HyperAlloc large-heap allocator benchmark -- art-on-server vs OpenJDK.
#
# HyperAlloc (Apache-2.0, github.com/corretto/heapothesys) sustains a target allocation rate while
# holding a configurable, reference-heavy live set, reporting the ACHIEVED allocation rate (MB/s) --
# i.e. how well the GC keeps up. It is the most direct demonstration of our headline: a multi-GB LIVE
# heap, which stock ART (4-byte compressed references) cannot hold and art-on-server (native 8-byte
# references) can. We sweep the live set across the old 4 GiB boundary on three collectors on the
# same machine:
#   jdk26-G1   OpenJDK 26 HotSpot C2 + G1 (throughput-oriented; compressed oops = 4-byte refs)
#   jdk26-ZGC  OpenJDK 26 HotSpot C2 + ZGC (-XX:+UseZGC; concurrent low-pause, and -- like ART CMC
#              and art-on-server -- ZGC uses UNCOMPRESSED 64-bit references, so it is both the apt
#              concurrent-collector peer to ART's CMC and the natural 8-byte-reference comparison)
#   art-jit    art-on-server: ART optimizing JIT + CMC (concurrent mark-compact; native 8-byte refs)
#
# Two upstream HotSpot dependencies are patched out for ART (bench/hyperalloc/0001-hyperalloc-art.patch):
#   - AllocObject measured its per-object overhead via JOL (needs sun.misc.Unsafe + a HotSpot
#     java.vm.name); replaced with a portable heap-delta measurement that is accurate on either VM.
#   - SimpleRunConfig read the heap size + UseCompressedOops via java.lang.management /
#     HotSpotDiagnosticMXBean (absent on ART); replaced with Runtime.maxMemory() and a cosmetic flag.
# The patch is runtime-neutral (the measured overhead is each VM's real layout), so it runs unchanged
# on OpenJDK too -- the comparison stays apples-to-apples.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AOSP=${AOSP:-/opt/aosp/main-art}
H=$AOSP/out/host/linux-arm64
B=$H/framework
JDK_BUILD=${JDK_BUILD:-$AOSP/prebuilts/jdk/jdk21/linux-arm64}
JDK_NEW=${JDK_NEW:-/tmp/jdk26}
W=/tmp/ha
DUR=${DUR:-20}; RATE=${RATE:-2048}; THREADS=${THREADS:-4}

mkdir -p "$W"
HA="$W/heapothesys/HyperAlloc"
if [ ! -d "$W/heapothesys" ]; then
  git clone --depth 1 https://github.com/corretto/heapothesys.git "$W/heapothesys"
fi
( cd "$W/heapothesys" && git checkout -- . && git apply "$HERE/0001-hyperalloc-art.patch" )

echo "=== build HyperAlloc (javac, no deps after patch) + dex ==="
rm -rf "$W/classes"; mkdir -p "$W/classes"
"$JDK_BUILD/bin/javac" -d "$W/classes" $(find "$HA/src/main/java" -name '*.java')
"$JDK_BUILD/bin/jar" cfe "$W/hyperalloc.jar" com.amazon.corretto.benchmark.hyperalloc.HyperAlloc -C "$W/classes" .
"$JDK_BUILD/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --min-api 34 --output "$W/hyperalloc-dex.jar" "$W/hyperalloc.jar"

BCP="$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar"
export ANDROID_ART_ROOT=$H ANDROID_ROOT=$H ANDROID_I18N_ROOT=$H/com.android.i18n ANDROID_TZDATA_ROOT=$H/com.android.tzdata ANDROID_DATA=/tmp/host-art-data
mkdir -p "$ANDROID_DATA"
MAIN=com.amazon.corretto.benchmark.hyperalloc.HyperAlloc

# Achieved allocation rate = column 3 of the csv.
ach() { [ -s "$1" ] && awk -F, '{print $3}' "$1" | tail -1 || echo CRASH; }
oj()  { local x=$1 s=$2 f=$3; shift 3; "$JDK_NEW/bin/java" -Xmx"$x" "$@" -cp "$W/hyperalloc.jar" $MAIN -a "$RATE" -s "$s" -m 0 -d "$DUR" -t "$THREADS" -l "$f" >/dev/null 2>&1 || true; ach "$f"; }
art() { local x=$1 s=$2 f=$3; "$H/bin/dalvikvm64" -Xbootclasspath:"$BCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map -Xmx"$x" -cp "$W/hyperalloc-dex.jar" $MAIN -a "$RATE" -s "$s" -m 0 -d "$DUR" -t "$THREADS" -l "$f" >/dev/null 2>&1 || true; ach "$f"; }

printf "%-26s %8s %12s %12s %14s\n" "point (xmx / live-set)" "target" "jdk26-G1" "jdk26-ZGC" "art-jit (CMC)"
printf -- '%.0s-' {1..76}; echo
# (xmx, live-set MB, label) -- ~2 GiB headroom each; the >4 GiB live sets are the headline.
for p in "3g:1024:<=4GiB" "6g:4096:>4GiB live" "9g:7168:>4GiB live"; do
  x=${p%%:*}; rest=${p#*:}; s=${rest%%:*}; lbl=${rest#*:}
  g=$(oj  "$x" "$s" "$W/g1-$s.csv"  -XX:+UseG1GC)
  z=$(oj  "$x" "$s" "$W/zgc-$s.csv" -XX:+UseZGC)
  a=$(art "$x" "$s" "$W/art-$s.csv")
  printf "%-26s %8s %12s %12s %14s\n" "$x / ${s}MB $lbl" "$RATE" "$g" "$z" "$a"
done
echo "achieved allocation rate (MB/s); higher = GC keeps up better. CRASH = run aborted."
