#!/usr/bin/env bats
set -euo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$REPO_ROOT/tests/fixtures/docker-record-args" "$BATS_TEST_TMPDIR/bin/docker"
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  export DOCKER_ARGS_FILE="$BATS_TEST_TMPDIR/docker-args"
  export HIERO_RPC_CONTAINER=rpc
  export HIERO_RPC_IMAGE=rpc:tag
  export DOCKERFILE_PATH="$BATS_TEST_TMPDIR/Dockerfile"
  export BUILD_CONTEXT="$BATS_TEST_TMPDIR"
  touch "$DOCKERFILE_PATH"
}

@test "startServer false starts nothing and touches no docker" {
  run env START_SERVER=false "$REPO_ROOT/scripts/start-server.sh"
  [[ "$status" -eq 0 ]]
  [[ ! -e "$DOCKER_ARGS_FILE" ]]
  [[ "$output" == *"startServer is false"* ]]
}

@test "a missing Dockerfile is an error, not a silent skip" {
  run env START_SERVER=true DOCKERFILE_PATH="$BATS_TEST_TMPDIR/absent" \
    "$REPO_ROOT/scripts/start-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"::error title=Dockerfile not found::"* ]]
}

# Regression: expanding an empty array under `set -u` aborts on bash 3.2, so an
# invocation with neither serverEnv nor dockerBuildArgs has to stay valid.
@test "builds and runs with no serverEnv and no build args" {
  run env START_SERVER=true "$REPO_ROOT/scripts/start-server.sh"
  [[ "$status" -eq 0 ]]
  grep -q $'^build\t-t\trpc:tag\t-f\t' "$DOCKER_ARGS_FILE"
  # The context is the final argument, and must be BUILD_CONTEXT rather than "."
  # so a caller can keep sibling checkouts out of the image.
  grep -q "$(printf '%s\t$' "$BUILD_CONTEXT")" "$DOCKER_ARGS_FILE"
  grep -q $'^run\t-d\t--network\thost\t--name\trpc\trpc:tag\t$' "$DOCKER_ARGS_FILE"
}

@test "serverEnv lines become -e arguments, skipping blanks and comments" {
  run env START_SERVER=true \
    SERVER_ENV=$'TCK_PORT=8544\n\n# a comment\n  TCK_HOST=0.0.0.0  \nEXTRA=a=b' \
    "$REPO_ROOT/scripts/start-server.sh"
  [[ "$status" -eq 0 ]]
  local run_line
  run_line="$(grep $'^run\t' "$DOCKER_ARGS_FILE")"
  [[ "$run_line" == *$'-e\tTCK_PORT=8544'* ]]
  [[ "$run_line" == *$'-e\tTCK_HOST=0.0.0.0'* ]]
  [[ "$run_line" == *$'-e\tEXTRA=a=b'* ]]
  [[ "$run_line" != *comment* ]]
  [[ "$output" == *"Passing TCK_PORT to the server container."* ]]
}

@test "dockerBuildArgs split as a command line, keeping quoted values whole" {
  run env START_SERVER=true \
    DOCKER_BUILD_ARGS="--load --cache-to 'type=gha,mode=max'" \
    "$REPO_ROOT/scripts/start-server.sh"
  [[ "$status" -eq 0 ]]
  local build_line
  build_line="$(grep $'^build\t' "$DOCKER_ARGS_FILE")"
  [[ "$build_line" == $'build\t--load\t--cache-to\ttype=gha,mode=max\t-t\t'* ]]
}
