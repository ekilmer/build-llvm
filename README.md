# Scripts to time LLVM Builds

Lets time LLVM builds!

The scripts included here will build LLVM (currently LLVM 11) and time how long it takes to build the proper binaries.

To ensure consistency, the following build process is used:

* Build LLVM 11 and clang-11 with host compiler.
* Build LLVM 11 and clang-11 again, with newly built LLVM11.
* Time a build cross compiling to the other architecture (x86-64 for arm64 and vice versa).
* (Linux Only): Optionally build form a tmpfs mount to remove disk I/O as a bottleneck of build times.

## Build Settings

The following build settings are used during build:
* Clang-11 and LLVM-11 from the [official source tarball](https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/llvm-project-11.0.0.tar.xz).
* Build Clang in addition to LLVM (`-DLLVM_ENABLE_PROJECTS=clang`).
* Release mode build (`-DCMAKE_BUILD_TYPE=Release`)
* Ninja is used as the build system (`-G Ninja`)
* Optimize for the native processor (`-mtune=native`)

## Supported Platforms
* Linux (x86-64 and arm64), tested on Ubuntu 18.04
* MacOS (x86-64 tested), tested on MacOS 10.15.7


