# foundation

A starter repository for the team's projects. Agents write most of the code
and people review every change, so the template exists to make each change
cheap and reliable to review. When complete, it will provide instructions
that Cursor agents follow, pinned tools and shared commands, example code and
checks for Python, TypeScript, Rust, and C/C++, CI, and support for
agent-launched compute jobs.

Status: under construction. So far it has the agent rules, skills, and Bugbot
review instructions described below, the shared `mise run` commands, Python
and Rust, each with its checks and an example module, the documentation build
([`docs/build.sh`](docs/build.sh)), cloud agent setup in
[`.cursor/environment.json`](.cursor/environment.json), and the
[PR template](.github/pull_request_template.md).
[`docs/template-plan.md`](docs/template-plan.md) lists the remaining work and
the order it lands in.

## Start a project

Projects will be created with [Copier](https://copier.readthedocs.io/), which
can later pull template updates into them (decision D1 in the plan). Until
that lands, copy this repository and delete what the project doesn't use.
Then add the repository to Linear as [`docs/linear.md`](docs/linear.md) says.

## Commands

[mise](https://mise.jdx.dev/) installs the tool versions pinned in
[`mise.toml`](mise.toml) and runs the shared commands, so people, agents, and
CI (once task T4 in the plan adds it) all run the same `mise run <command>`.
[`AGENTS.md`](AGENTS.md) lists the commands.

## Agent instructions

Rules in [`.cursor/rules/`](.cursor/rules/) load into every agent session,
except `dependencies`, which loads when an agent reads or edits a dependency
manifest or lockfile:

| Rule | Requires |
|---|---|
| [`clarity`](.cursor/rules/clarity.mdc) | Code, docs, and PRs are written for a competent engineer new to the code, and checked against the rule's review checklist before finishing. |
| [`compute-cost`](.cursor/rules/compute-cost.mdc) | Agent compute jobs share a cap of $10,000 a day. An agent asks a person before a job that would take its task over the task's compute budget, and before every job until the `compute-jobs` skill exists. |
| [`dependencies`](.cursor/rules/dependencies.mdc) | A new dependency comes with a one-line reason, an allowed licence, and a committed lockfile. A lockfile merge conflict is resolved by relocking, never by hand. |
| [`docs-from-source`](.cursor/rules/docs-from-source.mdc) | API reference is generated from doc comments, never written by hand, and each doc comment states the contract a caller needs. |
| [`ponytail`](.cursor/rules/ponytail.mdc) | The simplest solution that works, once the problem is understood. |
| [`reviewable-prs`](.cursor/rules/reviewable-prs.mdc) | At most 500 changed lines per PR, one logical change each, and a body that follows the PR template. |
| [`secrets`](.cursor/rules/secrets.mdc) | Secrets come from environment variables, are listed by name in `.env.example`, and never appear in commits or logs. |

Skills in [`.cursor/skills/`](.cursor/skills/) are read only when a task needs
them:

| Skill | Use when |
|---|---|
| [`add-language`](.cursor/skills/add-language/SKILL.md) | Adding a programming language to a project: its checks, docs build, CI job, and test command. |
| [`architecture-docs`](.cursor/skills/architecture-docs/SKILL.md) | Designing module or system boundaries, or writing READMEs, design docs, ADRs, and architecture diagrams. |
| [`clarity`](.cursor/skills/clarity/SKILL.md) | Creating or reorganising a module or file, writing a document, or designing a diagram, docs site, terminal output, or user interface. |
| [`decompose`](.cursor/skills/decompose/SKILL.md) | Splitting an approved plan into Linear sub-issues, one per PR, for agents to work on in parallel. |
| [`large-changes`](.cursor/skills/large-changes/SKILL.md) | Planning a change likely to exceed 500 changed lines: splitting it into stacked PRs, or justifying one oversize PR. |
| [`prune-review`](.cursor/skills/prune-review/SKILL.md) | Finding and removing dead code, speculative abstractions, and stale docs, on request or after a breaking change. |
| [`source-docs`](.cursor/skills/source-docs/SKILL.md) | Writing the first code in the repository, adding a language, or changing the docs build or its gates. |
| [`spec`](.cursor/skills/spec/SKILL.md) | Before coding a change that decision D7 in the plan says needs an approved plan: a new module, a public interface or data format change, a new dependency, or compute spend above the cost limit. |
| [`testing`](.cursor/skills/testing/SKILL.md) | Writing or changing tests, including the checks and tolerances numerical code needs. |

Changes to rules and skills are written or edited by a person, not generated
by an agent for itself, because only the former have been shown to help
(finding F2 in the plan).

Bugbot, Cursor's review agent, reviews every PR before a person does, using
the checks in [`.cursor/BUGBOT.md`](.cursor/BUGBOT.md).
