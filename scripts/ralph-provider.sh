#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "provider"
PROMPT="${1:-say hello and report the configured provider}"
PROVIDER="${CLAW_PROVIDER:-generic}"

note "running provider Ralph loop for provider=$PROVIDER"

provider_cycle() {
  run mix escript.build
  run ./claw_code doctor --provider "$PROVIDER"

  local probe_output
  local probe_status

  set +e
  probe_output="$(cd "$ROOT" && ./claw_code probe --provider "$PROVIDER" 2>&1)"
  probe_status=$?
  set -e

  printf '%s\n' "$probe_output" | tee -a "$LOG_FILE"

  if [[ "$probe_status" -eq 0 ]]; then
    note "probe succeeded; running live provider smoke"
    run ./claw_code chat --provider "$PROVIDER" "$PROMPT"
    return 0
  fi

  if grep -q -- "- status: missing_config" <<<"$probe_output"; then
    note "probe reported missing config; validating missing-provider path instead"

    local output
    local status

    set +e
    output="$(cd "$ROOT" && ./claw_code chat --provider "$PROVIDER" "$PROMPT" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" | tee -a "$LOG_FILE"

    if [[ "$status" -ne 1 ]]; then
      note "expected missing-provider validation to exit 1, got $status"
      return 1
    fi

    if ! grep -q "Stop reason: missing_provider_config" <<<"$output"; then
      note "expected missing-provider validation to report missing_provider_config"
      return 1
    fi

    return 0
  fi

  note "probe failed unexpectedly"
  return 1
}

run_cycles "provider gate" provider_cycle

note "provider Ralph loop complete"
note "log file: $LOG_FILE"
