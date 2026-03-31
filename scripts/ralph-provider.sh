#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "provider"
PROMPT="${1:-say hello and report the configured provider}"
PROVIDER="${CLAW_PROVIDER:-generic}"

note "running provider Ralph loop for provider=$PROVIDER"

provider_env_present() {
  case "$PROVIDER" in
    glm)
      require_env_any "glm" GLM_API_KEY BIGMODEL_API_KEY CLAW_API_KEY
      ;;
    nim)
      require_env_any "nim" NIM_API_KEY NVIDIA_API_KEY CLAW_API_KEY
      ;;
    kimi)
      require_env_any "kimi" KIMI_API_KEY MOONSHOT_API_KEY CLAW_API_KEY
      ;;
    *)
      require_env_any "generic provider" CLAW_API_KEY GLM_API_KEY BIGMODEL_API_KEY NIM_API_KEY NVIDIA_API_KEY KIMI_API_KEY MOONSHOT_API_KEY
      ;;
  esac
}

provider_cycle() {
  run mix escript.build
  run ./claw_code doctor

  if provider_env_present; then
    note "provider credentials present; running live provider smoke"
    run ./claw_code chat --provider "$PROVIDER" "$PROMPT"
  else
    note "provider credentials not present; validating missing-provider path instead"
    run ./claw_code chat --provider "$PROVIDER" "$PROMPT"
  fi
}

run_cycles "provider gate" provider_cycle

note "provider Ralph loop complete"
note "log file: $LOG_FILE"
