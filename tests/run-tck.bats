#!/usr/bin/env bats
set -euo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$REPO_ROOT/tests/fixtures/npm-record" "$BATS_TEST_TMPDIR/bin/npm"
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  export NPM_ARGS_FILE="$BATS_TEST_TMPDIR/npm-args"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/outputs"
  export TCK_OUTPUT_LOG="$BATS_TEST_TMPDIR/tck-output.log"
}

@test "targeted arguments preserve quoted phrases and output is teed" {
  run env TEST_MATRIX="spec.ts --grep 'some phrase'" NPM_EXIT_CODE=7 \
    "$REPO_ROOT/scripts/run-tck.sh"
  [[ "$status" -eq 0 ]]
  [[ "$(cat "$NPM_ARGS_FILE")" == $'run\ntest:file\n--\nspec.ts\n--grep\nsome phrase' ]]
  [[ "$(cat "$TCK_OUTPUT_LOG")" == "mock TCK output" ]]
  [[ "$(cat "$GITHUB_OUTPUT")" == "exitCode=7" ]]
  [[ "$output" == *"mocha exited with code 7"* ]]
}
