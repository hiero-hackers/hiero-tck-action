#!/usr/bin/env bats
set -euo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  export GITHUB_ACTION_PATH="$REPO_ROOT"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/outputs"
  export GITHUB_RUN_ID=42
  export GITHUB_RUN_ATTEMPT=2
}

@test "sdk alias resolves a bundled Dockerfile" {
  run env SDK=js START_SERVER=true "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 0 ]]
  grep -F "dockerfilePath=$REPO_ROOT/dockerfiles/js_sdk.Dockerfile" "$GITHUB_OUTPUT"
  grep -F "rpcServerPort=8544" "$GITHUB_OUTPUT"
}

@test "sdk and dockerfilePath conflict names both values" {
  run env SDK=python DOCKERFILE_PATH=custom.Dockerfile \
    "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"sdk 'python' and dockerfilePath 'custom.Dockerfile'"* ]]
}

@test "unknown sdk lists ids and aliases" {
  run env SDK=fortran "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Unknown sdk 'fortran'"* ]]
  [[ "$output" == *"cpp"* ]]
  [[ "$output" == *"py"* ]]
  [[ "$output" == *"swift"* ]]
}

@test "user environment and port override preset values" {
  run env SDK=python RPC_SERVER_PORT=9555 \
    SERVER_ENV=$'TCK_PORT=9555\nEXTRA=value=with=equals' \
    "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"User rpcServerPort overrides preset value 8544 with 9555."* ]]
  [[ "$output" == *"User serverEnv overrides preset TCK_PORT."* ]]
  [[ "$output" == *"User serverEnv adds EXTRA."* ]]
  grep -F "rpcServerPort=9555" "$GITHUB_OUTPUT"
  grep -F "TCK_HOST=0.0.0.0" "$GITHUB_OUTPUT"
  grep -F "TCK_PORT=9555" "$GITHUB_OUTPUT"
  grep -F "EXTRA=value=with=equals" "$GITHUB_OUTPUT"
  [[ "$(grep -c '^TCK_PORT=' "$GITHUB_OUTPUT")" -eq 1 ]]
}

@test "legacy fallback remains ./Dockerfile and port 8544" {
  touch "$BATS_TEST_TMPDIR/Dockerfile"
  cd "$BATS_TEST_TMPDIR"
  run env -u SDK -u DOCKERFILE_PATH -u RPC_SERVER_PORT \
    START_SERVER=true GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 0 ]]
  grep -F "dockerfilePath=./Dockerfile" "$GITHUB_OUTPUT"
  grep -F "rpcServerPort=8544" "$GITHUB_OUTPUT"
}

# The KEY=VALUE guard is what stops a caller's serverEnv from injecting extra
# lines into $GITHUB_OUTPUT; the randomised heredoc delimiter is a second layer
# behind it.
@test "a serverEnv line that is not KEY=VALUE is rejected" {
  run env SDK=python SERVER_ENV=$'TCK_PORT=8544\nHIERO_SERVER_ENV' \
    "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"::error title=Invalid serverEnv::"* ]]
  [[ "$output" == *"HIERO_SERVER_ENV"* ]]
}

@test "serverEnv survives the output heredoc intact" {
  # shellcheck disable=SC2016  # the literal $d is the point: shell metacharacters
  # in a serverEnv value must reach the container unexpanded and unmangled.
  run env SDK=python SERVER_ENV='ODD=a b "c" $d' \
    "$REPO_ROOT/scripts/resolve-server.sh"
  [[ "$status" -eq 0 ]]
  # Re-read the value the way Actions would: between the delimiter markers.
  local delim
  delim="$(sed -n 's/^serverEnv<<//p' "$GITHUB_OUTPUT")"
  [[ -n "$delim" ]]
  [[ "$(sed -n "/^serverEnv<<${delim}$/,/^${delim}$/p" "$GITHUB_OUTPUT" | sed '1d;$d' | grep -c '^ODD=')" -eq 1 ]]
  # shellcheck disable=SC2016  # matching the same literal, unexpanded.
  grep -qxF 'ODD=a b "c" $d' "$GITHUB_OUTPUT"
}
