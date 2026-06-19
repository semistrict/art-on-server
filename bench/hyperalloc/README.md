# Heapothesys / HyperAlloc — large-heap allocation benchmark vs OpenJDK 26

[HyperAlloc](https://github.com/corretto/heapothesys) (Amazon Corretto, **Apache-2.0**) sustains a
target allocation rate while holding a configurable, reference-heavy **live set**, and reports the
**achieved allocation rate** (MB/s) — i.e. how well the collector keeps up. It is the most direct
demonstration of art-on-server's headline: a multi-GB *live* heap, which stock ART (4-byte
compressed references) cannot hold and art-on-server (native 8-byte references) can.

## Run

```sh
bench/hyperalloc/run-hyperalloc.sh        # in the VM: clones HyperAlloc, applies the patch, builds, sweeps
```

## Methodology

Same patched HyperAlloc, same parameters, three collectors on the **same machine** (arm64, in the
build VM), each in its own process:

- **jdk26-G1** — OpenJDK 26 HotSpot C2 + G1 (throughput-oriented; compressed oops = 4-byte refs).
- **jdk26-ZGC** — OpenJDK 26 HotSpot C2 + ZGC (`-XX:+UseZGC`; concurrent, low-pause). ZGC, like ART
  CMC and art-on-server, uses **uncompressed 64-bit references**, so it is both the apt
  concurrent-collector peer to ART's CMC *and* the natural 8-byte-reference comparison.
- **art-jit (CMC)** — art-on-server: ART optimizing JIT + concurrent mark-compact, native 8-byte refs.

`bench/hyperalloc/0001-hyperalloc-art.patch` removes two HotSpot-only startup dependencies so the
benchmark runs on ART (and, being runtime-neutral, unchanged on OpenJDK): JOL object-layout (needs
`sun.misc.Unsafe` + a HotSpot `java.vm.name`) → a portable heap-delta overhead measurement; and the
`java.lang.management` / `HotSpotDiagnosticMXBean` heap+oops lookup (absent on ART) → `Runtime.maxMemory()`.

## Results (4 threads, 20 s, ~2 GiB headroom)

Achieved rate at a fixed **2048 MB/s target** (both HotSpot collectors saturate the target):

```
point (heap / live-set)     target   jdk26-G1   jdk26-ZGC   art-jit (CMC)
------------------------------------------------------------------------
3g / 1 GiB   (<=4 GiB)         2048       2035        2035           2035
6g / 4 GiB   (>4 GiB live)     2048       2035        2035           1305
9g / 7 GiB   (>4 GiB live)     2048       2035        2035           1329
```

**Uncapped** max allocation rate at 6 GiB heap / 4 GiB live (>4 GiB), `-a 100000`:

```
jdk26-ZGC  15282 MB/s
jdk26-G1   13915 MB/s
art-CMC    ~2236 MB/s     (was 496; 30x -> 8.2x with OSR -> 6.8x with the VDSO fix)
```

## What the numbers say

- **The headline works.** art-on-server holds a **4 GiB and 7 GiB live set** and keeps allocating
  with no crash — impossible on stock ART (4-byte references cap the heap at ~4 GiB). ZGC is the apt
  peer (also concurrent, also uncompressed 8-byte refs) and confirms the workload is well-formed.
- **The first measurement was a misconfiguration, not a collector limit.** The original 496 MB/s
  (~31× off ZGC) was because the hot allocation loop ran in the *switch interpreter* the whole time:
  OSR (On-Stack-Replacement, how a long-running loop migrates from interpreter to JIT) had been
  *disabled* as a workaround for the 64-bit-reference port (see below). With OSR fixed and enabled the
  loop runs compiled and the uncapped rate jumped to **~1863 MB/s (~8× ZGC)** — a 3.8× jump from one fix.
- **A second fix — `System.nanoTime()` was a syscall.** Profiling the result showed ~36% of mutator
  CPU in `System.nanoTime() → musl clock_gettime`, going through a real **syscall** instead of the
  kernel VDSO (~230 ns vs ~16 ns). Root cause: the arm64 Linux VDSO exports symbols only via
  `DT_GNU_HASH`, but stock musl's `__vdsosym` parsed only the SysV `DT_HASH` (absent), so it never
  resolved `__kernel_clock_gettime` and fell back to the syscall permanently. Fixed in
  `patches/external__musl/0001-vdso-gnu-hash-symbol-resolution` (teach `__vdsosym` to read GNU hash);
  HyperAlloc's allocation loop calls `nanoTime` per iteration, so this lifts the uncapped rate to
  **~2236 MB/s (~6.8× ZGC)**. Gate: `art-host/test/86-vdso-clock.sh` (asserts the VDSO fast path).
- **The residual ~7× gap is collector throughput, not pointer width.** ZGC also uses uncompressed
  64-bit references and sustains 15 GB/s; the JMH result (`art/jdk26 ≈ art/jdk26-nocoops`) confirms
  8-byte refs are not the cause. The remaining gap is per-small-object allocate+mark cost in ART's CMC
  (rate scales inversely with live-set size and rises to ~3.3 GB/s with larger objects) — CMC is tuned
  for *mobile* goals (low pause, ~1× heap reservation, small footprint), not peak server throughput.
- **Honest takeaway:** art-on-server *removes the 4 GiB ceiling* and runs large-heap workloads
  correctly and now with a JIT-compiled hot path. Closing the residual gap to G1/ZGC is a CMC
  throughput project (parallelize concurrent marking/compaction, speed the allocation fast path).

## A crash this benchmark found — and the fix

The 6 GiB/4 GiB point originally crashed the ART JIT (`SIGSEGV in
QuickExceptionHandler::DeoptimizeSingleFrame`, truncated fault address). Two native-8-byte-reference
bugs in the deoptimization-adjacent runtime, both fixed in `patches/art/0001`:
1. **Deopt vreg transfer** (`runtime/quick_exception_handler.cc`) read each optimized-frame reference
   into a 4-byte `uint32_t` (on-stack `StackReference` read as 4 bytes; in-register read via
   `GetRegisterIfAccessible`, which truncates the GP register to its low 32 bits) before
   `SetVRegReference` — truncating references above 4 GiB. The sibling of OSR (which a prior milestone
   *disabled* rather than fixed). Fixed to read the full 8-byte reference (`StackReference::AsMirrorPtr`
   / `GetGPRAddress`). The intermittent GC-stack-walk crash was a downstream symptom of this.
2. **Alloc/resolution stub null-check** (`runtime/arch/arm64/quick_entrypoints_arm64.S`) tested the
   object result with 32-bit `cbz w0`, so an object whose pointer had zero low-32-bits was misread as
   null → delivered a non-existent exception → abort (~1/4 runs). Fixed to `cbz x0`.

Regression test: `art-host/test/JitDeopt.java` + gate `art-host/test/84-jit-deopt.sh` (forces a
single-frame deopt of compiled code holding a >4 GiB reference; JIT must equal the interpreter).

## The throughput fix this benchmark forced — OSR + a GC-accounting overflow

Chasing the ~31× gap turned up two more native-8-byte-reference bugs, both fixed in `patches/art/0001`:
1. **OSR was disabled and its vreg transfer truncated references** (`runtime/jit/jit.cc`).
   `Jit::PrepareForOsr` copied each interpreter dex-register into the compiled OSR frame as a 4-byte
   `int32_t` — for a reference that read the truncated value-slot summary instead of the full 8-byte
   reference from the shadow frame's `References()`, and wrote only 4 bytes into the 8-byte OSR slot.
   It had been disabled (`kEnableOnStackReplacement=false`) rather than fixed, so long-running loops
   never left the interpreter (the cause of the 496 MB/s). Fixed to write the full 8-byte
   `GetVRegReference(vreg)` for slots the OSR stack-mask marks as references, and **re-enabled**.
   Regression test: `art-host/test/JitOsr.java` + gate `art-host/test/85-jit-osr.sh` (a long counted
   loop holding a >4 GiB reference must OSR and equal the interpreter).
2. **CMC freed-bytes accounting overflowed at >2 GiB** (`runtime/gc/collector/mark_compact.cc`,
   `runtime/gc/space/bump_pointer_space.h`). The moving-space compaction reclaim was stored in an
   `int32_t` (`freed_bytes = black_objs_slide_diff_`); once the moving space passed ~2 GiB it went
   negative, `RecordFree` underflowed `num_bytes_allocated_`, the heap reported 0 free, and HyperAlloc
   died with a spurious `OutOfMemoryError`/SIGSEGV (`freed 17179869183GB` in the GC log). Widened the
   reclaim accounting to `int64_t`. Independent of OSR (reproduces interpreted), but required to run
   the >4 GiB live sets at all.
