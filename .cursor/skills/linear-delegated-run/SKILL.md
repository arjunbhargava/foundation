---
name: linear-delegated-run
description: >
  Decide the role of a run that Linear started by delegating an issue, and
  follow it: a parent issue's run is an orchestrator that dispatches its
  sub-issues, any other run is a worker that passes a pre-flight before it
  writes code. Use in the first step of a run whose `run-info` source is
  `linear`, before writing code or launching any agent.
---

# Linear delegated run

`docs/linear-delegation.md` explains why a delegated run has a role. This
file holds the commands. `ISSUE_ID` below is the ID of the delegated issue, as
the run's prompt gives it, such as `ENG-12`. The run's other first step,
renaming itself, is in `docs/agent-naming.md`.

The Linear MCP is usually unavailable to a delegated run (see
`docs/linear-delegation.md`). Each step below that needs it says what to do
instead.

## Role check

```sh
.github/scripts/linear_queue.sh children ISSUE_ID
```

- `[]`: the issue has no sub-issues. The run is a [worker](#worker).
- A non-empty array: the issue is a parent. The run is an
  [orchestrator](#orchestrator).

## Worker

1. Run the [pre-flight](#worker-pre-flight). If a check fails, stop.
2. Do the issue. A worker launches no other agent.
3. Open one PR whose description says `Fixes ISSUE_ID`.

### Worker pre-flight

Run all four checks before writing code or creating a branch, so a failure
leaves nothing to clean up. Do not count the run itself: it has no PR yet, and
its own `bcId`, from the `run-info` tool, is excluded from the worker count.

1. **Limits.** These are the limits in `docs/orchestration.md` ("Cost"). The
   check fails when either count is at its limit:
   - Open agent PRs, at most 5. An agent PR is one from a `cursor/` branch:

     ```sh
     gh pr list --state open --limit 1000 --json headRefName \
       --jq '[.[] | select(.headRefName | startswith("cursor/"))] | length'
     ```

   - Running workers, at most 10. Call the `cursor-cloud` `list-cloud-agents`
     tool with `statuses: ["RUNNING"]` and `limit: 200`, and count the
     agents whose name starts with `Worker`, except this run. A parent
     issue's orchestrator has that name too, as `docs/agent-naming.md`
     gives every Linear-delegated run the same form, so a worker counts the
     orchestrator that dispatched it.
2. **Open PRs on the same files.** List the files you expect to change from
   the issue's acceptance criteria. Then list each open PR's files:

   ```sh
   gh pr list --state open --limit 1000 --json number,headRefName,files \
     --jq '.[] | {number, headRefName, paths: [.files[].path]}'
   ```

   The check fails when an open PR changes a file you expect to change.
   Name the PR and the file in the failure. For each such PR, run
   `git fetch origin <headRefName>` and then
   `git merge-tree --write-tree --name-only origin/main origin/<headRefName>`
   and report its output, because a PR that already conflicts with `main`
   will be reworked before it merges.
3. **Blockers.** Read the issue with the Linear MCP's issue tool, including
   its relations. The check fails when any issue blocking it is not Done or
   Canceled. Without the MCP, the check cannot run: do not count it as a
   failure, and list "blockers not checked" under "Needs a person" in your
   report.
4. **Still ready.** Read the issue's labels in the same call. The check fails
   when `agent-ready` is missing or `needs-person` is present. Without the
   MCP, list "labels not checked" under "Needs a person", as for check 3.

When a check fails, stop without opening a PR:

- With the MCP, comment on the issue with its save-comment tool, naming the
  check that failed and why, with the counts or PR numbers it found.
- Without the MCP, end your final message with the same text under "Needs a
  person". Linear shows no comment, so the owner finds the run through its
  page in Cursor.

## Orchestrator

An orchestrator writes no feature code and never does a sub-issue's work,
including a small one. Each sub-issue gets its own worker and PR.

1. List the sub-issues that can be dispatched now:

   ```sh
   .github/scripts/linear_queue.sh list --parent ISSUE_ID
   ```

   `list` returns only issues that have `agent-ready`, not `needs-person`,
   are not started, have no delegate, and whose blockers are all Done or
   Canceled.
2. When `list` returns `[]`, report that and stop, with no PR. Use the
   `children` output to say why: for each sub-issue, its state, whether it
   has `agent-ready`, and its delegate. For example, "ENG-13 and ENG-14 lack
   `agent-ready`, so I delegated nothing." Post it as a comment on
   `ISSUE_ID` with the MCP, or as your final message without it.
3. Otherwise delegate each listed issue in order:

   ```sh
   .github/scripts/linear_queue.sh delegate SUB_ISSUE_ID
   ```

   Before each call, run both limit counts from the worker pre-flight, check
   1. Count this run in the running-workers count, because each worker you
   dispatch will count it. Add the issues you have already delegated in this
   run, because a new worker takes a moment to show as running. Delegate nothing while either count is at its limit.
4. Report which sub-issues you delegated and which are still waiting, and
   why, in the same way as step 2. To dispatch the waiting ones later, a
   person mentions `@Cursor` in a comment on `ISSUE_ID`, which starts a new
   orchestrator. `list` skips every sub-issue that already has a delegate, so
   nothing is delegated twice.
5. If the orchestrator opens a PR at all, its description says
   `Part of ISSUE_ID`, never `Fixes`, because Linear would mark the parent
   done when that PR merges, while its sub-issues are still open.
