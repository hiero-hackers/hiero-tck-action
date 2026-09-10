#!/usr/bin/env bash
set -euo pipefail

# Inputs (optional): TEST_MATRIX="", TEST_SCRIPT=test:ci, TCK_TAG=unknown,
# TCK_OUTPUT_LOG=tck-output.log, GITHUB_OUTPUT=/dev/null.
TEST_MATRIX="${TEST_MATRIX:-}"
TEST_SCRIPT="${TEST_SCRIPT:-test:ci}"
TCK_TAG="${TCK_TAG:-unknown}"
TCK_OUTPUT_LOG="${TCK_OUTPUT_LOG:-tck-output.log}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
args=()

if [[ -n "$TEST_MATRIX" ]]; then
  script="test:file"
  while IFS= read -r arg; do
    [[ -n "$arg" ]] && args+=("$arg")
  done < <(printf '%s' "$TEST_MATRIX" | xargs -n1 printf '%s\n')
  echo "::notice title=Targeted TCK run::Running only: ${TEST_MATRIX}"
else
  script="$TEST_SCRIPT"
  if ! node -e 'process.exit(require("./package.json").scripts?.[process.argv[1]] ? 0 : 1)' "$script"; then
    echo "::warning title=TCK script missing::'${script}' is not in this TCK tag (${TCK_TAG}); falling back to 'test'."
    script="test"
  fi
fi

echo "Running: npm run ${script} -- ${args[*]}"
set +e
if ((${#args[@]} > 0)); then
  npm run "$script" -- "${args[@]}" 2>&1 | tee "$TCK_OUTPUT_LOG"
else
  npm run "$script" 2>&1 | tee "$TCK_OUTPUT_LOG"
fi
code=${PIPESTATUS[0]}
set -e
echo "exitCode=${code}" >> "$GITHUB_OUTPUT"
if ((code != 0)); then
  echo "::warning title=TCK suite failed::mocha exited with code ${code}. See the results summary below."
fi
