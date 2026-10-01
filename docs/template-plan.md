# Plan: a team template repository

Status: plan, not started. This document describes a starter repository for the
team's projects and the order to build it in. It is written for the people and
agents building the template. Copy it into the new repository as its first
commit.

## Goal

Every new project starts from one repository that already has:

- Instructions that Cursor agents follow (rules and skills).
- Pinned tool versions and one set of commands that people, agents, and
  continuous integration (CI) all run the same way.
- A working example and checks for each core language: Python, TypeScript,
  Rust, and C/C++.
- CI on GitHub Actions that enforces the rules, rather than relying on agents
  to remember them.
- A way for agents to launch long machine-learning or simulation jobs on
  separate compute, safely and within a budget.
- Support for several agents working at once without breaking each other's
  work.
  Agents write most of the code. People design the structure and review every
  change. The template is built around that split: its main job is to make each
  change cheap and reliable for a person to review.

## Terms

| Term                | Meaning                                                                                                                                               |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rule                | A short instruction file in `.cursor/rules/`. "Always applied" rules are loaded into every agent session.                                             |
| Skill               | A longer how-to file in `.cursor/skills/`, read by an agent only when its task needs it.                                                              |
| Cloud agent         | A Cursor agent that runs on its own virtual machine and branch, and opens a pull request (PR).                                                        |
| Template repository | A repository new projects are copied from.                                                                                                            |
| Copier              | A tool that creates a project from a template and can later pull template updates into it.                                                            |
| Lockfile            | A generated file that records the exact version of every dependency.                                                                                  |
| Merge queue         | A GitHub feature that tests each PR combined with everything ahead of it before merging, so two PRs that pass separately can't break `main` together. |
| Mutation testing    | A check on test quality: a tool makes small deliberate bugs in the code and reports which ones the tests fail to catch.                               |
| Hermetic test       | A test that depends only on its own inputs: no shared files, ports, databases, or test order.                                                         |
| Launcher            | The one tool agents use to start compute jobs on other machines.                                                                                      |
| Run record          | A small file written by every compute job that records the exact code, image, settings, and hardware used.                                            |
| Handoff             | The PR description, which tells the reviewer what was done, how it was checked, and what was not.                                                     |

## What the evidence says

These findings shaped the plan. Most are 2026 preprints and some use small
benchmarks, so treat the numbers as direction rather than precise effects.
| # | Finding | What the plan does about it |
|---|---|---|
| F1 | Repository instruction files such as `AGENTS.md` raised cost by about 20% and did not raise success rates. Agents follow every instruction, so unnecessary ones make tasks harder. Repository overviews did not help. [1] | Keep always-applied rules few and short. Put detail in skills. Keep `AGENTS.md` to commands and unusual requirements. |
| F2 | Skills written by people raised success by about 16 points on average (about 5 for software tasks). Skills an agent wrote for itself did not help, and sometimes hurt. Short, focused skills beat long ones. [2] | People write or edit every skill. Changes to `.cursor/` need a person's review. |
| F3 | About half of agent PRs that passed the tests would not have been merged by the projects' maintainers. The main reasons were not really fixing the problem, breaking other code, and poor code quality. [3] | Passing tests is not enough. Add an independent review step, test-quality checks, and a clearer handoff. |
| F4 | Telling agents to "use test-driven development" or "use property-based testing" made little difference; agents went through the motions. Tests that state concrete expected behaviour did help. [4][5] | Don't require a process. Require one named test for each acceptance criterion, and measure test quality with mutation testing. |
| F5 | A second model reviewing finished code helped more than a model planning before the code was written. Good plans help, but a bad plan is worse than none. [6][7] | People approve plans only for larger changes. Every PR gets a review by a separate agent before a person sees it. |
| F6 | Asking agents for a structured handoff made their work easier to review, not more correct. Sections such as "known limitations" appeared only when required. [8] | The PR template requires those sections. |
| F7 | In Cursor's experiments with hundreds of agents, agents coordinating through a shared file with locks collapsed to the speed of 1–3 agents. What worked was a planner that splits the work, workers that each own one task on their own copy of the code, and a handoff back to the planner. [9] | Plans and task lists live in Linear, not in a shared file. Each task becomes one agent, one branch, and one PR. |
| F8 | Splitting closely connected code between agents created broken interfaces and rework. Isolated workspaces plus git merges and tests worked well. [10][11] | Agree the interface first and land it, then split the work. Use a merge queue. |
| F9 | At Meta, engineers accepted 73% of tests generated to catch specific deliberate bugs. [12] | Use mutation testing to measure whether agent-written tests catch real mistakes. |

## Decisions

Each decision has a recommended default. Agents proceed with the default unless
a person has recorded a different choice here.
| # | Decision | Recommended default | Why |
|---|---|---|---|
| D1 | How projects are created from the template and receive later updates | Copier | A GitHub template copies files once; later changes to rules and skills never reach existing projects. Copier can pull them in later, and can include only the languages a project needs. Cost: one more tool, and some combinations of languages go untested. |
| D2 | Tool version manager and command runner | `mise` | One file (`mise.toml`) pins the versions of Python, Node, `uv`, `d2`, and so on, and defines the shared commands. Works the same locally, in agents, and in CI. |
| D3 | Python dependency manager | `uv`; switch to `pixi` for projects that need compiled scientific libraries | `uv` is fast and handles normal Python packages. `pixi` uses conda-forge, which also packages MPI, HDF5, CUDA libraries, and compilers. |
| D4 | Where compute jobs run | SkyPilot | One job description runs on the major clouds, GPU providers, Kubernetes, or a Slurm cluster. Switch to Slurm with Apptainer if the team has a university or lab cluster, since those clusters usually don't allow Docker. |
| D5 | Licence | **Decided:** 0BSD | The most permissive OSI-approved licence: no conditions, not even attribution. It grants no patent licence, unlike Apache-2.0. Projects may pick their own. |
| D6 | Merge method | Merge commits; no squash | The rules ask for commit history that reads as the review story. Squashing erases it. |
| D7 | Which changes need a person to approve a plan before coding | New module; change to a public interface or data format; new dependency; compute spend above the cost limit | Planning has a cost and only pays off for larger changes. |
| D8 | Cost limit for one agent-launched compute job before asking a person | **Decided:** no per-job limit for now; total agent compute spend at most $10,000 per day | Enforce the daily cap with the provider's budget controls (T16), not only the rule. Revisit the per-job limit when T16 lands. |
| D9 | Open agent PRs allowed per reviewer | Start at 3 | People review everything, so review time, not agent count, limits throughput. Adjust from data. |
| D10 | Cursor plan | Ask the owner | Team pools of the team's own GPU machines for agents need the Enterprise plan. |

## The work

Each task below is one PR of at most 500 changed lines, following
`reviewable-prs`. Each must pass CI on its own. "Needs" lists the tasks that
must be merged first. Tasks with the same needs can run in parallel, each with
its own agent.
Some steps are settings in GitHub, Cursor, or Linear rather than files. Agents
can't change those settings, so they're marked **(person)**.

### Stage 1: start the repository

**T1. Create the repository with the agent instructions.** Needs: nothing.

- **(person)** Create the new repository. Mark it as a template in GitHub
  settings if D1 is "GitHub template".
- Copy from the `slang` repository: `.cursor/rules/`, `.cursor/skills/`, and
  `docs/template-plan.md` (this file).
- Remove everything specific to slang. The skills mention slang as an example
  in a few places; replace those with neutral examples.
- Write a short `README.md` covering what the template is, how to start a
  project from it, and links to this plan and the skills.
- Done when: no file mentions slang, and every link in the README works.
  **T2. Basic repository files.** Needs: T1.
- `.editorconfig` (UTF-8, LF line endings, final newline).
- `.gitattributes`: LF line endings. Mark lockfiles and generated SVGs as
  generated, so GitHub collapses them in diffs.
- `.gitignore` for all four languages, plus `docs/_build/`,
  `docs/_generated/`, and `.env`.
- `.env.example`, listing environment variables by name with no values.
- `LICENSE` (D5) and `CODEOWNERS`. `CODEOWNERS` requires a person's review for
  `.cursor/`, `docs/architecture.md`, and public interface files.
- Done when: the files exist and CI (once T4 lands) passes on them.
  **T3. Tool versions, shared commands, and agent setup.** Needs: T1.
- `mise.toml` pins tool versions and defines the commands `setup`, `fmt`,
  `lint`, `test`, `docs`, and `check`. `check` runs everything CI runs. Each
  command starts as a placeholder that each language task fills in.
- `.cursor/environment.json`: the install step runs `mise install` and
  `mise run setup`, so a cloud agent's machine matches CI.
- `AGENTS.md`: only the commands, where code lives, and requirements an agent
  wouldn't guess. Add a "Cursor Cloud specific instructions" section. No
  overview of the repository (see F1).
- Done when: a fresh cloud agent can run `mise run check` with no other setup.
  **T4. CI skeleton and repository protection.** Needs: T3.
- `.github/workflows/ci.yml`:
  - One job per language, each running only when files of that language
    change. Language tasks add their jobs; this task adds the structure.
  - A docs job that runs `docs/build.sh` once it exists.
  - Triggers on pull requests and on `merge_group`, the event the merge queue
    uses.
  - Cancels older runs of the same PR when a new commit arrives.
- A PR size check that fails above 500 changed lines, not counting lockfiles
  or generated files, unless the PR description starts with `Oversize:`.
- Security defaults:
  - Workflows get read-only permissions unless a job needs more.
  - Third-party actions are pinned to an exact commit.
  - Renovate or Dependabot opens dependency and action updates.
  - CodeQL code scanning covers all four languages.
- `.github/rulesets/main.json`: require CI to pass, require one human review,
  turn on the merge queue, and allow only merge commits (D6). Add a script or
  documented `gh api` command that applies the ruleset, because GitHub doesn't
  copy settings from templates.
- **(person)** Apply the ruleset. Turn on secret scanning with push
  protection.
- Done when: a test PR above 500 lines fails the size check, and a PR merges
  through the merge queue.
  **T5. PR template.** Needs: T1. Can run alongside T2–T4.
- `.github/pull_request_template.md`, in the order from `reviewable-prs`:
  1. What changes and why, with the Linear issue ID (for example
     `Fixes ENG-123`). This links the PR to the issue.
  2. How to review: where to start, and what can be skimmed.
  3. How it was verified, including which test covers each acceptance
     criterion.
  4. What was not verified, and known limitations.
  5. Changes from the agreed plan, and problems found outside the task's
     scope. Report these as new Linear issues rather than fixing them here.
  6. Diagrams updated, or "no structural change".
  7. Risks and follow-ups.
- Update `reviewable-prs` to match.
- Done when: the template and the rule list the same sections in the same
  order.

### Stage 2: languages

Each language task adds:

- A small example module with documentation comments.
- One test.
- Formatting, lint, and type checks, with warnings treated as errors.
- Its block in `docs/build.sh`.
- Its CI job.
- A command that tests only that package.
  The example exists to prove the checks work. A project deletes it when its
  first real code arrives.
  Every check must fail when broken. The PR shows this by breaking the check once
  (for example, adding an undocumented public function), then reverting.
  **T6. Python, and the documentation build.** Needs: T3, T4.
- `uv` for dependencies, Python version, and the lockfile; `ruff` for format and
  lint (including documentation-comment rules); `pyright` for types; `pytest`
  for tests, including the examples inside documentation comments.
- Tests run in parallel (`pytest -n auto`), so tests that depend on shared
