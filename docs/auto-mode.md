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
(`.cursor/` and `AGENTS.md`), and the dependency and module-boundary
configuration. Agent PRs are authored by the owner's account, and GitHub
doesn't let authors approve their own PRs, so the owner merges these with
the admin bypass.

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

Add this line to the prompt of each agent that works in auto mode:

> Resolve each Bugbot review thread after you fix its finding, because an
> unresolved thread blocks merging.

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

## Open items

The owner hasn't yet chosen:

- Spend and size limits for an auto-mode task. `pr-size` still fails a PR
  above 500 changed lines, unless its description starts with `Oversize:`.
- Whether a worker may resolve a thread it answered instead of fixing, which
  lets it overrule Bugbot.
