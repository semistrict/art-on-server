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
3g / 1 GiB   (<=4 GiB)         2048       2035        2035            620
6g / 4 GiB   (>4 GiB live)     2048       2035        2035            480
9g / 7 GiB   (>4 GiB live)     2048       2035        2035            450
```

**Uncapped** max allocation rate at 6 GiB heap / 4 GiB live (>4 GiB), `-a 100000`:

```
jdk26-ZGC  15282 MB/s
jdk26-G1   13915 MB/s
art-CMC      496 MB/s
```

## What the numbers say

- **The headline works.** art-on-server holds a **4 GiB and 7 GiB live set** and keeps allocating
  with no crash — impossible on stock ART (4-byte references cap the heap at ~4 GiB). ZGC is the apt
  peer (also concurrent, also uncompressed 8-byte refs) and confirms the workload is well-formed.
- **ART CMC is much lower throughput than HotSpot's server collectors** — ~3–4× under the fixed
  target, ~**28–31× at the uncapped ceiling** (496 MB/s vs ZGC's 15.3 GB/s). ART's CMC is tuned for
  *mobile* goals (low pause, ~1× heap reservation, small footprint), not peak server allocation
  throughput.
- **The 8-byte references are not the cause.** ZGC also uses uncompressed 64-bit references and
  sustains 15 GB/s; the gap is collector design, not pointer width — consistent with the JMH result
  (`art/jdk26 ≈ art/jdk26-nocoops`).
- **Honest takeaway:** art-on-server *removes the 4 GiB ceiling* and runs large-heap workloads
  correctly, but is a low-throughput collector relative to G1/ZGC. The differentiator is heap
  capacity + low-pause behavior, not allocation throughput.

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
