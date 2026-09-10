#!/usr/bin/env bash
set -euo pipefail

# Input (optional): SDK_REGISTRY=dockerfiles/sdks.json.
registry="${SDK_REGISTRY:-dockerfiles/sdks.json}"
echo '| ID | SDK | Aliases | Upstream | Expected build |'
echo '| -- | --- | ------- | -------- | -------------: |'
jq -r 'to_entries[] | [
  ("`" + .key + "`"),
  .value.name,
  ((.value.aliases // []) | map("`" + . + "`") | join(", ")),
  ("[" + .value.repo + "](https://github.com/" + .value.repo + ")"),
  ((.value.expectedBuildMinutes | tostring) + " min")
] | "| " + join(" | ") + " |"' "$registry"
