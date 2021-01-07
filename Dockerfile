FROM ubuntu:18.04
COPY sources.list.changes /etc/apt/sources.list
WORKDIR /work
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install sudo
ADD . .
RUN ./build.sh --prepare-only
ENTRYPOINT ["/bin/bash"]
