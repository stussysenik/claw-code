#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

loop_init() {
  local name="$1"
  export LOOP_NAME="$name"
  export LOG_DIR="$ROOT/.omx/logs/$name"
  export LOG_FILE="$LOG_DIR/$TIMESTAMP.log"
  mkdir -p "$LOG_DIR"
}

note() {
  printf '%s %s\n' "[info]" "$*" | tee -a "$LOG_FILE"
}

run() {
  note "+ $*"
  (
    cd "$ROOT"
    "$@"
  ) 2>&1 | tee -a "$LOG_FILE"
}

require_env_any() {
  local label="$1"
  shift

  for var_name in "$@"; do
    if [[ -n "${!var_name:-}" ]]; then
      return 0
    fi
  done

  note "missing environment for $label. expected one of: $*"
  return 1
}

cycle_count() {
  echo "${RALPH_MAX_CYCLES:-1}"
}

sleep_seconds() {
  echo "${RALPH_SLEEP_SECONDS:-0}"
}

run_cycles() {
  local label="$1"
  shift

  local total
  total="$(cycle_count)"
  local sleep_for
  sleep_for="$(sleep_seconds)"
  local cycle=1

  while [[ "$cycle" -le "$total" ]]; do
    note "cycle $cycle/$total: $label"
    "$@"

    if [[ "$cycle" -lt "$total" && "$sleep_for" -gt 0 ]]; then
      note "sleeping ${sleep_for}s before next cycle"
      sleep "$sleep_for"
    fi

    cycle=$((cycle + 1))
  done
}
