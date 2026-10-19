---
name: linear-queue
description: >
  Use .github/scripts/linear_queue.sh to read and write the Linear queue of
  work for agents. Use when filing a follow-up or any finding outside your
  own issue, when asked what is next in the queue, and when dispatching an
  issue to a worker.
---

# Linear queue

`.github/scripts/linear_queue.sh` is the only way an agent reads or writes the
queue; don't write GraphQL by hand. It needs `LINEAR_API_KEY`, and
`LINEAR_TEAM_KEY` when the workspace has several teams. The top of the script
lists every option, and `docs/linear.md` defines
the queue.

## File

Run this for each problem you find outside your own issue, instead of fixing
it:

1. Write the issue from the template in `docs/linear.md` to a file.
2. Run `.github/scripts/linear_queue.sh create --title TITLE
   --description-file FILE`, with `--repo owner/name` for another repository
   and `--parent ISSUE_ID` for a sub-issue. Rerunning with the same title
   makes no duplicate.
3. Never add `agent-ready` to an issue you file. Only a person does, after
   reading it.
4. Add `--label needs-person` to anything only a person can do or decide.

`create` adds the `agent-filed` label itself, so don't add it by hand. A
person who files an issue by hand doesn't use `create`, and adds no
`agent-filed` label.

## List

Run `.github/scripts/linear_queue.sh list` to get the issues an orchestrator
can dispatch now, as JSON. An issue is listed when it has `agent-ready` and
not `needs-person`, is not started, has no delegate, and every issue blocking
it is Done or Canceled.

## Delegate

Run `.github/scripts/linear_queue.sh delegate ISSUE_ID` to start a Cursor
cloud agent on an issue from `list`. Before each call, check the limits in
`docs/orchestration.md`: at most 5 open agent PRs and at most 10 running
workers. Delegate nothing while either limit is reached.
