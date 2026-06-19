# ART SDK for Linux

Run and build server-side **Java and Kotlin** on the **Android Runtime (ART)**,
natively on Linux — no Android device, no emulator, no chroot, no root. One
tarball you unpack and use.

```sh
tar --zstd -xf artsdk-<ver>-linux-arm64.tar.zst
cd artsdk-<ver>-linux-arm64
bin/art selftest                      # prove the install works
bin/art compile -d hello.dex.jar share/examples/Hello.java
bin/art run -cp hello.dex.jar Hello
```

That's it — the launcher derives every path from its own location, so there's
nothing to configure and nothing to put on `PATH` unless you want to.

## Why ART on a server

ART is the runtime that executes billions of app processes on Android. Its
design goals — fast startup, small footprint, low-latency GC — are exactly
what latency-sensitive server services want.

- **CMC garbage collector.** ART's default collector is *Concurrent
  Mark-Compact*: it compacts the heap concurrently with your application using
  the kernel's `userfaultfd`, and — unlike HotSpot's ZGC/Shenandoah — it does
  it with **no read barriers**, so there is no per-field-read tax. Measured in
  this project: GC pauses in the **microsecond-to-low-millisecond** range under
  multi-threaded allocation churn, with a heap reservation of **1×** (not 2×).
- **No 4 GiB heap ceiling.** This SDK uses *native pointer-width* (8-byte,
  uncompressed) object references — HotSpot's `-XX:-UseCompressedOops` model —
  so the managed heap is not capped at the classic ART/compressed-oops 4 GiB
  limit. `-Xmx` well past 4 GiB works for every allocation pattern: the heap
  layout, the large-object space, the card table, **and the concurrent
  mark-compact collector's per-chunk/per-page offset bookkeeping** were all made
  64-bit-clean. Verified to 6+ GiB live for both large-buffer heaps (5 GiB of
  arrays) and graphs of *many small objects* (67M-object, ~6.8 GiB heaps survive
  concurrent compaction with heap-verification enabled) — and the **optimizing
  JIT is correct at every heap size, including past 4 GiB** (see *Execution
  modes*).
- **AOT-first.** `dex2oat` compiles ahead of time to native code, for instant
  startup and clean shared pages across processes.
- **The whole JVM ecosystem, transparently.** ART runs `dex`, but the SDK
  consumes ordinary `.class` JARs from Maven/Gradle: any classpath entry that
  isn't already dex is compiled to dex on the fly and cached by content hash
  (see *Transparent classpath* below). Your dependencies Just Work.
- **Small.** The runtime is a fraction of a JDK's size, and ships as a single
  static binary with no shared-library dependencies.

## The `art` driver

| Command | What it does |
|---|---|
| `art run -cp <cp> Main [args]` | Run a program. `.class` jars on `-cp` are dexed transparently. |
| `art compile [-cp DEPS] [-d out.dex.jar] <srcs>` | Compile `.java` (ECJ) → dex (d8), both on ART. |
| `art kotlinc [-cp DEPS] [-d out.dex.jar] <.kt>` | Compile Kotlin (kotlinc on ART) → dex. Fetches the Kotlin compiler on first use. |
| `art d8 [args]` | The dex compiler (R8/D8) directly. |
| `art aot <app.dex.jar>` | AOT-compile an app image for instant startup. |
| `art compile-boot` | Build a boot image into the per-install cache (faster startup). |
| `art selftest` | Run the SDK acceptance suite. |
| `art version` | Versions. |

The runtime defaults to the CMC collector (`-Xgc:CMC`); pass your own `-Xgc:` /
`-Xmx` / `-XX:` flags to `art run` to override.

## Transparent classpath (consume Maven/Gradle jars)

```sh
# A real dependency straight from Maven Central — a normal .class jar.
curl -O https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.jar

art compile -cp gson-2.11.0.jar -d app.dex.jar MyApp.java
art run     -cp app.dex.jar:gson-2.11.0.jar MyApp
```

`art run` inspects each `-cp` entry: dex jars are used as-is; `.class` jars and
class directories are compiled to dex with `d8` and cached under
`~/.cache/artsdk/dex/<sha256>.jar`, so the first run pays the dexing cost once
and every run after is instant. This is what lets ART consume the JVM library
ecosystem unchanged.

## Kotlin

```sh
curl -O https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.1/kotlinx-coroutines-core-jvm-1.8.1.jar
art kotlinc -cp kotlinx-coroutines-core-jvm-1.8.1.jar -d app.dex.jar Coroutines.kt
art run -cp app.dex.jar:kotlinx-coroutines-core-jvm-1.8.1.jar CoroutinesKt
```

The Kotlin compiler itself runs on ART (it is dexed and cached on first use),
and the Kotlin stdlib + `kotlinx.coroutines` are ordinary Maven jars consumed
through transparent dexing. Data classes, the stdlib, and coroutines all work.

## Layout

```
bin/        art driver, dalvikvm (runtime), dex2oat, d8, javac-art
lib/
  bootjars/ the SDK bootclasspath (core-oj, core-libart, core-icu4j, okhttp,
            bouncycastle, apache-xml, conscrypt) as dex
  compile/  OSS (AOSP libcore) .class stubs — the compile-time classpath
  tools/    r8 + ECJ, dexed to run on ART
  i18n/     ICU data        tzdata/  time-zone data       android/ CA trust store
libexec/    compile / aot / boot-image / classpath-dexing helpers
share/      examples
tests/      selftest + sources
```

## Compatibility & limits

- **Language level.** Sources compile at Java 8 source/target by default
  against the OSS core stubs; bytecode from any JVM language is accepted by d8
  (min-api 34), so modern library jars run fine.
- **Heap.** The SDK defaults to the CMC collector and the full managed-heap
  range is usable (see `docs/` for sizing). Native pointer-width references
  remove the classic ART 4 GiB ceiling; `-Xmx` well past 4 GiB is supported.
- **What does *not* work (yet):** JVMTI agents and tools that attach a native
  agent `.so`; libraries that ship their own JNI `.so` (pure-JVM jars are
  fine); `Unsafe`-heavy code that assumes a HotSpot object layout. Off-heap
  (`DirectByteBuffer`) works and is the recommended path for very large
  buffers.

## Execution modes

The move to native pointer-width references is complete and correct in **both**
the switch interpreter **and the optimizing JIT**, at **every heap size,
including well past 4 GiB**.

The **interpreter** reads, writes, and spills full 8-byte references and agrees
with the 8-byte heap/GC representation throughout.

The **optimizing JIT** treats a reference as a native 8-byte value end to end:
the register allocator, spill slots, load/store width, the managed calling
convention, virtual/interface dispatch (including the inlined `IfTable`
interface-check scan), the JIT class/string GC-root tables, the GC stack-root
stride, the inline-cache stub, the TLAB allocation fast path, and the
write-barrier card-table index (`object >> kCardShift`) are all 64-bit-clean.
The dex-vs-machine width distinction is handled by a `DataType::IsWideType`
(long/double = two dex registers) vs `Is64BitType` (8-byte machine value, now
including references) split. Reference field loads, reference array loads
(8-byte-scaled), null checks, `instanceof`/`checkcast` (including interface
checks), autoboxing (`Integer.valueOf` reading the static `IntegerCache.cache[]`
array), static reference fields, `java.util` stream pipelines and
method-reference lambdas (`map.values().stream().mapToInt(Integer::intValue).sum()`),
iterators, object arrays, `HashMap`, and the implicit-suspend / GC-root / deopt /
inline-cache / GC-stack-scan paths all agree with the interpreter — verified
**at both ≤4 GiB and >4 GiB heaps** (`test/79-jit-correctness.sh`,
`test/80-jit-ref.sh`, plus the `JitBox` / `JitStream` >4 GiB acceptance runs).

The JIT is the recommended mode for all workloads; the interpreter remains
available (`-Xint`) as a correctness oracle and for debugging.

| Workload | Recommended mode |
|---|---|
| Anything (any heap size, including > 4 GiB) | optimizing JIT (default) |
| Debugging / a correctness oracle | interpreter (`-Xint`) |

## License

The runtime, core libraries, and dex toolchain are AOSP (Apache-2.0, with the
OpenJDK-derived `libcore` parts under GPLv2+CPE, as in any JDK). The SDK
packaging and examples in this project are Apache-2.0. No proprietary or
non-OSI components are bundled.
