#!/usr/bin/env bash
set -euo pipefail

# Inputs: START_SERVER=true, DOCKERFILE_PATH=./Dockerfile, SERVER_ENV="",
# DOCKER_BUILD_ARGS="", HIERO_RPC_CONTAINER, HIERO_RPC_IMAGE,
# BUILD_CONTEXT=.
START_SERVER="${START_SERVER:-true}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-./Dockerfile}"
SERVER_ENV="${SERVER_ENV:-}"
DOCKER_BUILD_ARGS="${DOCKER_BUILD_ARGS:-}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"

if [[ "$START_SERVER" != "true" ]]; then
  echo "startServer is false - expecting the workflow to have started a server already."
  exit 0
fi

: "${HIERO_RPC_CONTAINER:?HIERO_RPC_CONTAINER must be set}"
: "${HIERO_RPC_IMAGE:?HIERO_RPC_IMAGE must be set}"

if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "::error title=Dockerfile not found::No Dockerfile at '${DOCKERFILE_PATH}'."
  exit 1
fi

env_args=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue
  env_args+=(-e "$line")
  echo "Passing ${line%%=*} to the server container."
done <<< "$SERVER_ENV"

build_args=()
if [[ -n "$DOCKER_BUILD_ARGS" ]]; then
  while IFS= read -r arg; do
    [[ -n "$arg" ]] && build_args+=("$arg")
  done < <(printf '%s' "$DOCKER_BUILD_ARGS" | xargs -n1 printf '%s\n')
  echo "Extra docker build arguments: ${build_args[*]}"
fi

echo "Building server image from ${DOCKERFILE_PATH}..."
# ${arr[@]+"${arr[@]}"} rather than "${arr[@]}": expanding an empty array under
# `set -u` aborts on bash 3.2, which is what a macOS workstation runs. Runners
# have bash 5 and would not notice, but the scripts are meant to be runnable
# outside Actions.
docker build ${build_args[@]+"${build_args[@]}"} \
  -t "$HIERO_RPC_IMAGE" -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT"
docker run -d --network host --name "$HIERO_RPC_CONTAINER" \
  ${env_args[@]+"${env_args[@]}"} "$HIERO_RPC_IMAGE"
