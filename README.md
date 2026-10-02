# foundation

A starter repository for the team's projects. Agents write most of the code
and people review every change, so the template exists to make each change
cheap and reliable to review. When complete, it will provide instructions
that Cursor agents follow, pinned tools and shared commands, example code and
checks for Python, TypeScript, Rust, and C/C++, CI, and support for
agent-launched compute jobs.

Status: under construction. So far it has the agent rules and skills listed
below, the shared `mise run` commands (placeholders until the language tasks
add tools and checks), cloud agent setup in
[`.cursor/environment.json`](.cursor/environment.json), the
[PR template](.github/pull_request_template.md), and the Bugbot review
instructions. [`docs/template-plan.md`](docs/template-plan.md) lists the
remaining work and the order it lands in.

## Start a project

Projects will be created with [Copier](https://copier.readthedocs.io/), which
can later pull template updates into them (decision D1 in the plan). Until
that lands, copy this repository and delete what the project doesn't use.

## Agent instructions

Rules in [`.cursor/rules/`](.cursor/rules/) load into every agent session:

| Rule | Requires |
|---|---|
| [`clarity`](.cursor/rules/clarity.mdc) | Everything is written for a competent engineer new to the code. |
| [`docs-from-source`](.cursor/rules/docs-from-source.mdc) | API reference is generated from doc comments; `docs/build.sh` fails on undocumented public symbols. |
| [`ponytail`](.cursor/rules/ponytail.mdc) | The simplest solution that works, once the problem is understood. |
| [`reviewable-prs`](.cursor/rules/reviewable-prs.mdc) | At most 500 changed lines per PR, one logical change each, and a fixed PR body. |

Skills in [`.cursor/skills/`](.cursor/skills/) are read only when a task needs
them:

| Skill | Use when |
|---|---|
| [`architecture-docs`](.cursor/skills/architecture-docs/SKILL.md) | Designing module boundaries, or writing design docs, ADRs, and diagrams. |
| [`clarity`](.cursor/skills/clarity/SKILL.md) | Writing anything a person will read. Holds the review checklist. |
| [`prune-review`](.cursor/skills/prune-review/SKILL.md) | Removing dead code, speculative abstractions, and stale docs. |
| [`source-docs`](.cursor/skills/source-docs/SKILL.md) | Changing public code or doc comments, or adding a language to the docs build. |

Changes to rules and skills are written or edited by a person, not generated
by an agent for itself, because only the former have been shown to help
(finding F2 in the plan).

Bugbot, Cursor's review agent, reviews every PR before a person does, using
the checks in [`.cursor/BUGBOT.md`](.cursor/BUGBOT.md).
