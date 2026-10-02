# Agent instructions

## Commands

`mise.toml` defines every command, so people, agents, and CI run the same
thing:

| Command | What it does |
|---|---|
| `mise run setup` | Install project dependencies. |
| `mise run fmt` | Format all code in place. |
| `mise run lint` | Check formatting, lint, and types without changing files. |
| `mise run test` | Run all tests. |
| `mise run docs` | Build the documentation site. |
| `mise run check` | Run everything CI runs. |

Run `mise run check` before opening a PR; it must pass. Until the language
tasks in `docs/template-plan.md` land, each command is a placeholder that
prints a message and succeeds.

## Where code lives

No code yet. Each language task adds its directory and lists it here.

## Requirements

- Pin every tool in `mise.toml`, at an exact version. Don't install tools
  another way.
- Don't change `.cursor/rules/` or `.cursor/skills/` unless the task is about
  them. People write those files (finding F2 in the plan).
- The PR body follows the `reviewable-prs` rule.
- Before asking a person to review a PR, fix each finding in Bugbot's review
  of the latest push (the `Cursor Bugbot` check), or reply saying why it is
  wrong. If Bugbot doesn't run, say so under "What was not verified".

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `.cursor/install.sh` when the machine is
  set up. It installs the pinned mise to `/usr/local/bin`, which is on every
  agent shell's PATH, then runs `mise install` and `mise run setup`. If
  `mise` or a tool is missing, rerun
  `MISE_INSTALL_PATH=/usr/local/bin/mise bash .cursor/install.sh`.
