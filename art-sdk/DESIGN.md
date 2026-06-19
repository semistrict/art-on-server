# ART SDK for Linux — design

A self-contained, distributable SDK for building and running JVM-language
server applications on the Android Runtime (ART), natively on Linux. No
Android device, no bionic chroot, no root. One tarball you unpack and use.

## Why ART on servers

- **CMC garbage collector**: concurrent compaction via userfaultfd with *no
  read barriers* — the only production runtime besides OpenJDK that compacts
  concurrently, and unlike ZGC/Shenandoah it pays no per-load barrier tax.
  Measured in this project: 7–600µs pauses under multi-threaded churn.
- **AOT-first**: dex2oat compiles boot + app images ahead of time → instant
  startup, shared clean pages across processes, predictable performance.
- Battle-tested on billions of devices; small footprint next to a JDK.

## What's in the box

```
artsdk-<version>-linux-<arch>/
  bin/
    art             # launcher / driver (run, compile, aot, test, selftest)
    dalvikvm        # the runtime (linux_musl, static or mostly-static)
    dex2oat         # AOT compiler
    d8              # dex compiler (wrapper running r8.jar on dalvikvm)
    javac-art       # java source compiler (ECJ running on dalvikvm)
    oatdump dexdump profman   # diagnostics
  lib/
    bootjars/       # core-oj, core-libart, okhttp, bouncycastle, apache-xml,
                    # core-icu4j, conscrypt (the SDK bootclasspath)
    boot/<arch>/    # prebuilt boot image (boot.art/.oat/.vdex)
    icu/icudt.dat   # ICU data
    tzdata/
    tools/          # r8.jar + ecj dex (the self-hosted dex toolchain)
  share/
    maven/          # art-maven-plugin (generalized from minihub-maven-plugin)
    examples/
  tests/            # post-install acceptance: `art selftest`
  docs/
```

Two distribution tiers:

1. **SDK tarball** (`.tar.zst`, target ≈ 60–80 MB): everything above.
2. **Standalone runtime** (`art-standalone`, single file ≈ 30–40 MB): static
   dalvikvm + embedded boot image + app dex — the scp-and-run artifact for
   deployments. Produced by `art aot --standalone app.jar`.

## Developer experience

- `art run -cp app.dex Main` — run a dex jar.
- `art compile src/ -o app.dex` — ECJ + d8 in one step (`go build` feel).
- `art aot app.dex` — dex2oat app image for instant startup.
- `art selftest` — run the SDK acceptance suite on the installed SDK.
- Maven: `art-maven-plugin` with compile / dex / test goals (ported from the
  proven minihub plugin; tests execute on dalvikvm).
- **Env-free**: the launcher derives all paths (`BOOTCLASSPATH`, boot image,
  ICU/tzdata roots) relative to its own location. No `ANDROID_*` exports.

## Engineering foundation (status)

| Piece | Source | Status |
|---|---|---|
| Runtime/compiler for linux-arm64 | `~/src/art-host` fork of AOSP master-art (linux_musl-arm64 host port) | building; build system fully bootstrapped natively |
| Boot jars + boot image | same build (`m` host targets) | after runtime |
| Dex toolchain (r8, ECJ on ART) | proven in `~/src/minihub` | done, needs re-packaging |
| Maven plugin | `~/src/minihub/tools/maven-plugin` | done, needs generalizing |
| Acceptance tests | art-server smoke/GC-verify + minihub unit/API suites | done, need porting from chroot to SDK layout |
| Static link | upstream `art_static_defaults` + `BUILD_HOST_static=true` musl flow | after dynamic works |

## Platform roadmap

1. **linux-arm64** — the current fork (only configuration needing new work).
2. **linux-x86_64** — upstream-supported host config; mostly packaging.
3. **macOS (darwin-arm64)** — Soong supports darwin-arm64 hosts; ART host on
   macOS is a larger port (no userfaultfd → different GC default).

The fork stays a patch series over AOSP `master-art`
(`~/src/art-host/patches/*`), applied idempotently after sync — rebases
stay tractable and each platform adds its own small series.

## Versioning

SDK versions track the ART module: `artsdk 36.x` ≈ Android 16 ART. The
runtime ABI (dex version, oat version) is pinned per SDK release; app dex is
forward-portable, oat artifacts are not (regenerate on SDK upgrade —
`art aot` makes that cheap).

## Open questions (defaults chosen, revisit later)

- musl-static vs mostly-static dalvikvm default → **static** for portability.
- ICU data embedded vs external → **external file** (29 MB; embedding is a
  later size optimization).
- JIT profiles / dex2oat caches → `~/.cache/artsdk`.
- Windows/WSL: out of scope until macOS lands.
