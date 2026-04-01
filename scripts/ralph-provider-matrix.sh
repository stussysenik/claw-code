#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "provider-matrix"
PROMPT="${1:-say hello and report the configured provider}"
PROVIDER_MATRIX="${CLAW_PROVIDER_MATRIX:-generic,glm,kimi,nim}"

IFS=',' read -r -a RAW_PROVIDERS <<<"$PROVIDER_MATRIX"
PROVIDERS=()

for provider in "${RAW_PROVIDERS[@]}"; do
  provider="${provider//[[:space:]]/}"

  if [[ -n "$provider" ]]; then
    PROVIDERS+=("$provider")
  fi
done

note "running provider-matrix Ralph loop for providers=${PROVIDERS[*]}"

validate_provider_probe() {
  local provider="$1"
  local probe_output
  local probe_status

  run ./claw_code doctor --provider "$provider"

  set +e
  probe_output="$(cd "$ROOT" && ./claw_code probe --provider "$provider" 2>&1)"
  probe_status=$?
  set -e

  printf '%s\n' "$probe_output" | tee -a "$LOG_FILE"

  if [[ "$probe_status" -eq 0 ]]; then
    note "probe succeeded for provider=$provider; running chat smoke"
    run ./claw_code chat --provider "$provider" "$PROMPT"
    return 0
  fi

  if grep -q -- "- status: missing_config" <<<"$probe_output"; then
    note "probe reported missing config for provider=$provider; validating missing-provider path"

    local output
    local status

    set +e
    output="$(cd "$ROOT" && ./claw_code chat --provider "$provider" "$PROMPT" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" | tee -a "$LOG_FILE"

    if [[ "$status" -ne 1 ]]; then
      note "expected missing-provider validation to exit 1 for provider=$provider, got $status"
      return 1
    fi

    if ! grep -q "Stop reason: missing_provider_config" <<<"$output"; then
      note "expected missing-provider validation to report missing_provider_config for provider=$provider"
      return 1
    fi

    return 0
  fi

  note "probe failed unexpectedly for provider=$provider"
  return 1
}

provider_matrix_cycle() {
  run mix escript.build
  run ./claw_code providers

  for provider in "${PROVIDERS[@]}"; do
    note "checking provider=$provider"
    validate_provider_probe "$provider"
  done
}

run_cycles "provider matrix gate" provider_matrix_cycle

note "provider-matrix Ralph loop complete"
note "log file: $LOG_FILE"
