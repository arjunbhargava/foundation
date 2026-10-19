---
name: orchestrate
description: >
  Coordinate other cloud agents: dispatch a parent issue's Linear sub-issues
  to workers, watch their pull requests, report to the owner, and hand off to
  a fresh orchestrator. Use when asked to orchestrate, coordinate, or manage
  agents, when delegated an issue that has sub-issues, when a comment says
  `@Cursor orchestrate this`, and before launching any worker. Read
  `docs/orchestration.md` first.
---

# Orchestrate

Read `docs/orchestration.md` in full before you launch or message any agent.
It holds the procedure; this file only says when it applies and what you must
not forget.

- Being delegated an issue that has sub-issues, or being asked in a comment
  (`@Cursor orchestrate this`), makes you the orchestrator for that parent
  issue. Dispatch its sub-issues from the Linear queue: list them with
  `.github/scripts/linear_queue.sh list --parent PARENT_ID` and delegate each
  with `delegate`, as the `linear-queue` skill says, instead of repeating its
  commands here. Delegate only within 5 open agent PRs and 10 running
  workers.
- Wait for events with `subscribe_linear_issue` and `subscribe_github_pr`
  instead of polling, and end the turn while waiting. After a merge, list the
  parent's sub-issues again and dispatch what the merge unblocked.
- Never merge for the owner. In auto mode, a PR that changes no owned path
  merges itself, and the merge unblocks the next sub-issues. When every
  dispatchable sub-issue is in review, send the owner one message listing only
  the PRs auto mode holds (an owned path, `needs-human-review`, or an open
  review thread), in merge order, and end the turn.
- Hand off to a fresh orchestrator after about 5 merges or when your context
  is large, because each step re-reads the whole context and costs more as it
  grows. The handoff names the parent issue; Linear and GitHub hold the state.
- Check spend at each pause with `mise run spend`, and stop launching near the
  dashboard limit.
- Never merge a PR or enable auto-merge yourself.
