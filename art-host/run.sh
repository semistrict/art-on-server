#!/usr/bin/env bash
# Host-side orchestrator for the arm64 host port. Idempotent.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
NAME=art

run_in_vm() {
  echo "==> $1"
  limactl shell "$NAME" -- REPO="$HERE" bash "$HERE/$1"
}

run_in_vm scripts/10-sync.sh
run_in_vm scripts/30-toolchain.sh
run_in_vm scripts/35-apply-patches.sh
run_in_vm scripts/40-bootstrap.sh
run_in_vm scripts/50-build-art.sh
run_in_vm scripts/55-runtime-data.sh
run_in_vm scripts/57-build-static.sh
run_in_vm test/60-smoke-host-art.sh
run_in_vm test/65-gc-verify-host.sh
run_in_vm test/70-static-dalvikvm.sh
# GC / heap-layout acceptance (native 8-byte references, >4 GiB heaps).
run_in_vm test/72-cardtable-stability.sh
run_in_vm test/74-largeobj-gc.sh
run_in_vm test/76-interp-invoke-abi.sh
run_in_vm test/78-bigheap-moving.sh
# Optimizing-JIT 64-bit-reference acceptance (the 4 GiB-cap removal for compiled code).
run_in_vm test/79-jit-correctness.sh
run_in_vm test/80-jit-ref.sh
run_in_vm test/81-jit-largeheap.sh
run_in_vm test/82-jit-intrinsics.sh

echo "art-host run: OK"
