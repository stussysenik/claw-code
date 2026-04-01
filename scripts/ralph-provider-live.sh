#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "provider-live"
PROMPT="${1:-say hello and report the configured provider}"
PROVIDER_LIVE="${CLAW_PROVIDER_LIVE:-glm,nim,generic}"

IFS=',' read -r -a RAW_PROVIDERS <<<"$PROVIDER_LIVE"
PROVIDERS=()

for provider in "${RAW_PROVIDERS[@]}"; do
  provider="${provider//[[:space:]]/}"

  if [[ -n "$provider" ]]; then
    PROVIDERS+=("$provider")
  fi
done

note "running provider-live Ralph loop for providers=${PROVIDERS[*]}"

generic_base_url() {
  printf '%s' "${CLAW_GENERIC_LIVE_BASE_URL:-${CLAW_BASE_URL:-}}"
}

generic_model() {
  printf '%s' "${CLAW_GENERIC_LIVE_MODEL:-${CLAW_MODEL:-}}"
}

generic_api_key() {
  printf '%s' "${CLAW_GENERIC_LIVE_API_KEY:-${CLAW_API_KEY:-}}"
}

generic_api_key_header() {
  printf '%s' "${CLAW_GENERIC_LIVE_API_KEY_HEADER:-${CLAW_API_KEY_HEADER:-authorization}}"
}

validate_generic_live_config() {
  local base_url
  local model

  base_url="$(generic_base_url)"
  model="$(generic_model)"

  if [[ -z "$base_url" || -z "$model" ]]; then
    note "generic live proof requires CLAW_GENERIC_LIVE_BASE_URL or CLAW_BASE_URL plus CLAW_GENERIC_LIVE_MODEL or CLAW_MODEL"
    return 1
  fi
}

run_generic_live() {
  local command="$1"
  shift

  local base_url
  local model
  local api_key
  local api_key_header

  validate_generic_live_config

  base_url="$(generic_base_url)"
  model="$(generic_model)"
  api_key="$(generic_api_key)"
  api_key_header="$(generic_api_key_header)"

  note "+ generic live $command --provider generic --base-url $base_url --model $model --api-key-header $api_key_header"

  (
    cd "$ROOT"
    export CLAW_PROVIDER="generic"
    export CLAW_BASE_URL="$base_url"
    export CLAW_MODEL="$model"
    export CLAW_API_KEY_HEADER="$api_key_header"

    if [[ -n "$api_key" ]]; then
      export CLAW_API_KEY="$api_key"
    else
      unset CLAW_API_KEY
    fi

    ./claw_code "$command" --provider generic "$@"
  ) 2>&1 | tee -a "$LOG_FILE"
}

provider_live_cycle() {
  run mix escript.build

  for provider in "${PROVIDERS[@]}"; do
    note "checking live provider=$provider"

    if [[ "$provider" == "generic" ]]; then
      run_generic_live doctor
      run_generic_live probe "$PROMPT"
      run_generic_live chat "$PROMPT"
      continue
    fi

    run ./claw_code doctor --provider "$provider"
    run ./claw_code probe --provider "$provider" "$PROMPT"
    run ./claw_code chat --provider "$provider" "$PROMPT"
  done
}

run_cycles "provider live gate" provider_live_cycle

note "provider-live Ralph loop complete"
note "log file: $LOG_FILE"
