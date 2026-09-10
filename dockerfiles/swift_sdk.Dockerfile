# JSON-RPC server for the Hiero SDK TCK.
#
# Build context is the repository root:
#   docker build -f /path/to/action/dockerfiles/swift_sdk.Dockerfile \
#     -t hiero-sdk-swift-tck .
#
# The `protobufs` submodule is not needed: the generated Swift lives under
# Sources/HieroProtobufs/Generated and is committed. Add a .dockerignore listing
# .build/ and protobufs/ so a working clone does not ship them as build context.

FROM swift:6.0-noble AS build

WORKDIR /hiero-sdk-swift

# Resolved first and on their own layer, so editing Swift sources does not
# re-fetch the dependency graph. Package.resolved pins it, so this is exact.
#
# --scratch-path keeps SwiftPM's work out of the source tree. Without it the
# checkouts land in ./.build, and the `COPY . .` below overwrites them with
# whatever .build a working clone happens to have - discarding this layer.
COPY Package.swift Package.resolved ./
RUN swift package resolve --scratch-path /build

COPY . .

# Debug, deliberately. Sources/HieroTCK/main.swift does `@testable import Hiero`,
# which only links against a module compiled with -enable-testing: the default
# for debug builds and not for release. Upstream CI builds the same way.
RUN swift build --product HieroTCK --scratch-path /build

# Resource bundles land beside the binary, so take whatever is there.
RUN set -eux; \
    bin="$(swift build --scratch-path /build --show-bin-path)"; \
    mkdir -p /install; \
    cp "${bin}/HieroTCK" /install/; \
    cp -r "${bin}"/*.bundle /install/ 2>/dev/null || true; \
    ldd /install/HieroTCK


FROM swift:6.0-noble-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /install/ /app/

EXPOSE 8544

# main.swift hardcodes port 8544 and leaves Vapor's default 127.0.0.1 hostname.
# Passing them to the serve command instead binds every interface, so the image
# works behind a published port as well as under `--network host`, and honours
# TCK_PORT like the other SDK TCK images.
ENTRYPOINT ["/bin/sh", "-c", "exec /app/HieroTCK serve --hostname 0.0.0.0 --port \"${TCK_PORT:-8544}\""]
