#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ARCH=$(uname -m)
export DEBIAN_FRONTEND=noninteractive

set -euo pipefail
#set -x

DISTRIB_ID=Unknown
if [[ -f /etc/lsb-release ]]
then
  source /etc/lsb-release
fi

# install our build tools

function macos_prepare() {
  brew update || true
  brew install cmake ninja xz || true
}

function linux_prepare() {

# Tune opt set according to:
# https://community.arm.com/developer/tools-software/tools/b/tools-software-ides-blog/posts/compiler-flags-across-architectures-march-mtune-and-mcpu
if [[ "${ARCH}" == "x86_64" ]]
then
  sudo dpkg --add-architecture arm64
  TUNE_OPTS="-march=native"
else
  sudo dpkg --add-architecture amd64
  TUNE_OPTS="-mcpu=native"
fi

sudo apt update || true
sudo apt install -qyy xz-utils curl cmake lld-10 clang-10 ninja-build time
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
    ${DIR}/llvm
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
NATIVE_ARGS="${TUNE_OPTS} -isysroot $(xcrun --show-sdk-path)"
CC=clang CXX=clang++ cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=clang \
  -DLLVM_ENABLE_LTO=On \
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
  -DLLVM_ENABLE_LTO=On \
  -DLLVM_ENABLE_LLD=True \
  -DCMAKE_C_FLAGS="${TUNE_OPTS}" \
  -DCMAKE_CXX_FLAGS="${TUNE_OPTS}" \
  -DCMAKE_INSTALL_PREFIX=${DIR}/native-bin \
  -G Ninja \
  ../llvm

/usr/bin/time -p cmake --build . 2> ${DIR}/bootstrap_native.time
ninja install
popd
}

function macos_build_native() {
pushd llvm

for round in $(seq 1 ${BUILD_ROUNDS})
do
  mkdir build-native && cd build-native
  NATIVE_ARGS="${TUNE_OPTS} -isysroot $(xcrun --show-sdk-path) -I/Library/Developer/CommandLineTools/usr/include/c++/v1 -L$(xcrun --show-sdk-path)/usr/lib/ -Wno-unused-command-line-argument"
  CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS=clang \
    -DCMAKE_C_FLAGS="${NATIVE_ARGS}" \
    -DCMAKE_CXX_FLAGS="${NATIVE_ARGS}" \
    -DCMAKE_SYSROOT="$(xcrun --show-sdk-path)" \
    -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
    -G Ninja \
    ../llvm

  /usr/bin/time -p cmake --build . 2> ${DIR}/build_native_${round}.time
  cd .. && rm -rf build-native
done
popd
}

# build a native arch with boostrapped compiler
function linux_build_native() {
pushd llvm
for round in $(seq 1 ${BUILD_ROUNDS})
do
  mkdir build-native && cd build-native
  CC=${DIR}/native-bin/bin/clang CXX=${DIR}/native-bin/bin/clang++ cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS=clang \
    -G Ninja \
    ../llvm

  /usr/bin/time -p cmake --build . 2> ${DIR}/build_native_${round}.time
  cd .. && rm -rf build-native
done
popd
}

function macos_build_cross_aarch64() {
pushd llvm
for round in $(seq 1 ${BUILD_ROUNDS})
do
  mkdir build-cross && cd build-cross

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

  /usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_amd64_to_aarch64_${round}.time

  cd .. && rm -rf build-cross
done
popd
}

# cross compile aarch64 with native compiler (on amd64)
function linux_build_cross_aarch64() {

# patch libc.so and libpthread.so to use relative paths
if [[ "${DISTRIB_ID}" == "Ubuntu" ]]
then
  sudo cp ${DIR}/aarch64/libc.so /usr/aarch64-linux-gnu/lib/
  sudo cp ${DIR}/aarch64/libpthread.so /usr/aarch64-linux-gnu/lib/
fi

pushd llvm
for round in $(seq 1 ${BUILD_ROUNDS})
  do
    mkdir build-cross && cd build-cross

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

    /usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_amd64_to_aarch64_${round}.time
    cd .. && rm -rf build-cross
  done
popd
}

function macos_build_cross_amd64() {
pushd llvm
cd build-cross
echo "Building to AMD64 on MacOS ARM64 not yet supported"
popd
exit 1
}

# cross compile amd64 with native compiler (on aarch64)
function linux_build_cross_amd64() {
if [[ "${DISTRIB_ID}" == "Ubuntu" ]]
then
  sudo cp ${DIR}/amd64/libc.so /usr/x86_64-linux-gnu/lib/
  sudo cp ${DIR}/amd64/libpthread.so /usr/x86_64-linux-gnu/lib/
  sudo cp ${DIR}/amd64/libm.so /usr/x86_64-linux-gnu/lib/
fi

pushd llvm

for round in $(seq 1 ${BUILD_ROUNDS})
do
  mkdir build-cross && cd build-cross

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

  /usr/bin/time -p cmake --build . 2> ${DIR}/build_cross_aarch64_to_amd64_${round}.time
  cd .. && rm -rf build-native
  done
popd
}

ALWAYS_USE_DISK=no
BUILD_ROUNDS=3
SKIP_PREPARE=no
PREPARE_ONLY=no
BOOTSTRAP_LTO=On

function do_help() {
  echo "LLVM Build Timing Script"
  echo "  [--prepare-only]"
  echo "    just install build pre-requisites"
  echo "  [--skip-prepare]"
  echo "    do not install any pre-requisites, just build"
  echo "  [--always-use-disk]"
  echo "    do NOT attempt to create a tmpfs mount, just use an on-disk directory"
  echo "  [--build-rounds <rounds>]"
  echo "    how many times to build llvm (default: ${BUILD_ROUNDS})"
  echo "  [--bootstrap-lto <On|Off|Thin>]"
  echo "    which LTO mode to use for bootstrap comiler (default: ${BOOTSTRAP_LTO})"
  echo "  [--help]"
  echo "    this screen"
  exit 0  
}

# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --bootstrap-lto)
      BOOTSTRAP_LTO=$2
      shift
      shift
      ;;
    --build-rounds)
      BUILD_ROUNDS=$2
      shift
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY=yes
      shift
      ;;
    --skip-prepare)
      SKIP_PREPARE=yes
      shift
      ;;
    --always-use-disk)
      ALWAYS_USE_DISK=yes
      shift # past value
      ;;
    --help)
      do_help
      shift # past value
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
esac
done

if [[ ${#POSITIONAL[@]} -ne 0 ]]
then
  echo "Unknown arguments: ${POSITIONAL}"
  exit 1
fi

if [[ "${OSTYPE}" == "linux-gnu"* ]]
then
  if [[ "${SKIP_PREPARE}" == "no" ]]
  then
    linux_prepare
  fi
  if [[ "${PREPARE_ONLY}" == "yes" ]]
  then
    exit $? 
  fi

  if [[ "${ALWAYS_USE_DISK}" == "no" ]]
  then
    prepare_llvm tmpfs
  else
    prepare_llvm drive
  fi
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
  if [[ "${SKIP_PREPARE}" == "no" ]]
  then
    macos_prepare
  fi
  if [[ "${PREPARE_ONLY}" == "yes" ]]
  then
    exit $? 
  fi
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
