#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ARCH=$(uname -m)

set -euo pipefail
set -x

# install our build tools

function macos_prepare() {
  brew update || true
  brew install cmake ninja xz
}

function linux_prepare() {
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
}

function prepare_llvm() {
  local use_tmpfs=$1
# fetch clang-11 & llvm-11
if [[ ! -f "${DIR}/llvm.tar.xz" ]]
then
  curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/llvm-project-11.0.0.tar.xz --output llvm.tar.xz
fi

if [[ ! -d "${DIR}/llvm" ]]
then
  mkdir ${DIR}/llvm
fi

if [[ "${use_tmpfs}" == "tmpfs" ]]
then
# always unmount, just in case
sudo umount ${DIR}/llvm || true
sudo mount -t tmpfs \
    -o size=12G,uid=$(id -u),gid=$(id -g) \
    tmpfs \
    $(pwd)/llvm
elif [[ "${use_tmpfs}" == "drive" ]]
then
  rm -rf ${DIR}/llvm
  mkdir ${DIR}/llvm
else
  echo "Must specify [drive] or [tmpfs] to prepare_llvm"
  exit 1
fi


#extract it
mkdir -p llvm/bootstrap-native
mkdir -p llvm/build-native
mkdir -p llvm/build-cross
tar -xJf llvm.tar.xz --strip-components=1 -C llvm/
}

function macos_bootstrap_native() {
pushd llvm
cd bootstrap-native
NATIVE_ARGS="-mtune=native -isysroot $(xcrun --show-sdk-path)"
CC=clang CXX=clang++ cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DCMAKE_C_FLAGS="${NATIVE_ARGS}" \
  -DCMAKE_CXX_FLAGS="${NATIVE_ARGS}" \
  -DCMAKE_INSTALL_PREFIX=${DIR}/native-bin \
  -DCMAKE_SYSROOT="$(xcrun --show-sdk-path)" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/bootstrap_native.time
ninja install
popd
}

function linux_bootstrap_native() {
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

function macos_build_native() {
pushd llvm
cd build-native
NATIVE_ARGS="-mtune=native -isysroot $(xcrun --show-sdk-path) -I/Library/Developer/CommandLineTools/usr/include/c++/v1 -L$(xcrun --show-sdk-path)/usr/lib/ -Wno-unused-command-line-argument"
CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DCMAKE_C_FLAGS="${NATIVE_ARGS}" \
  -DCMAKE_CXX_FLAGS="${NATIVE_ARGS}" \
  -DCMAKE_SYSROOT="$(xcrun --show-sdk-path)" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/build_native.time
popd
}

# build a native arch with boostrapped compiler
function linux_build_native() {
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

function macos_build_cross_aarch64() {
pushd llvm
cd build-cross

CROSS_ARGS="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -I/Library/Developer/CommandLineTools/usr/include/c++/v1 -L$(xcrun --sdk iphoneos --show-sdk-path)/usr/lib/ -Wno-unused-command-line-argument"
CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
  -DCMAKE_CROSSCOMPILING=True \
  -DLLVM_TABLEGEN=${DIR}/llvm/bootstrap-native/bin/llvm-tblgen \
  -DCLANG_TABLEGEN=${DIR}/llvm/bootstrap-native/bin/clang-tblgen \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_TARGET_ARCH=AArch64 \
  -DCMAKE_C_FLAGS="${CROSS_ARGS}" \
  -DCMAKE_CXX_FLAGS="${CROSS_ARGS}" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-apple-darwin19.6.0 \
  -DCMAKE_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_amd64.time
popd
}

# cross compile aarch64 with native compiler (on amd64)
function linux_build_cross_aarch64() {
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
function linux_build_cross_amd64() {
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

if [[ "${OSTYPE}" == "linux-gnu"* ]]
then
  linux_prepare
  prepare_llvm tmpfs
  # get us a fresh build of llvm11 that doesn't break
  linux_bootstrap_native
  # build llvm11 with llvm11
  linux_build_native
  if [[ "${ARCH}" == "x86_64" ]]
  then
    linux_build_cross_aarch64
  else
    linux_build_cross_amd64
  fi
elif [[ "${OSTYPE}" == "darwin"* ]]
then
  macos_prepare
  prepare_llvm drive
  macos_bootstrap_native
  macos_build_native
  if [[ "${ARCH}" == "x86_64" ]]
  then
    macos_build_cross_aarch64
  else
    macos_build_cross_amd64
  fi
else
  echo "Unsupported OS: ${OSTYPE}"
  exit 1
fi
