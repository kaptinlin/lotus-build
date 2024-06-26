### Based on ldoublewood <ldoublewood@gmail.com> original Dockerfile, with 
### extra additions.
FROM golang:1.21.7-bullseye AS lotus-builder
MAINTAINER textile <contact@textile.io>

ENV SRC_DIR /lotus


# RUN sed -i 's#http://deb.debian.org#https://mirrors.163.com#g' /etc/apt/sources.list \
#    && sed -i 's#http://security.debian.org#https://mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list \
#RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
#RUN sed -i 's/http:/https:/g' /etc/apt/sources.list
RUN apt-get update && apt-get install -y ca-certificates build-essential clang llvm libclang-dev mesa-opencl-icd ocl-icd-libopencl1 ocl-icd-opencl-dev jq hwloc libhwloc-dev 

ARG RUST_VERSION=1.63.0
# ENV RUSTUP_DIST_SERVER=https://rsproxy.cn
# ENV RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

#RUN curl -sSf https://rsproxy.cn/rustup-init.sh | sh -s -- -y
# RUN curl -sSf https://sh.rustup.rs | sh -s -- -y

RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
        amd64) rustArch='x86_64-unknown-linux-gnu' ;; \
        arm64) rustArch='aarch64-unknown-linux-gnu' ;; \
        *) echo >&2 "unsupported architecture: ${dpkgArch}"; exit 1 ;; \
    esac; \
    url="https://static.rust-lang.org/rustup/archive/1.25.1/${rustArch}/rustup-init"; \
    wget "$url"; \
    chmod +x rustup-init; \
    ./rustup-init -y --no-modify-path --profile minimal --default-toolchain $RUST_VERSION --default-host ${rustArch}; \
    rm rustup-init; \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME; \
    rustup --version; \
    cargo --version; \
    rustc --version;


# Get su-exec, a very minimal tool for dropping privileges,
# and tini, a very minimal init daemon for containers
ENV SUEXEC_VERSION v0.2
ENV TINI_VERSION v0.18.0
RUN set -x \
  && cd /tmp \
  && git clone https://github.com/ncopa/su-exec.git \
  && cd su-exec \
  && git checkout -q $SUEXEC_VERSION \
  && make \
  && cd /tmp \
  && wget -q -O tini https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini \
  && chmod +x tini

# Download packages first so they can be cached.
COPY lotus/go.mod lotus/go.sum $SRC_DIR/
COPY lotus/extern/ $SRC_DIR/extern/

# ARG GO111MODULE=on
# ARG GODEBUG=x509ignoreCN=0
# ARG GOPROXY=https://goproxy.cn,direct
RUN cd $SRC_DIR \
  && go mod download

COPY lotus/Makefile $SRC_DIR

# Because extern/filecoin-ffi building script need to get version number from git
COPY lotus/.git/ $SRC_DIR/.git/
COPY lotus/.gitmodules $SRC_DIR/

#RUN echo '[source.crates-io]' > ~/.cargo/config \
#  && echo 'registry = "https://github.com/rust-lang/crates.io-index"'  >> ~/.cargo/config \
#  && echo "replace-with = 'sjtu'"  >> ~/.cargo/config \
#  && echo '[source.sjtu]'   >> ~/.cargo/config \
#  && echo 'registry = "https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index"'  >> ~/.cargo/config \
#  && echo '' >> ~/.cargo/config

# Download dependence first
RUN cd $SRC_DIR \
  && mkdir $SRC_DIR/build \
  # && . $HOME/.cargo/env \
  && make clean \
  && FFI_BUILD_FROM_SOURCE=1 RUSTFLAGS="-C target-cpu=native -g" CGO_CFLAGS="-D__BLST_PORTABLE__" make deps

COPY lotus/ $SRC_DIR

ARG MAKE_TARGET=lotus

# Build the thing.
RUN cd $SRC_DIR \
  # && . $HOME/.cargo/env \
  && FFI_BUILD_FROM_SOURCE=1 RUSTFLAGS="-C target-cpu=native -g" CGO_CFLAGS="-D__BLST_PORTABLE__" make $MAKE_TARGET

# Build the thing.
RUN cd $SRC_DIR \
  # && . $HOME/.cargo/env \
  && FFI_BUILD_FROM_SOURCE=1 RUSTFLAGS="-C target-cpu=native -g" CGO_CFLAGS="-D__BLST_PORTABLE__" make lotus-shed

# Now comes the actual target image, which aims to be as small as possible.
FROM ubuntu:20.04 AS lotus-base

# Get the executable binary and TLS CAs from the build container.
ENV SRC_DIR /lotus
COPY --from=0 $SRC_DIR/lotus /usr/local/bin/lotus
COPY --from=0 $SRC_DIR/lotus-shed /usr/local/bin/lotus-shed
COPY --from=0 /tmp/su-exec/su-exec /sbin/su-exec
COPY --from=0 /tmp/tini /sbin/tini

# Base resources
COPY --from=0 /etc/ssl/certs                           /etc/ssl/certs
COPY --from=0 /lib/*/libdl.so.2         /lib/
COPY --from=0 /lib/*/librt.so.1         /lib/
COPY --from=0 /lib/*/libgcc_s.so.1      /lib/
COPY --from=0 /lib/*/libutil.so.1       /lib/
COPY --from=0 /usr/lib/*/libltdl.so.7   /lib/
COPY --from=0 /usr/lib/*/libnuma.so.1   /lib/
COPY --from=0 /usr/lib/*/libhwloc.so.*  /lib/
COPY --from=0 /usr/lib/*/libOpenCL.so.1 /lib/

# WS port
EXPOSE 1235
# P2P port
EXPOSE 5678

# Create the home directory and switch to a non-privileged user.
ENV HOME_PATH /data
ENV PARAMCACHE_PATH /var/tmp/filecoin-proof-parameters

RUN groupadd -f users


RUN mkdir -p $HOME_PATH $PARAMCACHE_PATH \
  && adduser --uid 1000 --ingroup users --home $HOME_PATH --disabled-password --gecos "" lotus \
  && chown -R lotus:users $HOME_PATH $PARAMCACHE_PATH

VOLUME $HOME_PATH
VOLUME $PARAMCACHE_PATH

USER lotus

# Execute the daemon subcommand by default
CMD ["/sbin/tini", "--", "lotus", "daemon"]
