# art-on-server — ART on Linux with native 64-bit object references

Run server-side **Java and Kotlin** on the **Android Runtime (ART)**, natively on
Linux (arm64), with the classic **4 GiB managed-heap ceiling removed**. ART uses
native pointer-width (8-byte, uncompressed) object references — HotSpot's
`-XX:-UseCompressedOops` model — made 64-bit-clean end to end across the runtime,
the CMC concurrent mark-compact GC, the switch interpreter, **and the optimizing
JIT** (codegen, intrinsics, stubs, and the calling convention). `-Xmx` well past
4 GiB works for every allocation pattern, on both the interpreter and the JIT.

## Layout

- [`art-host/`](art-host/) — the ART fork and the host build pipeline. Builds
  `dalvikvm`/`libart`/`dex2oat` for linux-arm64 against a musl toolchain
  (statically linkable). Contains:
  - `patches/art/0001-*.patch` — the native-64-bit-reference + static-dalvikvm fork.
  - `patches/{bionic,build__make,build__soong,external__*,libcore,…}` — arm64-musl host enablement.
  - `scripts/` — sync → toolchain → patch → bootstrap → build → static-link.
  - `test/` — GC/card-table/large-object/big-heap gates (72/74/76/78) and
    optimizing-JIT 64-bit-reference correctness gates (79–82); the interpreter
    (`-Xint`) is the oracle the JIT must match.
  - `run.sh` — orchestrates the build and the full acceptance suite in the VM.

- [`art-sdk/`](art-sdk/) — the distributable SDK built on top: a self-contained
  tarball with the `art` driver (run / compile / kotlinc / d8 / aot / selftest),
  the CMC collector by default, transparent dexing of ordinary Maven/Gradle
  `.class` jars, and Java + Kotlin examples. Defaults to the optimizing JIT at
  every heap size (`ARTSDK_INT=1` forces the interpreter as a correctness oracle).
  See [`art-sdk/sdk/README.md`](art-sdk/sdk/README.md).

## Status

The 4 GiB cap is removed for **both** the interpreter and the optimizing JIT, at
every heap size verified to 6+ GiB. JIT reference correctness — fields, arrays,
virtual/interface dispatch, streams/lambdas/boxing, the hand-written arm64
intrinsics (arraycopy / VarHandle CAS / `String.equals` / `Reference`), the
write-barrier card table, the GC stack-root scan, and references passed in the
outgoing stack-argument area — is gated by `art-host/test/79`–`82` against the
interpreter oracle.
