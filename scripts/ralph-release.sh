#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "release"
note "running release Ralph loop"

release_env_present() {
  require_env_any "github release" GITHUB_TOKEN GH_TOKEN
}

release_cycle() {
  run ./scripts/qa.sh validate
  run ./scripts/qa.sh core
  run ./scripts/qa.sh native
  run ./scripts/qa.sh adapters
  run ./scripts/qa.sh provider
  run ./scripts/qa.sh daemon
  run npm ci --ignore-scripts

  if release_env_present; then
    note "github token present; running semantic-release dry run"
    run npm run release:dry-run
  else
    note "github token missing; validating release config shape instead"
    run node -e 'const fs = require("node:fs"); const config = JSON.parse(fs.readFileSync(".releaserc.json", "utf8")); if (!Array.isArray(config.branches) || !config.branches.includes("main")) throw new Error("main release branch missing"); if (!Array.isArray(config.plugins) || !config.plugins.includes("@semantic-release/github")) throw new Error("github plugin missing"); console.log("semantic-release config ok");'
  fi
}

run_cycles "release gate" release_cycle

note "release Ralph loop complete"
note "log file: $LOG_FILE"
