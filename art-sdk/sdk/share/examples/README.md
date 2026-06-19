# Examples

All commands assume the SDK's `bin/` is on your `PATH` (or prefix with
`/path/to/sdk/bin/`).

## Hello, world

```sh
art compile -d hello.dex.jar Hello.java
art run -cp hello.dex.jar Hello
art run -cp hello.dex.jar Hello Ramon      # -> Hello, Ramon, from ART on aarch64
```

## Using a Maven dependency (transparent dexing)

`InventoryReport.java` uses Gson — a normal `.class` jar from Maven Central,
with no pre-dexing. The SDK dexes it on the fly and caches the result.

```sh
curl -O https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.jar
art compile -cp gson-2.11.0.jar -d inventory.dex.jar InventoryReport.java
art run     -cp inventory.dex.jar:gson-2.11.0.jar InventoryReport
```

The first `art run` dexes `gson-2.11.0.jar` once (into `~/.cache/artsdk/dex/`);
subsequent runs are instant.

## A large heap

The runtime uses native pointer-width (8-byte) references and the CMC collector,
so it is not capped at 4 GiB. `HeapStress` builds a large, cross-linked object
graph, churns garbage to force concurrent compaction, and re-verifies every
retained object's identity and links afterwards — proving references survive
moving GC well past the old 4 GiB ceiling.

```sh
art compile -d heapstress.dex.jar HeapStress.java
art run -Xmx10g -cp heapstress.dex.jar HeapStress 5     # ~5.6 GiB live, verify after GC
# -> HEAPSTRESS OK: verified 55924053 nodes after GC, peak heap ~5643 MiB
```

This builds ~56M small linked nodes (well past 4 GiB), churns garbage to force the
concurrent mark-compact collector, and re-verifies every retained node after GC —
proving references survive moving collection above the old 4 GiB ceiling for
*small-object* heaps, not just large buffers. It runs on the interpreter (the
SDK's correct, stable default — see "Execution modes" in the top-level README). To
double-check GC integrity, add `-Xgc:CMC,preverify,postverify`.

## Faster startup with an AOT boot image

```sh
art compile-boot          # one-time per install; caches a boot image
art run -cp hello.dex.jar Hello   # now starts from the compiled image
```
