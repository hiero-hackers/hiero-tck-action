# JSON-RPC server for the Hiero SDK TCK.
#
# Build context is the repository root, so build it from there:
#   docker build -f tck/Dockerfile.local -t hiero-sdk-js-tck .
#
# This differs from the tck/Dockerfile already in the repository, which installs
# @hiero-ledger/sdk from npm and therefore tests the published package. This one
# builds the SDK from the checkout and installs that, so a pull request is
# tested against its own changes. It needs the repository root as its context
# for that reason - tck/Dockerfile expects the context to be tck/ itself.

# --- Stage 1: build the SDK from this checkout ----------------------------
FROM node:20-bookworm-slim AS sdk-builder

# Pinned to .github/workflows/build.yml, which is the combination upstream CI
# builds with. package.json declares no packageManager field, so corepack has
# nothing to go on and pnpm is installed explicitly.
ARG PNPM_VERSION=9.15.5
ARG TASK_VERSION=3.35.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "pnpm@${PNPM_VERSION}" "@go-task/cli@${TASK_VERSION}"

WORKDIR /sdk

COPY . .

RUN pnpm install --frozen-lockfile

# `task build` is build:prep (install, format, lint, codegen) then build:compile
# (babel, rollup). The codegen is required, so the whole task is run rather than
# just the compile half.
RUN task build

# `files` in package.json is lib/, src/, dist/, all of which now exist.
RUN pnpm pack --pack-destination /sdk-package


# --- Stage 2: the TCK server ----------------------------------------------
FROM node:20-bookworm-slim

WORKDIR /app

COPY tck/ ./
COPY --from=sdk-builder /sdk-package/*.tgz /tmp/hiero-sdk.tgz

# tck/package.json pins a released @hiero-ledger/sdk. Dropping it before the
# install is what lets the locally built tarball take its place; npm ci is not
# usable here because removing the dependency puts package.json and
# package-lock.json out of agreement.
RUN npm pkg delete "dependencies.@hiero-ledger/sdk" \
    && npm install \
    && npm install /tmp/hiero-sdk.tgz \
    && rm -f /tmp/hiero-sdk.tgz \
    && node -e "console.log('sdk resolved to', require.resolve('@hiero-ledger/sdk'))"

EXPOSE 8544

# server.ts reads its port from argv[2], defaulting to 8544, and Express binds
# every interface. Passing TCK_PORT through keeps the container configured the
# same way as the other SDK TCK images.
ENTRYPOINT ["/bin/sh", "-c", "exec npx ts-node server.ts \"${TCK_PORT:-8544}\""]
