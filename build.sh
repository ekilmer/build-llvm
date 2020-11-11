#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ARCH=$(uname -m)

set -euo pipefail
set -x

# install our build tools

if [[ "${ARCH}" == "x86_64" ]]
then
  sudo dpkg --add-architecture arm64
else
  sudo dpkg --add-architecture amd64
fi

sudo apt update || true
sudo apt install -qyy xz-utils curl cmake clang-10 ninja-build
# for cross compiling
if [[ "${ARCH}" == "x86_64" ]]
then
  sudo apt install -qyy gcc-7-aarch64-linux-gnu binutils-aarch64-linux-gnu libstdc++6-arm64-cross libgcc1-arm64-cross libstdc++-7-dev-arm64-cross
  sudo apt install -qyy libtinfo5:arm64 zlib1g:arm64 libxml2-dev:arm64 liblzma5:arm64 libicu-dev:arm64
else
  sudo apt install -qyy gcc-7-x86-64-linux-gnu binutils-x86-64-linux-gnu libstdc++6-amd64-cross libgcc1-amd64-cross libstdc++-7-dev-amd64-cross
  sudo apt install -qyy libtinfo5:amd64 zlib1g:amd64 libxml2-dev:amd64 liblzma5:amd64 libicu-dev:amd64
fi

# fetch clang-11 & llvm-11
if [[ ! -f "${DIR}/llvm.tar.xz" ]]
then
  curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/llvm-project-11.0.0.tar.xz --output llvm.tar.xz
fi

if [[ ! -d "${DIR}/llvm" ]]
then
  mkdir ${DIR}/llvm
fi

# always unmount, just in case
sudo umount ${DIR}/llvm || true
sudo mount -t tmpfs \
    -o size=12G,uid=$(id -u),gid=$(id -g) \
    tmpfs \
    $(pwd)/llvm

#extract it
mkdir -p llvm/bootstrap-native
mkdir -p llvm/build-native
mkdir -p llvm/build-cross
tar -xJf llvm.tar.xz --strip-components=1 -C llvm/

function bootstrap_native() {
pushd llvm
cd bootstrap-native
CC=clang-10 CXX=clang++-10 cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DCMAKE_C_FLAGS="-mtune=native" \
  -DCMAKE_CXX_FLAGS="-mtune=native" \
  -DCMAKE_INSTALL_PREFIX=${DIR}/native-bin \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/bootstrap_native.time
ninja install
popd
}

# build a native arch with boostrapped compiler
function build_native() {
pushd llvm
cd build-native
CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/build_native.time
popd
}

# cross compile aarch64 with native compiler (on amd64)
function build_cross_aarch64() {
pushd llvm
cd build-cross

# patch libc.so and libpthread.so to use relative paths
sudo cp ${DIR}/aarch64/libc.so /usr/aarch64-linux-gnu/lib/
sudo cp ${DIR}/aarch64/libpthread.so /usr/aarch64-linux-gnu/lib/

CROSS_ARGS="-target aarch64-linux-gnu --gcc-toolchain=/usr -isystem/usr/aarch64-linux-gnu/include/c++/7/aarch64-linux-gnu"
CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
  -DCMAKE_CROSSCOMPILING=True \
  -DLLVM_TABLEGEN=${DIR}/native-bin/bin/llvm-tblgen \
  -DCLANG_TABLEGEN=${DIR}/llvm/build-native/bin/clang-tblgen \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_TARGET_ARCH=AArch64 \
  -DCMAKE_C_FLAGS="${CROSS_ARGS}" \
  -DCMAKE_CXX_FLAGS="${CROSS_ARGS}" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-linux-gnu \
  -DCMAKE_SYSROOT="/usr/aarch64-linux-gnu" \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_aarch64.time
popd
}

# cross compile amd64 with native compiler (on aarch64)
function build_cross_amd64() {
pushd llvm
cd build-cross

sudo cp ${DIR}/amd64/libc.so /usr/x86_64-linux-gnu/lib/
sudo cp ${DIR}/amd64/libpthread.so /usr/x86_64-linux-gnu/lib/
sudo cp ${DIR}/amd64/libm.so /usr/x86_64-linux-gnu/lib/

CROSS_ARGS="-target x86_64-linux-gnu --gcc-toolchain=/usr -isystem/usr/x86_64-linux-gnu/include/c++/7/x86_64-linux-gnu"
CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
  -DCMAKE_CROSSCOMPILING=True \
  -DLLVM_TABLEGEN=${DIR}/native-bin/bin/llvm-tblgen \
  -DCLANG_TABLEGEN=${DIR}/llvm/build-native/bin/clang-tblgen \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_TARGET_ARCH=X86 \
  -DCMAKE_C_FLAGS="${CROSS_ARGS}" \
  -DCMAKE_CXX_FLAGS="${CROSS_ARGS}" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-linux-gnu \
  -DCMAKE_SYSROOT="/usr/x86_64-linux-gnu" \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_amd64.time
popd
}

# get us a fresh build of llvm11 that doesn't break
bootstrap_native

# build llvm11 with llvm11
build_native

if [[ "${ARCH}" == "x86_64" ]]
then
  build_cross_aarch64
else
  build_cross_amd64
fi
