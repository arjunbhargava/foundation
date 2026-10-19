---
orphan: true
---

# Plan: a team template repository

This document records the findings and decisions behind a starter repository
for the team's projects. It is written for the people and agents who maintain
the template. Unfinished work from the original task list is in Linear.

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

| Term | Meaning |
|---|---|
| Rule | A short instruction file in `.cursor/rules/`. "Always applied" rules are loaded into every agent session. |
| Skill | A longer how-to file in `.cursor/skills/`, read by an agent only when its task needs it. |
| Cloud agent | A Cursor agent that runs on its own virtual machine and branch, and opens a pull request (PR). |
| Template repository | A repository new projects are copied from. |
| Copier | A tool that creates a project from a template and can later pull template updates into it. |
| Lockfile | A generated file that records the exact version of every dependency. |
| Merge queue | A GitHub feature that tests each PR combined with everything ahead of it before merging, so two PRs that pass separately can't break `main` together. |
| Mutation testing | A check on test quality: a tool makes small deliberate bugs in the code and reports which ones the tests fail to catch. |
| Hermetic test | A test that depends only on its own inputs: no shared files, ports, databases, or test order. |
| Launcher | The one tool agents use to start compute jobs on other machines. |
| Run record | A small file written by every compute job that records the exact code, image, settings, and hardware used. |
| Handoff | The PR description, which tells the reviewer what was done, how it was checked, and what was not. |

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
| F6 | Asking agents for a structured handoff made their work easier to review, not more correct. Sections such as "known limitations" appeared only when required. [8] | The PR template requires a short handoff, with one line for any limitation that matters. |
| F7 | In Cursor's experiments with hundreds of agents, agents coordinating through a shared file with locks collapsed to the speed of 1–3 agents. What worked was a planner that splits the work, workers that each own one task on their own copy of the code, and a handoff back to the planner. [9] | Plans and task lists live in Linear, not in a shared file. Each task becomes one agent, one branch, and one PR. |
| F8 | Splitting closely connected code between agents created broken interfaces and rework. Isolated workspaces plus git merges and tests worked well. [10][11] | Agree the interface first and land it, then split the work. Test each PR combined with `main` before merging, with a merge queue after the organization move; until then PRs aren't retested against the latest `main`. |
| F9 | At Meta, engineers accepted 73% of tests generated to catch specific deliberate bugs. [12] | Use mutation testing to measure whether agent-written tests catch real mistakes. |

## Decisions

Each decision has a recommended default. Agents proceed with the default unless
a person has recorded a different choice here.

| # | Decision | Recommended default | Why |
|---|---|---|---|
| D1 | How projects are created from the template and receive later updates | Copier | A GitHub template copies files once; later changes to rules and skills never reach existing projects. Copier can pull them in later, and can include only the languages a project needs. Cost: one more tool, and some combinations of languages go untested. |
| D2 | Tool version manager and command runner | `mise` | `mise.toml` pins the tools that more than one language, or the docs build, runs (such as `uv`) and defines the shared commands; each language's own tools and commands are in `.config/mise/conf.d/<language>.toml`. Works the same locally, in agents, and in CI. |
| D3 | Python dependency manager | `uv`; switch to `pixi` for projects that need compiled scientific libraries | `uv` is fast and handles normal Python packages. `pixi` uses conda-forge, which also packages MPI, HDF5, CUDA libraries, and compilers. |
| D4 | Where compute jobs run | SkyPilot | One job description runs on the major clouds, GPU providers, Kubernetes, or a Slurm cluster. Switch to Slurm with Apptainer if the team has a university or lab cluster, since those clusters usually don't allow Docker. |
| D5 | Licence | **Decided:** Apache-2.0, copyright the repository owner | Permissive, requires attribution through `NOTICE`, and grants an explicit patent licence. Projects may pick their own. |
| D6 | Merge method | Merge commits; no squash | The rules ask for commit history that reads as the review story. Squashing erases it. |
| D7 | Which changes need a person to approve a plan before coding | New module; change to a public interface or data format; new dependency; compute spend above the cost limit. **Changed (2026-10-16):** these need a written plan, and the agent proceeds after posting it. A person approves first only when the change is hard to reverse: a data format with existing users, a published interface, a shipped dependency with a licence question, or compute spend. | Planning has a cost and only pays off for larger changes. Waiting for approval stopped most PRs on the owner. |
| D8 | Cost limit for one agent-launched compute job before asking a person | **Decided:** no per-job limit for now; total agent compute spend at most $10,000 per day | Enforce the daily cap with the provider's budget controls, not only the rule (INFRA-62). Revisit the per-job limit when INFRA-62 lands. |
| D9 | Open agent PRs allowed per reviewer | **Decided:** 5, raised from 3 on 2026-10-02 | People review everything, so review time, not agent count, limits throughput. The owner raised it to 5 early on, because 3 made progress too slow. Adjust from data. |
| D10 | Cursor plan | Ask the owner | Team pools of the team's own GPU machines for agents need the Enterprise plan. |
| D11 | Which model each agent runs on | **Decided (2026-10-03):** design work (plans, rulesets, CI security, and changes that span several areas, such as converting the repository to Copier) runs on Claude Opus 5.5 at xhigh effort. The orchestrator, and tasks with checkable acceptance criteria and a local change, run on Claude Sonnet 5.5 at high effort. A Sonnet task that fails twice on the same CI failure or Bugbot finding is relaunched on Opus from its branch. **Changed (2026-10-14):** design work on Opus runs at medium effort with `fast=false`, to lower cost. xhigh effort is reserved for an extremely challenging or confusing feature, and the orchestrator says why in its launch message to the owner. A relaunch after two failures is at medium effort, unless the failure itself looks confusing. Everything else is unchanged. | Spends the most capable model only where a mistake is costly. Revisit with the data from `mise run spend`: a cheaper model saves money only if it doesn't add review rounds. |

## How agents work on this repository

- One task, one Linear sub-issue, one agent, one branch, one PR.
- A planner (a person, or an agent using `decompose`) creates the tasks.
  Workers don't coordinate with each other; they report back through the PR
  description.
- An orchestrating agent hands off to a fresh one, with a written summary of
  the state, after every few merges. Each turn resends its whole context, so
  the cost of a turn grows with every message it has received. Workers report
  back once, when their PR is ready or blocked.
- Shared state lives in git and Linear only. No shared task files, no shared
  databases or fixed ports, and every external resource name includes the
  branch or run ID.
- An agent that finds a problem outside its task lists it under Follow-ups
  instead of fixing it.
- Each PR is tested combined with `main` before merging, by a merge queue
  once the repository moves to an organization. Until then a PR is tested against the `main` it
  last ran on, not the latest one.
- For a hard task, run several agents on it separately and review only the
  best result. Parallel agents should not multiply review work.

## Not in scope

- A custom system for coordinating agents. Cursor already provides subagents,
  an API, automations, and Linear routing.
- Agents talking to each other directly, or shared memory files.
- A dedicated agent for merging other agents' work. A merge queue, after
  the organization move, covers it, and Cursor found such a role
  slowed things down [9].
- Release automation, deployment, and choices of C/C++ package manager or
  experiment tracker. These belong to each project.

## Sources

1. Gloaguen et al., [Evaluating AGENTS.md](https://arxiv.org/abs/2602.11988), ICLR 2026 workshop.
2. [SkillsBench](https://arxiv.org/abs/2602.12670), 2026.
3. METR, [Many SWE-bench-passing PRs would not be merged](https://metr.org/notes/2026-03-10-many-swe-bench-passing-prs-would-not-be-merged-into-main/), March 2026.
4. Fowler, [TDD inside the agent loop](https://martinfowler.com/articles/exploring-gen-ai/tdd-in-the-agent-loop.html).
5. Luu, [How well do agents use test and verification techniques?](https://danluu.com/agentic-testing/)
6. [Review beats planning](https://arxiv.org/abs/2603.03406), 2026. Small models on short programming problems; weak evidence for larger work.
7. [From plan to action: how well do agents follow the plan?](https://arxiv.org/abs/2604.12147), 2026.
8. [Software delegation contracts](https://arxiv.org/abs/2606.17099), 2026. A pilot study of 64 runs.
9. Cursor, [Scaling long-running autonomous coding](https://cursor.com/blog/scaling-agents) and [Towards self-driving codebases](https://cursor.com/blog/self-driving-codebases).
10. [Cohesion-aware task partitioning for multi-agent coding](https://www.alphaxiv.org/overview/2606.00953), 2026.
11. [CAID: effective strategies for asynchronous software engineering agents](https://www.alphaxiv.org/abs/2603.21489), 2026.
12. Meta, [Mutation-guided LLM-based test generation](https://arxiv.org/abs/2501.12862), 2025.
