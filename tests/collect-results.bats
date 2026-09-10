#!/usr/bin/env bats
set -euo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  export CASE_DIR="$BATS_TEST_TMPDIR/case"
  mkdir -p "$CASE_DIR/mochawesome-report"
  export GITHUB_OUTPUT="$CASE_DIR/outputs"
  export GITHUB_STEP_SUMMARY="$CASE_DIR/summary.md"
  export REPORT="$CASE_DIR/mochawesome-report/mochawesome.json"
  export TCK_OUTPUT_LOG="$CASE_DIR/tck-output.log"
  export REPORT_PATH="hiero-tck/mochawesome-report"
}

run_case() {
  local scenario="$1"
  if [[ "$scenario" != "no-report" ]]; then
    cp "$REPO_ROOT/tests/fixtures/$scenario/mochawesome.json" "$REPORT"
  fi
  if [[ "$scenario" == "passing" ]]; then
    cp "$REPO_ROOT/tests/fixtures/tck-output.log" "$TCK_OUTPUT_LOG"
  fi
  run "$REPO_ROOT/scripts/collect-results.sh"
  [[ "$status" -eq 0 ]]
  diff -u "$REPO_ROOT/tests/snapshots/$scenario.outputs" "$GITHUB_OUTPUT"
  diff -u "$REPO_ROOT/tests/snapshots/$scenario.summary.md" "$GITHUB_STEP_SUMMARY"
}

@test "clean all-passing report" { run_case passing; }
@test "parallel report has counts without detail" { run_case parallel; }
@test "failed before hook reports skipped and other" { run_case hooks; }
@test "all infrastructure failures are classified" { run_case infra; }
@test "mixed genuine and infrastructure failures are classified" { run_case mixed; }
@test "missing report still emits every output" { run_case no-report; }

@test "all scenarios emit the complete declared output set" {
  local scenario
  for scenario in passing parallel hooks infra mixed no-report; do
    rm -rf "$CASE_DIR"
    mkdir -p "$CASE_DIR/mochawesome-report"
    export GITHUB_OUTPUT="$CASE_DIR/outputs"
    export GITHUB_STEP_SUMMARY="$CASE_DIR/summary.md"
    export REPORT="$CASE_DIR/mochawesome-report/mochawesome.json"
    export TCK_OUTPUT_LOG="$CASE_DIR/tck-output.log"
    [[ "$scenario" == "no-report" ]] || cp "$REPO_ROOT/tests/fixtures/$scenario/mochawesome.json" "$REPORT"
    run "$REPO_ROOT/scripts/collect-results.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(cut -d= -f1 "$GITHUB_OUTPUT")" == $'total\npassed\nfailed\npending\nhookFailures\nskipped\nregistered\ngenuineFailures\ninfraFailures\nunimplementedMethods\nreportPath' ]]
  done
}
