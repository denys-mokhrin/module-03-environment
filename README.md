# module-03-environment

Course project for Agentic Engineering 3.0, module 3: Claude Code environment, permissions and isolation.

A small Node.js + TypeScript (Express) service, configured so Claude Code works safely in it. Based on the course starter `3.9-starters/nodejs-typescript` (path B).

## Run

- Tests: `npm test` (Node 22.18+ runs TypeScript natively, no install needed)
- Dev server: `npm run dev`
- Config checks: `make verify` (on Windows without `make`: `bash tests/validate-devcontainer.sh && bash tests/validate-whitelist.sh`)

## Claude Code configuration

| Level | File | In git | What it holds |
|---|---|---|---|
| User | `~/.claude/settings.json` | no | model, attribution, status line, auto-compact threshold |
| Project | `.claude/settings.json` | yes | team permissions (deny secrets, allow the test loop), sandbox, env |
| Local | `.claude/settings.local.json` | no | personal model for this project, local env |

Key decisions:
- `Read`/`Edit` deny rules for `.env`, `*.pem`, `*.key`, credentials and `~/.ssh`, `~/.aws` live in the project file, so they apply to everyone on the team.
- The sandbox also denies reading `./.env`, `~/.ssh`, `~/.aws` at the OS level, because permissions only see the command Claude runs, not the files a script opens.
- `excludedCommands` uses `docker *`: a bare `docker` entry matches only the command without arguments.

## Isolation

- `.devcontainer/` and `docker-compose.yml`: Claude Code runs as the non-root `node` user, and a default-deny firewall (`init-firewall.sh`) allows only the domains listed in the sandbox config.
- `build.sh` and `leak.sh` are deliberate test scripts for lessons 3.6 and 3.7: they print `.env`, which holds only `FAKE_SECRET=only-for-test`.
