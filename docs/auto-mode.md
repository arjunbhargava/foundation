# Auto mode

In auto mode, a pull request (PR) into `main` merges without an approving
review when it changes no path in `.github/CODEOWNERS`, CI passes, and every
review thread is resolved. CI and Bugbot replace a person as the gate, so
exploratory work that needs several rounds doesn't wait for review on each.
It is a switch for the whole repository, and applies to every PR into `main`,
not only agent PRs.

Status: in progress (T23 in [the template plan](template-plan.md)). The
review ruleset and the auto-merge workflow are in place. Until the
branch-update workflow lands, a PR that falls behind `main` waits for someone
to update it.

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

## The auto-merge workflow

`.github/workflows/auto-merge.yml` turns on GitHub's auto-merge, with a merge
commit, for an agent PR once Bugbot has reviewed the PR's latest commit.
GitHub then merges the PR when the rulesets allow it. If the PR already meets
them, the workflow merges it at once. It waits for Bugbot because until
Bugbot posts, there are no review threads to block the merge.

It manages a PR that has the `agent` label, which `agent-label.yml` adds,
comes from a branch in this repository, not a fork, merges into `main`, and
wasn't opened by Dependabot. For such a PR:

- **Auto-merge stays off while the PR is a draft**, or while Bugbot hasn't
  finished reviewing its latest commit. A cancelled Bugbot run doesn't count.
  Bugbot gives it the same `neutral` conclusion as a review with findings, so
  the workflow reads the run's summary.
- **A push turns auto-merge off** until Bugbot has reviewed the new commit,
  because GitHub keeps auto-merge on after a push by anyone with write access.
- **While "Allow auto-merge" is off**, in Settings > General > Pull
  Requests, the workflow neither turns auto-merge on nor merges. It still
  turns auto-merge off after a push, because GitHub doesn't say that turning
  the setting off cancels auto-merge on PRs that already have it.

In review mode, auto-merge waits for the approval `main: review` requires.
The owner can't approve PRs from their own account, so they still merge
those with the admin bypass. A collaborator's approval would merge the PR
without a click, which that approval already allows.

The workflow doesn't:

- **Update a PR that is behind `main`.** `main: checks` requires an
  up-to-date branch, so the PR waits until someone updates it, or until the
  branch-update workflow, the last part of T23, does.
- **Start workflows on `main`.** GitHub makes the merge as
  `github-actions[bot]` and starts no workflows for what `GITHUB_TOKEN` does,
  so CodeQL's analysis of `main` doesn't run after an auto-merged PR.
- **Notice the `agent` label being added.** `agent-label.yml` adds it with
  `GITHUB_TOKEN` too. On PRs #35, #37, and #38 it landed within 2 seconds of
  Bugbot starting, 3 to 6 minutes before Bugbot finished. A PR labelled after
  Bugbot finishes waits until its next push, or until it is marked ready.

To stop one PR from merging, select "Disable auto-merge" on it. To stop all
of them, turn off "Allow auto-merge".

## What still needs the owner

A PR that changes a path in `.github/CODEOWNERS` needs a code owner's
approval in both modes. Those paths include CI and the rulesets
(`.github/`), the commands CI runs (`mise.toml` and `.config/mise/`), the
agent instructions (`.cursor/` and `AGENTS.md`), and the files that configure
checks, dependencies, and module boundaries, such as `biome.json`,
`docs/build.sh`, `Cargo.toml`, and `pyproject.toml`. A change to one of those can weaken a
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
> waits for the owner. Mark the PR ready for review when your work is done,
> because a draft doesn't merge.

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
