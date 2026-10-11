# Auto mode

In auto mode, a pull request (PR) into `main` merges without an approving
review when it changes no path in `.github/CODEOWNERS`, CI passes, and every
review thread is resolved. CI and Bugbot replace a person as the gate, so
exploratory work that needs several rounds doesn't wait for review on each.
It is a switch for the whole repository, and applies to every PR into `main`,
not only agent PRs.

Status: in progress (T23 in [the template plan](template-plan.md)). This page
covers the review ruleset. Until the auto-merge workflow lands, a PR that
meets the requirements still needs someone to press merge.

## What changes

Auto mode swaps the review ruleset. The `main: checks` ruleset is the same in
both modes: `ci-ok` and `pr-size` must pass on a branch that is up to date
with `main`.

| Requirement | Review mode: `main: review` | Auto mode: `main: review (auto mode)` |
|---|---|---|
| Approving reviews | 1 | 0 |
| Code owner's approval when a PR changes an owned path | Required | Required |
| Every review thread resolved | Not required | Required |

`.github/rulesets/main-review.json` and `main-review-auto.json` hold the two
rulesets. `mise run lint:rulesets` fails if they differ in anything else.

## What still needs the owner

A PR that changes a path in `.github/CODEOWNERS` needs a code owner's
approval in both modes. Those paths include CI and the rulesets
(`.github/`), the commands CI runs (`mise.toml`), the agent instructions
(`.cursor/` and `AGENTS.md`), and the files that configure checks,
dependencies, and module boundaries, such as `biome.json`, `docs/build.sh`,
`Cargo.toml`, and `pyproject.toml`. A change to one of those can weaken a
check or add a dependency, which D7 already requires the owner to approve.
Agent PRs are authored by the owner's account, and GitHub doesn't let
authors approve their own PRs, so the owner merges these with the admin
bypass.

## Switching auto mode on and off

```sh
mise exec -- .github/rulesets/apply.sh --dry-run --auto  # print the changes
mise exec -- .github/rulesets/apply.sh --auto            # switch on
mise exec -- .github/rulesets/apply.sh                   # switch off
```

`--auto` creates or updates `main: review (auto mode)`, then disables
`main: review`; without the flag, the script does the reverse. It needs `gh`
logged in as a repository admin. Without a shell, use Settings > Rules >
Rulesets: the first time, import `main-review-auto.json` with New ruleset >
Import a ruleset; then set the enforcement status of one review ruleset to
Active and the other to Disabled.

## Instruction for worker prompts

Add these lines to the prompt of each agent that works in auto mode:

> Resolve a Bugbot review thread only after you fix its finding. If you
> dispute a finding, reply saying why and leave the thread open, so the PR
> waits for the owner.

An unresolved thread blocks merging. In auto mode, threads are the only gate
against merging a flawed PR that passes CI, so only the owner closes a
disputed one.

## Auditing and reverting

Every PR merges as a merge commit (D6), so each auto-merged PR is one commit
on `main`, and one revert undoes it. To list the PRs merged since auto mode
was switched on, here from 2026-10-10:

```sh
gh pr list --state merged --label agent --search "merged:>=2026-10-10" \
  --json number,title,mergedAt,mergeCommit
```

Read each with `gh pr diff <number>`; its CI runs and Bugbot's review are on
the PR page. To revert one, branch from `main`, run
`git revert -m 1 <merge commit>`, and open a PR. `-m 1` keeps `main`'s side
of the merge, which undoes everything the PR changed.

## Limits

- **Spend: $500 per day** across all cloud agent runs on this repository.
  It counts cloud agent runs only, as `mise run spend` counts them, not
  editor or Bugbot usage. It is a starting value, to revise with
  `mise run spend` data. The repository can't stop a run partway through, so
  the real cap is the spend limit the owner sets in the Cursor dashboard. The
  orchestrator checks the day's spend at each pause with
  `mise run spend -- --since "$(date -u +%F)"`, whose "All N cloud agent
  runs" row is the total since 00:00 UTC. That total includes every cloud
  agent run on the team's account, so while other repositories run agents
  too, it overstates this repository's spend.
- **Size: 500 changed lines per PR**, the ceiling `pr-size` enforces in both
  modes. A PR whose description starts with `Oversize:` passes `pr-size`, and
  Bugbot then checks that the `large-changes` skill allows it.
