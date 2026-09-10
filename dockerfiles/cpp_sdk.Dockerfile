# JSON-RPC server for the Hiero SDK TCK.
#
# Build context is the repository root:
#   docker build -f src/tck/Dockerfile -t hiero-sdk-cpp-tck .
#
# The expensive layers are ordered above `COPY . .` and keyed on the two files
# that actually pin them, vcpkg.json and HieroApi.cmake, so a source-only change
# reuses the third-party build instead of repeating it.

FROM ubuntu:24.04 AS build

# Ninja's default of N+2 outruns memory on 4-core runners once it reaches the
# generated protobuf translation units, so the job count is capped.
ARG BUILD_JOBS=3
# Set by BuildKit; the fallback keeps the classic builder working.
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# perl builds vcpkg's openssl; zip and linux-libc-dev are both asserted by
# SystemLibraries.cmake; autoconf/automake/libtool build secp256k1 and apr.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    ninja-build \
    pkg-config \
    git \
    curl \
    zip \
    unzip \
    tar \
    autoconf \
    automake \
    libtool \
    linux-libc-dev \
    perl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH:-amd64}" in \
      amd64) echo x64-linux ;; \
      arm64) echo arm64-linux ;; \
      *) echo "unsupported TARGETARCH '${TARGETARCH}'" >&2; exit 1 ;; \
    esac > /vcpkg-triplet

# --- vcpkg toolchain -------------------------------------------------------
# Kept outside the source tree so `COPY . .` cannot overwrite the bootstrapped
# binary. The commit comes from the manifest's own baseline rather than the
# submodule, so this layer is keyed by exactly the file that determines it.
COPY vcpkg.json /manifest/vcpkg.json
RUN set -eux; \
    ref="$(sed -n 's/.*"builtin-baseline"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' /manifest/vcpkg.json)"; \
    test -n "$ref"; \
    git clone --filter=blob:none https://github.com/microsoft/vcpkg.git /opt/vcpkg; \
    git -C /opt/vcpkg checkout --detach "$ref"; \
    /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics

# --- third-party dependencies ---------------------------------------------
# Installed here rather than by CMake's manifest mode so the result is a layer
# that survives source changes. VCPKG_MANIFEST_INSTALL=OFF below stops CMake
# from repeating the work.
RUN /opt/vcpkg/vcpkg install \
      --x-manifest-root=/manifest \
      --triplet "$(cat /vcpkg-triplet)" \
      --host-triplet "$(cat /vcpkg-triplet)" \
      --x-install-root=/opt/vcpkg_installed \
      --clean-after-build

# --- HAPI protobufs --------------------------------------------------------
# HieroApi.cmake fetches these with a full clone of hiero-consensus-node, a
# ~630MB repository. Shallow-cloning the one tag it wants and handing the result
# to FetchContent skips both the download and its re-verification.
COPY HieroApi.cmake /manifest/HieroApi.cmake
RUN set -eux; \
    tag="$(sed -n 's/^set(HAPI_VERSION_TAG "\([^"]*\)".*/\1/p' /manifest/HieroApi.cmake | head -1)"; \
    test -n "$tag"; \
    git clone --depth 1 --branch "$tag" \
      https://github.com/hiero-ledger/hiero-consensus-node.git /opt/hapi

# --- the SDK itself --------------------------------------------------------
WORKDIR /hiero-sdk-cpp
COPY . .

# Configured explicitly rather than through CMakePresets: the presets only cover
# linux-x64, and this reproduces linux-x64-release for whichever architecture is
# being built. BUILD_TCK is off by default, and without it there is no server.
RUN cmake -S . -B build -G "Ninja Multi-Config" \
      -DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake \
      -DVCPKG_TARGET_TRIPLET="$(cat /vcpkg-triplet)" \
      -DVCPKG_INSTALLED_DIR=/opt/vcpkg_installed \
      -DVCPKG_MANIFEST_INSTALL=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TCK=ON \
      -DFETCHCONTENT_SOURCE_DIR_HPROTO=/opt/hapi

RUN cmake --build build --config Release -j "${BUILD_JOBS}"
RUN cmake --install build --config Release --prefix /install --strip

# Fails here rather than at container start if the layout moved, and records the
# runtime libraries the final stage has to provide.
RUN test -x /install/tck/hiero-sdk-cpp-tck && ldd /install/tck/hiero-sdk-cpp-tck


FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    libatomic1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /install/tck/ /app/tck/

EXPOSE 8544

# The server takes its port as argv[1], not from the environment. The wrapper
# maps TCK_PORT onto it so the container is configured the same way as the other
# SDK TCK images.
ENTRYPOINT ["/bin/sh", "-c", "exec /app/tck/hiero-sdk-cpp-tck \"${TCK_PORT:-8544}\""]
