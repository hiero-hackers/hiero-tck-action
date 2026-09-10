FROM rust:1.98.1-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        pkg-config \
        libssl-dev \
        protobuf-compiler \
        libprotobuf-dev && \
    rm -rf /var/lib/apt/lists/*


COPY . .

RUN git submodule update --init --recursive
RUN cargo build --release --package hiero-sdk-tck


FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/hiero-sdk-tck /usr/local/bin/hiero-sdk-tck

EXPOSE 8544

ENTRYPOINT ["hiero-sdk-tck"]
