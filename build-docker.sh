#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -euo pipefail
set -x

mkdir -p ${DIR}/llvm

rm -rf ${DIR}/results || true
mkdir ${DIR}/results

docker=docker
if ! command -v "${docker}" &> /dev/null
then
    echo "Docker command not found. Using podman instead of Docker"
    docker=podman
fi

DOCKER_TAG=${USER}-llvm-build-image
${docker} build -t ${DOCKER_TAG} -f Dockerfile .

totalm="$(free -m | awk '/^Mem:/{print $2}')"
# Check if total RAM size is larger than 100GB
if [ $totalm -gt 100000 ]
then
    echo "RAM is large enough to use RAMDisk for LLVM Build"
    sudo umount ${DIR}/llvm || true
    sudo mount -t tmpfs \
        -o size=12G,uid=$(id -u),gid=$(id -g) \
        tmpfs \
        ${DIR}/llvm
else
    echo "Not using tmpfs because RAM is not large enough. Need more than 100GB"
fi

${docker} run --rm \
          -v ${DIR}/llvm:/llvm-build:z \
          ${DOCKER_TAG} \
          "-c" "cp -R /work/* /llvm-build; cd /llvm-build; ./build.sh --skip-prepare --always-use-disk"

cp ${DIR}/llvm/results/*.time ${DIR}/results
