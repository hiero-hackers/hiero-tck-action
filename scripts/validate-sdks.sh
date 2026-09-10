#!/usr/bin/env bash
set -euo pipefail

# Inputs (optional): SDK_REGISTRY=dockerfiles/sdks.json, README_PATH=README.md.
registry="${SDK_REGISTRY:-dockerfiles/sdks.json}"
readme="${README_PATH:-README.md}"
expected_files="$(mktemp)"
actual_files="$(mktemp)"
expected_table="$(mktemp)"
actual_table="$(mktemp)"
trap 'rm -f "$expected_files" "$actual_files" "$expected_table" "$actual_table"' EXIT

jq -r 'to_entries[].value.dockerfile' "$registry" | sort > "$expected_files"
find dockerfiles -maxdepth 1 -name '*_sdk.Dockerfile' -exec basename {} \; | sort > "$actual_files"
diff -u "$expected_files" "$actual_files"

scripts/generate-sdk-table.sh > "$expected_table"
sed -n '/<!-- sdk-table:start -->/,/<!-- sdk-table:end -->/p' "$readme" |
  sed '1d;$d' > "$actual_table"
diff -u "$expected_table" "$actual_table"
