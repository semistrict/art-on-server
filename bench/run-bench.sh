#!/usr/bin/env bash
# In-VM JMH benchmark: art-on-server (ART optimizing JIT, native 8-byte references) vs OpenJDK.
#
# Methodology. Identical Java sources and JMH config run on three runtimes on the SAME machine:
#   jdk26          OpenJDK 26 HotSpot C2, default (compressed oops = 4-byte references)
#   jdk26-nocoops  OpenJDK 26 with -XX:-UseCompressedOops (8-byte references, same width as ART)
#   art-jit        art-on-server: ART optimizing JIT (-Xnoimage so hot code is JIT-compiled)
# JMH cannot fork ART (its dalvikvm launcher is not a `java`-compatible CLI), so each measurement is
# in-process (forks=0); to keep the comparison fair AND to avoid cross-benchmark JIT pollution, every
# benchmark is run in its OWN fresh runtime process on every runtime (one benchmark per invocation).
# A small java.lang.management shim (bench/shim) goes on the ART bootclasspath (Android/ART omits
# that package; the core JMH runner references a little of it).
#
# Usage: bench/run-bench.sh            (build + run the whole matrix, emit results/summary.txt)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AOSP=${AOSP:-/opt/aosp/main-art}
H=$AOSP/out/host/linux-arm64
B=$H/framework
JDK_BUILD=${JDK_BUILD:-$AOSP/prebuilts/jdk/jdk21/linux-arm64}   # compile/dex toolchain (stable)
JDK_NEW=${JDK_NEW:-/tmp/jdk26}                                  # the "latest OpenJDK" under test
XMX=${XMX:-2g}

W=/tmp/bench
LIB=$W/lib
RES=$W/results
rm -rf "$RES"; mkdir -p "$RES"
JMHCP="$LIB/jmh-core-1.37.jar:$LIB/jmh-generator-annprocess-1.37.jar:$LIB/jopt-simple-5.0.4.jar:$LIB/commons-math3-3.6.1.jar"
RUNCP="$LIB/jmh-core-1.37.jar:$LIB/jopt-simple-5.0.4.jar:$LIB/commons-math3-3.6.1.jar"

echo "=== compile suite (+ JMH annotation processor) ==="
rm -rf "$W/classes"; mkdir -p "$W/classes"
"$JDK_BUILD/bin/javac" -cp "$JMHCP" -d "$W/classes" $(find "$HERE/src" -name '*.java')
test -f "$W/classes/META-INF/BenchmarkList" || { echo "BenchmarkList not generated" >&2; exit 1; }

echo "=== build java.lang.management shim (ART bootclasspath) ==="
rm -rf "$W/shimout"; mkdir -p "$W/shimout"
"$JDK_BUILD/bin/javac" --patch-module java.base="$HERE/shim" -d "$W/shimout" $(find "$HERE/shim" -name '*.java')
"$JDK_BUILD/bin/jar" cf "$W/shim.jar" -C "$W/shimout" .
rm -f "$W/mgmt.jar"
"$JDK_BUILD/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --min-api 34 --output "$W/mgmt.jar" "$W/shim.jar"

echo "=== dex suite + JMH (ART) ==="
"$JDK_BUILD/bin/jar" cf "$W/app.jar" -C "$W/classes" .
rm -f "$W/bench.jar"
"$JDK_BUILD/bin/java" -cp "$B/d8.jar" com.android.tools.r8.D8 --min-api 34 --output "$W/bench.jar" \
  "$W/app.jar" "$LIB/jmh-core-1.37.jar" "$LIB/jopt-simple-5.0.4.jar" "$LIB/commons-math3-3.6.1.jar"
( cd "$W/classes" && "$JDK_BUILD/bin/jar" uf "$W/bench.jar" META-INF/BenchmarkList META-INF/CompilerHints )

# Benchmark list (Class.method) from JMH's BenchmarkList metadata (custom format:
# "JMH S <n> <class> S <n> <generated> S <n> <method> S <n> <Mode> ..."). The class is the first
# aos.bench.* token; the method is the token three positions before the Mode word.
mapfile -t BMS < <(awk '{cls="";meth="";for(i=1;i<=NF;i++){if($i ~ /^aos\.bench\.[A-Za-z]+$/ && cls=="")cls=$i; if($i=="AverageTime")meth=$(i-3)} if(cls!=""&&meth!="")print cls"."meth}' "$W/classes/META-INF/BenchmarkList" | sort -u)
echo "=== ${#BMS[@]} benchmarks; each run in its own process per runtime ==="

PIN=""; command -v taskset >/dev/null 2>&1 && PIN="taskset -c 3"
ARTBCP="$W/mgmt.jar:$B/core-oj-hostdex.jar:$B/core-libart-hostdex.jar:$B/core-icu4j-hostdex.jar:$B/okhttp-hostdex.jar:$B/bouncycastle-hostdex.jar:$B/apache-xml-hostdex.jar:$B/conscrypt-hostdex.jar"
export ANDROID_ART_ROOT=$H ANDROID_ROOT=$H ANDROID_I18N_ROOT=$H/com.android.i18n ANDROID_TZDATA_ROOT=$H/com.android.tzdata ANDROID_DATA=/tmp/host-art-data
mkdir -p "$ANDROID_DATA"

# score <logfile> -> "score unit" or "CRASH" or "ERR"
score() {
  if grep -q "invalid reference\|SIGSEGV\|Aborted\|Fatal signal" "$1"; then echo "CRASH"; return; fi
  local s; s=$(grep -oE '[0-9]+\.[0-9]+ ±\([0-9.]+%\) [num]?s/op \[Average\]' "$1" | head -1)
  [ -n "$s" ] && echo "$s" || echo "ERR"
}

printf "%-34s %16s %16s %16s\n" "benchmark" "jdk26" "jdk26-nocoops" "art-jit" | tee "$RES/summary.txt"
printf -- "%.0s-" {1..86} | tee -a "$RES/summary.txt"; echo | tee -a "$RES/summary.txt"
for bm in "${BMS[@]}"; do
  short=${bm#aos.bench.}
  $PIN "$JDK_NEW/bin/java" -Xmx"$XMX" -cp "$W/classes:$RUNCP" aos.bench.RunBench "$bm\$" >"$RES/$short.jdk26.log" 2>&1 || true
  $PIN "$JDK_NEW/bin/java" -Xmx"$XMX" -XX:-UseCompressedOops -cp "$W/classes:$RUNCP" aos.bench.RunBench "$bm\$" >"$RES/$short.nocoops.log" 2>&1 || true
  $PIN "$H/bin/dalvikvm64" -Xbootclasspath:"$ARTBCP" -Xnoimage-dex2oat -Xgc:CMC -XX:LargeObjectSpace=map -Xmx"$XMX" \
      -cp "$W/bench.jar" aos.bench.RunBench "$bm\$" >"$RES/$short.art.log" 2>&1 || true
  printf "%-34s %16s %16s %16s\n" "$short" "$(score "$RES/$short.jdk26.log")" "$(score "$RES/$short.nocoops.log")" "$(score "$RES/$short.art.log")" \
    | tee -a "$RES/summary.txt"
done
echo "results in $RES/summary.txt"
