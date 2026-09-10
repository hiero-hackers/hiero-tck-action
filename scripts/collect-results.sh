#!/usr/bin/env bash
set -euo pipefail

# Inputs (optional): REPORT=mochawesome-report/mochawesome.json,
# TCK_OUTPUT_LOG=tck-output.log, REPORT_PATH=hiero-tck/mochawesome-report,
# GITHUB_OUTPUT=/dev/null, GITHUB_STEP_SUMMARY=/dev/null.
REPORT="${REPORT:-mochawesome-report/mochawesome.json}"
TCK_OUTPUT_LOG="${TCK_OUTPUT_LOG:-tck-output.log}"
REPORT_PATH="${REPORT_PATH:-hiero-tck/mochawesome-report}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

emit_outputs() {
  {
    echo "total=${total}"
    echo "passed=${passed}"
    echo "failed=${failed}"
    echo "pending=${pending}"
    echo "hookFailures=${other}"
    echo "skipped=${skipped}"
    echo "registered=${registered}"
    echo "genuineFailures=${genuine}"
    echo "infraFailures=${infra}"
    echo "unimplementedMethods=${unimplemented_csv}"
    echo "reportPath=${report_path}"
  } >> "$GITHUB_OUTPUT"
}

if [[ ! -f "$REPORT" ]]; then
  echo "::error title=No TCK report::Expected ${REPORT} but the suite produced none. It did not run to completion."
  total=0 passed=0 failed=0 pending=0 other=0 skipped=0 registered=0
  genuine=0 infra=0 unimplemented_csv="" report_path=""
  emit_outputs
  {
    echo "### Hiero TCK Results"
    echo
    echo "No report was produced - the suite did not run to completion."
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

read -r total passed failed pending other skipped registered duration < <(
  jq -r '.stats | [
    (.tests // 0), (.passes // 0), (.failures // 0), (.pending // 0),
    (.other // 0), (.skipped // 0), (.testsRegistered // 0),
    ((.duration // 0) / 1000 | floor)
  ] | @tsv' "$REPORT"
)
all_failures=$((failed + other))
groups_file="$(mktemp)"
trap 'rm -f "$groups_file"' EXIT
jq '
  def clean: (.err.message // "unknown")
    | gsub("\n"; " ") | gsub(" +at .*"; "") | .[0:110];
  def kind: if test("Internal error|unhealthy") then "server"
            elif test("Hiero error") then "network"
            elif test("^TypeError") then "harness"
            else "test" end;
  [ .. | objects | select(.fail? == true)
    | { title: (.fullTitle // "<untitled>"), cause: clean } ]
  | map(. + {kind: (.cause | kind)})
  | group_by(.cause) | sort_by(-length)
' "$REPORT" > "$groups_file"

detail=$(jq -r '[.[] | length] | add // 0' "$groups_file")
genuine=$(jq -r '[.[] | select(.[0].kind == "test") | length] | add // 0' "$groups_file")
infra=$(jq -r '[.[] | select(.[0].kind != "test") | length] | add // 0' "$groups_file")
unimplemented=""
if [[ -f "$TCK_OUTPUT_LOG" ]]; then
  unimplemented=$(grep -oE "Method [A-Za-z0-9_]+ not found" "$TCK_OUTPUT_LOG" 2>/dev/null |
    sed 's/^Method //; s/ not found$//' | sort -u || true)
fi
unimplemented_count=$(printf '%s' "$unimplemented" | grep -c . || true)
unimplemented_csv=$(printf '%s' "$unimplemented" | tr '\n' ',' | sed 's/,$//')
report_path="$REPORT_PATH"
emit_outputs

{
  echo "### Hiero TCK Results"
  echo
  echo "| Total | Passed | Failed | Pending | Hook failures | Skipped | Duration |"
  echo "| ----: | -----: | -----: | ------: | ------------: | ------: | -------: |"
  echo "| ${total} | ${passed} | ${failed} | ${pending} | ${other} | ${skipped} | $((duration / 60))m $((duration % 60))s |"
} >> "$GITHUB_STEP_SUMMARY"

if ((detail > 0 && infra > 0 && genuine == 0)); then
  {
    echo
    echo "> [!CAUTION]"
    echo "> All ${infra} failures are server or network errors, not SDK incompatibilities."
    echo "> **This run is not a valid compatibility measurement.** The network or the server"
    echo "> under test became unhealthy. Re-run over fewer tests per network - see testMatrix."
  } >> "$GITHUB_STEP_SUMMARY"
elif ((infra > 0)); then
  {
    echo
    echo "> [!WARNING]"
    echo "> ${infra} of ${detail} failures are server or network errors rather than SDK"
    echo "> incompatibilities. Genuine test failures: **${genuine}**."
  } >> "$GITHUB_STEP_SUMMARY"
fi

if ((skipped > 0)); then
  {
    echo
    echo "> [!WARNING]"
    echo "> ${other} suite hook(s) failed, so ${skipped} of ${registered} registered tests never ran."
    echo "> Those tests are counted as neither passed nor failed."
  } >> "$GITHUB_STEP_SUMMARY"
elif ((other > 0)); then
  {
    echo
    echo "> [!WARNING]"
    echo "> ${other} suite hook(s) failed. Hook failures are counted separately from test failures."
  } >> "$GITHUB_STEP_SUMMARY"
fi

if ((unimplemented_count > 0)); then
  {
    echo
    echo "**Not implemented by this SDK (${unimplemented_count})** - reported as pending, not failed."
    echo
    printf '%s\n' "$unimplemented" | awk '{ print "- `" $0 "`" }'
  } >> "$GITHUB_STEP_SUMMARY"
fi

if ((detail > 0)); then
  {
    echo
    echo "**Failures by cause**"
    echo
    echo "| Count | Cause | Kind |"
    echo "| ----: | ----- | ---- |"
    jq -r '.[] | "| \(length) | `\(.[0].cause)` | \(.[0].kind) |"' "$groups_file"
    echo
    echo "<details><summary>Failing tests (${detail})</summary>"
    echo
    jq -r '.[]
      | "##### \(.[0].kind) - \(.[0].cause) (\(length))", "",
        (.[0:40][] | "- \(.title)"),
        (if length > 40 then "- _...and \(length - 40) more_" else empty end),
        ""' "$groups_file"
    echo "</details>"
  } >> "$GITHUB_STEP_SUMMARY"
elif ((all_failures > 0)); then
  {
    echo
    echo "> [!NOTE]"
    echo "> The report carries no per-test detail, so the ${all_failures} failures cannot be"
    echo "> classified and the HTML report will be empty. mochawesome does not populate"
    echo "> results under mocha's parallel mode - re-run with testScript: test:serial to see which tests failed."
  } >> "$GITHUB_STEP_SUMMARY"
fi
