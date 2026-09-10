#!/usr/bin/env bash
set -euo pipefail

# Inputs (optional): RPC_PORT=8544, STARTUP_TIMEOUT=120, START_SERVER=true,
# HIERO_RPC_CONTAINER="".
RPC_PORT="${RPC_PORT:-8544}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-120}"
START_SERVER="${START_SERVER:-true}"
url="http://localhost:${RPC_PORT}/"
deadline=$((SECONDS + STARTUP_TIMEOUT))

# Set once the port accepts a connection, so the timeout message can tell
# "nothing ever listened" apart from "something listened but never spoke
# JSON-RPC" - two different faults that used to produce the same error.
tcp_seen=false

# Callers establish that the container exists first. Guarding this on
# `docker ps` swallowed the logs on the crash path, where the container is
# known to exist because it was just inspected.
dump_container_logs() {
  echo "::group::${HIERO_RPC_CONTAINER} logs"
  docker logs "$HIERO_RPC_CONTAINER" 2>&1 || true
  echo "::endgroup::"
}

container_exists() {
  [[ -n "${HIERO_RPC_CONTAINER:-}" ]] || return 1
  [[ -n "$(docker ps -aq -f name="$HIERO_RPC_CONTAINER" 2>/dev/null)" ]]
}

echo "Waiting up to ${STARTUP_TIMEOUT}s for the RPC server on ${url}..."
while ((SECONDS < deadline)); do
  if [[ "$START_SERVER" == "true" ]]; then
    if [[ -z "${HIERO_RPC_CONTAINER:-}" ]] ||
      ! running=$(docker inspect -f '{{.State.Running}}' "$HIERO_RPC_CONTAINER" 2>/dev/null); then
      echo "::error title=RPC server container missing::The action started no container named '${HIERO_RPC_CONTAINER:-<unset>}'."
      exit 1
    fi
    if [[ "$running" != "true" ]]; then
      exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$HIERO_RPC_CONTAINER" 2>/dev/null || echo unknown)
      dump_container_logs
      echo "::error title=RPC server crashed::Container '${HIERO_RPC_CONTAINER}' exited with code ${exit_code} before the RPC server became ready."
      exit 1
    fi
  fi

  # A TCP connect is non-mutating and treats any listening HTTP implementation
  # as alive, so it is the cheap gate. Once the port answers, one reset confirms
  # the JSON-RPC layer itself; unlike curl --fail, a valid JSON-RPC error
  # carried by HTTP 4xx counts as ready.
  #
  # Both stages stay inside the retry loop. Accepting a connection does not mean
  # the application behind it is serving yet - plenty of servers bind before
  # they finish wiring up routes - so a reset that does not answer is a reason
  # to poll again, not to fail the run.
  if (exec 3<>"/dev/tcp/127.0.0.1/${RPC_PORT}") 2>/dev/null; then
    tcp_seen=true
    if response=$(curl --silent --max-time 10 -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"reset","params":[],"id":1}' \
      "$url" 2>/dev/null) && jq -e \
      '.jsonrpc == "2.0" and (has("result") or has("error"))' \
      >/dev/null 2>&1 <<< "$response"; then
      echo "RPC server is ready."
      exit 0
    fi
  fi
  sleep 2
done

if [[ "$tcp_seen" == "true" ]]; then
  echo "::error title=RPC layer not ready::Port ${RPC_PORT} accepted connections but ${url} never answered the reset JSON-RPC call within ${STARTUP_TIMEOUT}s."
else
  echo "::error title=RPC server not ready::No response from ${url} after ${STARTUP_TIMEOUT}s."
fi
if [[ "$START_SERVER" == "true" ]] && container_exists; then
  dump_container_logs
fi
exit 1
