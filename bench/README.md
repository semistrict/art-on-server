# Benchmarks — art-on-server (ART optimizing JIT) vs OpenJDK 26

JMH microbenchmarks comparing **art-on-server** (ART with native 8-byte object references, optimizing
JIT) against **OpenJDK 26** (HotSpot C2) on the same machine.

## How to run

```sh
# in the build VM, after art-host has been built
bench/run-bench.sh                 # builds the suite + shim, runs the full matrix
python3 bench/summarize.py /tmp/bench/results
```

## Methodology

- **Same Java sources, same JMH config**, three runtimes on the **same host** (arm64, in the build VM):
  - `jdk26` — OpenJDK 26 HotSpot C2, default (compressed oops = **4-byte** references).
  - `jdk26-nocoops` — OpenJDK 26 `-XX:-UseCompressedOops` (**8-byte** references, the *same width as ART*).
  - `art-jit` — art-on-server, ART optimizing JIT (`-Xnoimage-dex2oat` so hot code is JIT-compiled).
- **In-process, per-benchmark fresh process.** JMH cannot fork ART (its `dalvikvm` launcher is not a
  `java`-compatible CLI), so every measurement runs with `forks=0`; to keep it fair and to avoid
  cross-benchmark JIT pollution, *each benchmark runs in its own freshly-started runtime* on every
  runtime. Warmup 5×1s, measurement 5×1s, `AverageTime` (lower = faster).
- **JMH on ART.** JMH runs in-process on ART once a tiny `java.lang.management` shim (`bench/shim`,
  the slice the core runner needs) is placed on the ART bootclasspath — Android/ART omits that package.
- All runs `-Xmx2g`, default collector each side (ART CMC, HotSpot G1).

> Microbenchmark caveats apply (in-process runs, a 2 GB heap, a single VM). Treat these as
> order-of-magnitude, not precise. The harness is committed so the numbers are reproducible.

## Results

```
benchmark                         unit      jdk26    nocoops    art-jit  art/jdk26  art/ncp
--------------------------------------------------------------------------------------------
Arithmetic.longArithmetic        us/op     33.317     33.266     33.225      1.00x    1.00x
Arithmetic.doubleArithmetic      us/op      7.076      7.064      7.171      1.01x    1.02x
Dispatch.monomorphicInterface    us/op     23.791     23.831     23.991      1.01x    1.01x
Dispatch.polymorphicInterface    us/op     16.614     17.608      9.823      0.59x    0.56x
Loops.intSum                     ns/op  25291.346  25378.590  38477.473      1.52x    1.52x
Arithmetic.intArrayReduce        us/op      5.431      5.401      8.847      1.63x    1.64x
Allocation.buildList             us/op     45.250     48.608     78.170      1.73x    1.61x
Allocation.walkAndDrop           us/op     38.872     42.811     68.180      1.75x    1.59x
Loops.consume                    ns/op    240.130    240.341    507.215      2.11x    2.11x
Allocation.objectArrays          us/op     36.939     40.089     78.719      2.13x    1.96x
Streams.collectToList            us/op     11.602     14.187     34.956      3.01x    2.46x
Collections.hashMapGet           us/op     11.858     15.111     43.802      3.69x    2.90x
Streams.filterMapReduce          us/op      1.534      1.465     10.600      6.91x    7.24x
Streams.mapToIntSum              us/op      1.161      1.085     11.907     10.26x   10.97x
Strings.builderConcat            us/op      3.324      3.398     37.256     11.21x   10.96x
Collections.arrayListIterate     us/op      9.018      8.468    101.916     11.30x   12.04x
Strings.hashAndEquals            us/op      6.299      5.940   2095.055    332.6x   352.7x
Collections.hashMapBuild         us/op     30.203     34.961      CRASH          -        -
--------------------------------------------------------------------------------------------
geomean art-jit / jdk26 (compressed oops):  3.31x   (n=17)
geomean art-jit / jdk26 -UseCompressedOops: 3.20x   (n=17)
```

## What the numbers say

- **Compute-bound code is at parity with C2.** `longArithmetic`, `doubleArithmetic`, and
  `monomorphicInterface` are within 1–2% of HotSpot; `polymorphicInterface` is actually *faster* on
  ART (0.59x). ART's optimizing compiler generates competitive scalar/dispatch code.
- **The 8-byte reference width is NOT the main cost.** `art/jdk26` (3.31x) ≈ `art/jdk26-nocoops`
  (3.20x): when HotSpot is forced to the same 8-byte references ART uses, the gap barely moves. The
  difference is **optimization depth, not pointer size** — exactly the headline trade the project
  makes (native 8-byte refs to lift the 4 GiB cap) costs little on throughput.
- **The gap is allocation- and library-heavy code (1.5–3x typical).** Allocation (~1.7–2.1x), HashMap
  get (3.7x), stream pipelines (3–10x). HotSpot C2 has decades of escape analysis, scalar
  replacement, and aggressive inlining that ART's JIT does not match yet.
- **The outliers are C2 eliminating allocation ART must perform.** `Strings.hashAndEquals` (332x) and
  `builderConcat`/`mapToIntSum` (10–11x) are dominated by short-lived allocation that C2's escape
  analysis scalar-replaces away, while ART actually allocates and collects. These are the clearest
  targets for future ART JIT work (escape analysis / scalar replacement), not reference-width issues.

## Bug found by this benchmark

`Collections.hashMapBuild` (rebuild a 2048-entry `HashMap<String,Integer>` in a hot loop) **crashes
the ART JIT** under sustained allocation + a concurrent CMC GC: `verification.cc: GC tried to mark
invalid reference 0x1`. The **interpreter is correct** (`-Xint` completes, ~1113 µs/op), so this is a
JIT codegen bug the targeted tests (`art-host/test/79`–`82`) did not exercise — it needs HashMap
resize churn plus a GC at the wrong moment. The other 17 benchmarks are JIT-correct. This is tracked
as a follow-up; it does not affect the interpreter or the committed correctness gates.
