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
}

@test "removes the container and, when it built one, the image" {
  run env REMOVE_IMAGE=true "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
  grep -q $'^rm\t-f\trpc\t$' "$DOCKER_ARGS_FILE"
  grep -q $'^image\trm\trpc:tag\t$' "$DOCKER_ARGS_FILE"
}

@test "leaves the image alone for a server the workflow started" {
  run env REMOVE_IMAGE=false "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
  grep -q $'^rm\t-f\trpc\t$' "$DOCKER_ARGS_FILE"
  [[ "$(grep -c $'^image\trm' "$DOCKER_ARGS_FILE" || true)" -eq 0 ]]
}

@test "dumps grouped logs only when asked" {
  run env DUMP_LOGS=true "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"::group::rpc logs"* ]]
  [[ "$output" == *"container log line"* ]]

  : > "$DOCKER_ARGS_FILE"
  run env DUMP_LOGS=false "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"::group::"* ]]
}

@test "says so rather than erroring when no container was ever created" {
  run env DUMP_LOGS=true DOCKER_PS_EMPTY=true "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"No RPC server container found"* ]]
}

# The job's pass/fail verdict moved into this script when the shell was
# extracted, so it is the only thing that still fails the run.
@test "fails the job on a non-zero TCK exit code and reports the counts" {
  run env TCK_EXIT_CODE=1 FAILED=3 HOOKS=1 SKIPPED=12 TOTAL=40 \
    "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"3 test failure(s) and 1 hook failure(s) out of 40 tests"* ]]
  [[ "$output" == *"12 further registered test(s) never ran."* ]]
}

@test "an empty exit code, from a suite that never ran, does not fail the job" {
  run env TCK_EXIT_CODE= "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
}

@test "a zero exit code passes" {
  run env TCK_EXIT_CODE=0 "$REPO_ROOT/scripts/cleanup.sh"
  [[ "$status" -eq 0 ]]
}
