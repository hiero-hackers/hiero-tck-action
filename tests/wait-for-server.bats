#!/usr/bin/env bats
set -euo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
}

use_docker_fixture() {
  cp "$REPO_ROOT/tests/fixtures/$1" "$BATS_TEST_TMPDIR/bin/docker"
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

@test "fails immediately with exit code and logs when container crashes" {
  use_docker_fixture docker-crashed
  run env START_SERVER=true HIERO_RPC_CONTAINER=rpc STARTUP_TIMEOUT=120 \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"::group::rpc logs"* ]]
  [[ "$output" == *"fatal startup error"* ]]
  [[ "$output" == *"::error title=RPC server crashed::"* ]]
  [[ "$output" == *"exited with code 17"* ]]
}

@test "reports a container that was never created" {
  use_docker_fixture docker-missing
  run env START_SERVER=true HIERO_RPC_CONTAINER=missing STARTUP_TIMEOUT=120 \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"::error title=RPC server container missing::"* ]]
}

@test "does not inspect Docker for an externally started server" {
  use_docker_fixture docker-record-call
  run env START_SERVER=false STARTUP_TIMEOUT=0 \
    DOCKER_CALLED_FILE="$BATS_TEST_TMPDIR/docker-called" \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  [[ "$status" -eq 1 ]]
  [[ ! -e "$BATS_TEST_TMPDIR/docker-called" ]]
  [[ "$output" == *"::error title=RPC server not ready::"* ]]
}

@test "accepts a JSON-RPC response over HTTP 4xx after one reset" {
  local port_file="$BATS_TEST_TMPDIR/port"
  local calls_file="$BATS_TEST_TMPDIR/calls"
  python3 "$REPO_ROOT/tests/fixtures/rpc-server.py" \
    "$port_file" "$calls_file" &
  local server_pid=$!
  while [[ ! -s "$port_file" ]]; do sleep 0.05; done
  run env START_SERVER=false RPC_PORT="$(cat "$port_file")" STARTUP_TIMEOUT=5 \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"RPC server is ready."* ]]
  [[ "$(wc -l < "$calls_file" | tr -d ' ')" -eq 1 ]]
}

# Regression: a listening socket does not mean the RPC layer is serving. The
# first implementation failed the run on the first unanswered reset, turning an
# ordinary startup race into a hard error.
@test "retries the reset while the port listens but RPC is not up yet" {
  local port_file="$BATS_TEST_TMPDIR/port"
  local calls_file="$BATS_TEST_TMPDIR/calls"
  python3 "$REPO_ROOT/tests/fixtures/rpc-server.py" \
    "$port_file" "$calls_file" 2 &
  local server_pid=$!
  while [[ ! -s "$port_file" ]]; do sleep 0.05; done
  run env START_SERVER=false RPC_PORT="$(cat "$port_file")" STARTUP_TIMEOUT=30 \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"RPC server is ready."* ]]
  [[ "$(wc -l < "$calls_file" | tr -d ' ')" -eq 3 ]]
}

@test "timing out after the port opened blames the RPC layer, not the port" {
  local port_file="$BATS_TEST_TMPDIR/port"
  local calls_file="$BATS_TEST_TMPDIR/calls"
  python3 "$REPO_ROOT/tests/fixtures/rpc-server.py" \
    "$port_file" "$calls_file" 9999 &
  local server_pid=$!
  while [[ ! -s "$port_file" ]]; do sleep 0.05; done
  run env START_SERVER=false RPC_PORT="$(cat "$port_file")" STARTUP_TIMEOUT=3 \
    "$REPO_ROOT/scripts/wait-for-server.sh"
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"::error title=RPC layer not ready::"* ]]
  [[ "$output" == *"accepted connections"* ]]
}
