#!/usr/bin/env bash
set -euo pipefail

# Inputs (all optional): START_SERVER=true, SDK="", DOCKERFILE_PATH="",
# SERVER_ENV="", RPC_SERVER_PORT="", GITHUB_ACTION_PATH=script parent,
# SDK_REGISTRY=<action>/dockerfiles/sdks.json, GITHUB_OUTPUT=/dev/null.
START_SERVER="${START_SERVER:-true}"
SDK="${SDK:-}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-}"
SERVER_ENV="${SERVER_ENV:-}"
RPC_SERVER_PORT="${RPC_SERVER_PORT:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
action_path="${GITHUB_ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
registry="${SDK_REGISTRY:-${action_path}/dockerfiles/sdks.json}"

if [[ -n "${OPERATOR_KEY:-}" ]]; then
  echo "::add-mask::${OPERATOR_KEY}"
fi

if [[ -n "$SDK" && -n "$DOCKERFILE_PATH" ]]; then
  echo "::error title=Conflicting server inputs::sdk '${SDK}' and dockerfilePath '${DOCKERFILE_PATH}' cannot both be set."
  exit 1
fi

preset_env=""
if [[ -n "$SDK" ]]; then
  sdk_id=$(jq -r --arg requested "$SDK" '
    to_entries[] | select(.key == $requested or (.value.aliases // [] | index($requested))) | .key
  ' "$registry")
  if [[ -z "$sdk_id" ]]; then
    valid=$(jq -r '[to_entries[] | .key, (.value.aliases // [])[]] | sort | join(", ")' "$registry")
    echo "::error title=Unknown SDK preset::Unknown sdk '${SDK}'. Valid ids and aliases: ${valid}."
    exit 1
  fi
  dockerfile=$(jq -r --arg id "$sdk_id" '.[$id].dockerfile' "$registry")
  DOCKERFILE_PATH="${action_path}/dockerfiles/${dockerfile}"
  preset_port=$(jq -r --arg id "$sdk_id" '.[$id].rpcServerPort' "$registry")
  preset_env=$(jq -r --arg id "$sdk_id" '.[$id].serverEnv | to_entries[] | "\(.key)=\(.value)"' "$registry")
  echo "Using SDK preset '${sdk_id}' (${SDK})."
  echo "Preset Dockerfile: ${DOCKERFILE_PATH}"
  if [[ -n "$RPC_SERVER_PORT" ]]; then
    echo "User rpcServerPort overrides preset value ${preset_port} with ${RPC_SERVER_PORT}."
  else
    RPC_SERVER_PORT="$preset_port"
    echo "Preset rpcServerPort: ${RPC_SERVER_PORT}."
  fi
else
  DOCKERFILE_PATH="${DOCKERFILE_PATH:-./Dockerfile}"
  RPC_SERVER_PORT="${RPC_SERVER_PORT:-8544}"
fi

# Validated before the merge, not inside it. While this loop fed the merge
# pipeline directly, its `exit 1` only left the subshell and its ::error
# annotation went down the pipe into awk, so a malformed line failed the run
# with no message explaining why.
user_env=""
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    echo "::error title=Invalid serverEnv::Expected KEY=VALUE, got '${line}'."
    exit 1
  fi
  user_env+="${line}"$'\n'
done <<< "$SERVER_ENV"
user_env="${user_env%$'\n'}"

merged_file="$(mktemp)"
trap 'rm -f "$merged_file"' EXIT
{
  printf '%s\n' "$preset_env" | awk 'NF { print "preset\t" $0 }'
  printf '%s\n' "$user_env" | awk 'NF { print "user\t" $0 }'
} | awk -F '\t' '
  {
    split($2, pair, "="); key = pair[1]
    if (!(key in seen)) { order[++count] = key; seen[key] = 1 }
    value[key] = substr($2, length(key) + 2); source[key] = $1
  }
  END {
    for (i = 1; i <= count; i++)
      print source[order[i]] "\t" order[i] "=" value[order[i]]
  }
' > "$merged_file"

resolved_env=""
while IFS=$'\t' read -r source assignment; do
  [[ -z "$assignment" ]] && continue
  key="${assignment%%=*}"
  preset_has_key=false
  while IFS= read -r preset_assignment; do
    if [[ "${preset_assignment%%=*}" == "$key" ]]; then
      preset_has_key=true
      break
    fi
  done <<< "$preset_env"
  if [[ "$source" == "user" && "$preset_has_key" == "true" ]]; then
    echo "User serverEnv overrides preset ${key}."
  elif [[ "$source" == "user" ]]; then
    echo "User serverEnv adds ${key}."
  else
    echo "Preset serverEnv supplies ${key}."
  fi
  resolved_env+="${assignment}"$'\n'
done < "$merged_file"
resolved_env="${resolved_env%$'\n'}"

if [[ "$START_SERVER" == "true" && ! -f "$DOCKERFILE_PATH" ]]; then
  echo "::error title=Dockerfile not found::No Dockerfile at '${DOCKERFILE_PATH}'. Set dockerfilePath to its location, or set startServer to false if the workflow starts the server itself."
  exit 1
fi

suffix="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${RANDOM}"

# serverEnv is caller-controlled and multi-line, so its heredoc delimiter is
# randomised and checked: a fixed one appearing as a line of the value would
# terminate the output early, letting the remainder be read as further outputs.
delimiter="HIERO_SERVER_ENV_${RANDOM}${RANDOM}${RANDOM}"
while grep -qxF "$delimiter" <<< "$resolved_env"; do
  delimiter="HIERO_SERVER_ENV_${RANDOM}${RANDOM}${RANDOM}"
done

{
  echo "dockerfilePath=${DOCKERFILE_PATH}"
  echo "rpcServerPort=${RPC_SERVER_PORT}"
  echo "container=hiero-rpc-${suffix}"
  echo "image=hiero-rpc-server:${suffix}"
  echo "serverEnv<<${delimiter}"
  printf '%s\n' "$resolved_env"
  echo "${delimiter}"
} >> "$GITHUB_OUTPUT"
