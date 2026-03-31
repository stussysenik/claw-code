#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mode="${1:-validate}"
shift || true

case "$mode" in
  validate)
    exec "$ROOT/scripts/validate-repo.sh"
    ;;
  core|native|adapters|provider|daemon|release)
    exec "$ROOT/scripts/ralph-${mode}.sh" "$@"
    ;;
  *)
    printf 'usage: %s [validate|core|native|adapters|provider|daemon|release] [args...]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
    ;;
esac
