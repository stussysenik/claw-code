#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mix format --check-formatted
mix test
mix escript.build
./claw_code summary >/dev/null
./claw_code symphony --native "review MCP tool" >/dev/null

echo "repo validation passed"
