# Release Checklist

## Table of Contents

- [Checklist](#checklist)
- [Release Discipline](#release-discipline)

## Checklist

1. `mix format --check-formatted`
2. `mix test`
3. `mix escript.build`
4. `./claw_code summary`
5. `./claw_code doctor`
6. `./claw_code symphony --native "review MCP tool"`
7. `./scripts/qa.sh release`
8. `npm run release:dry-run` when GitHub auth is available; otherwise prove `.releaserc.json` and workflow shape still parse cleanly
9. Session files created by new flows can still be loaded
10. Any new environment variables are documented
11. The relevant mission file and issue links are updated

## Release Discipline

- Use conventional commits so semantic-release can generate tags, changelogs, and GitHub Releases later.
- Keep release evidence recorded in `progress.md`.
- If `main` gains branch protection that blocks bot pushes, revisit the `@semantic-release/git` path before enabling automated changelog commits.
