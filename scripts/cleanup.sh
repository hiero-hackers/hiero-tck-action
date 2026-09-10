#!/usr/bin/env bash
set -euo pipefail

# Inputs (optional): HIERO_RPC_CONTAINER="", HIERO_RPC_IMAGE="",
# DUMP_LOGS=false, REMOVE_IMAGE=false, TCK_EXIT_CODE=0 and result counts.
container="${HIERO_RPC_CONTAINER:-}"
image="${HIERO_RPC_IMAGE:-}"

if [[ "${DUMP_LOGS:-false}" == "true" ]]; then
  if [[ -n "$container" ]] && [[ -n "$(docker ps -aq -f name="$container")" ]]; then
    echo "::group::${container} logs"
    docker logs "$container" 2>&1 || true
    echo "::endgroup::"
  else
    echo "No RPC server container found - nothing to dump."
  fi
fi

if [[ -n "$container" ]] && [[ -n "$(docker ps -aq -f name="$container")" ]]; then
  echo "Stopping and removing ${container}..."
  docker rm -f "$container" || true
fi
if [[ "${REMOVE_IMAGE:-false}" == "true" && -n "$image" ]]; then
  docker image rm "$image" >/dev/null 2>&1 || true
fi

if [[ "${TCK_EXIT_CODE:-0}" != "0" ]]; then
  echo "TCK suite failed: ${FAILED:-0} test failure(s) and ${HOOKS:-0} hook failure(s) out of ${TOTAL:-0} tests."
  if (( ${SKIPPED:-0} > 0 )); then
    echo "${SKIPPED} further registered test(s) never ran."
  fi
  exit 1
fi
