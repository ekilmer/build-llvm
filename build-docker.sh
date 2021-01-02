#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set -euo pipefail
set -x


DOCKER_TAG=${USER}-llvm-build-image
docker build -t ${DOCKER_TAG} -f Dockerfile .

rm -rf ${DIR}/results || true
mkdir ${DIR}/results

sudo umount ${DIR}/llvm || true
sudo mount -t tmpfs \
    -o size=12G,uid=$(id -u),gid=$(id -g) \
    tmpfs \
    ${DIR}/llvm

docker run --rm \
          -v ${DIR}/llvm:/llvm-build \
          ${DOCKER_TAG} \
          "-c" "cp -R /work/* /llvm-build; cd /llvm-build; ./build.sh --skip-prepare --always-use-disk"

cp ${DIR}/llvm/results/*.time ${DIR}/results
