# How the ART SDK works

## The pieces

```
your .java/.kt ──ECJ/kotlinc(on ART)──▶ .class ──d8(on ART)──▶ dex ──▶ dalvikvm
   Maven .class jars ─────────transparent d8 + content-hash cache────────▶ dex ─┘
```

Everything — the Java compiler (ECJ), the Kotlin compiler, the dex compiler
(R8/D8) — is itself dexed and runs *on ART*. The SDK is self-hosting: there is
no JDK in the box.

## Transparent classpath dexing

ART executes dex, but the world ships `.class` JARs. `art run` resolves its
`-cp` through `libexec/art-dexcp`:

1. Split the classpath.
2. For each entry: if it already contains `classes*.dex`, use it as-is;
   otherwise (a normal Maven `.class` jar, or a directory of `.class` files)
   compile it to dex with `d8` and cache the result at
   `~/.cache/artsdk/dex/<sha256-of-input>.jar`.
3. Hand the all-dex classpath to the runtime.

Content-hash keying means each dependency is dexed exactly once across all
apps and runs. This is what makes the JVM/Maven ecosystem usable on ART without
a build-system plugin.

## The CMC garbage collector

ART's default is the **Concurrent Mark-Compact** collector:

- **Marks** live objects concurrently with the mutator.
- **Compacts** (relocates objects to defragment) concurrently, using the
  kernel's `userfaultfd`: pages being relocated are registered for
  user-space fault handling, so a mutator that touches a mid-relocation page
  traps into ART, which forwards the access — no stop-the-world move.
- Uses **no read barriers** (unlike ART's older Concurrent Copying collector
  and unlike ZGC/Shenandoah on HotSpot), so ordinary field reads in compiled
  code are plain loads. And being a *compactor* rather than a *copier*, it
  reserves **1×** the heap, not 2×.

The SDK launcher defaults to `-Xgc:CMC`. You can verify it at runtime with
`-verbose:gc` (look for `CollectorTypeCMC` and `concurrent mark compact GC
freed ...`).

## Native (64-bit) object references — no 4 GiB heap cap

Stock ART stores object references as **32-bit** values (the low bits of the
address), which confines the entire managed heap to the low 4 GiB of the
address space. That is fine for a phone app; it is not fine for a server.

This SDK's runtime uses **native pointer-width (64-bit) references** — the
HotSpot `-XX:-UseCompressedOops` model. A reference is simply the object's
address, so:

- the heap can be arbitrarily large and live anywhere in the address space;
- there is no shift/decode cost on reference access;
- reference fields are naturally (8-byte) aligned, so volatile/atomic access
  and the concurrent collector stay correct.

The cost is 4 extra bytes per reference field. For server workloads that trade
readily for an unbounded heap.

The object header becomes a native-width class reference plus the 4-byte lock
word (12 bytes), and array/instance layout derives every offset from that
header size — aligning the first element up to 8 bytes for `long`/`double`/
reference arrays, exactly as HotSpot's `arrayOop::base_offset_in_bytes` does.
Object instances pack subclass fields into the header's alignment tail rather
than wasting it, so the per-object overhead is just the wider class reference.

## AOT and JIT

- `dex2oat` ahead-of-time compiles dex to native `.oat`/`.art` images.
  `art compile-boot` builds a boot image for the SDK's core classes into the
  per-install cache (the image embeds absolute paths, so it cannot ship in the
  relocatable tarball); `art aot app.dex.jar` builds an app image.
- At run time the JIT re-profiles and re-optimizes hot methods.
- Without an image the runtime interprets + JITs from dex directly
  (`-Xnoimage-dex2oat`), which is the default until you run `art compile-boot`.

## Relocatable, env-free

`bin/art` resolves the SDK root from its own path and sets every runtime root
(bootclasspath, ICU, tzdata, CA certs) relative to it. Unpack the tarball
anywhere and run; nothing touches the environment or the system.
