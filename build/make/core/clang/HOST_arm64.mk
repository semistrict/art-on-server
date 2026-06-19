# Clang config for an arm64 Linux build host (linux_musl-arm64). The runtime
# archives live in the per-triple directory of the linux-arm64 clang prebuilt.
HOST_LIBPROFILE_RT := $(LLVM_RTLIB_PATH)/aarch64-unknown-linux-musl/libclang_rt.profile.a
HOST_LIBCRT_BUILTINS := $(LLVM_RTLIB_PATH)/aarch64-unknown-linux-musl/libclang_rt.builtins.a
