FROM rust:latest

# set CROSS_CONTAINER_IN_CONTAINER to inform `cross` that it is executed from within a container
ENV CROSS_CONTAINER_IN_CONTAINER=true

RUN apt-get update
RUN apt-get install -y libfuse3-3 libfuse3-dev libfuse2 libfuse-dev clang
# install `cross`
RUN curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain nightly -y
RUN rustup update
RUN rustup component add rust-src
RUN cargo install --force --git https://github.com/cross-rs/cross cross
RUN cargo install xh wasm-bindgen-cli redoxer trunk wasm-opt cargo-xwin rust-script

RUN curl -fsSL https://get.docker.com | sh
