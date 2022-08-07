FROM ubuntu:18.04
COPY sources.list.changes /etc/apt/sources.list
WORKDIR /work
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install sudo
COPY ./build.sh ./build.sh
COPY ./sources.list.changes ./sources.list.changes
RUN ./build.sh --prepare-only
COPY . .
ENTRYPOINT ["/bin/bash"]
