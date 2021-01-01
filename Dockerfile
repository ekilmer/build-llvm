FROM ubuntu:18.04
COPY sources.list.changes /etc/apt/sources.list
WORKDIR /work
ADD . .
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install sudo
RUN ./build.sh --prepare-only
ENTRYPOINT ["/bin/bash"]
