---
name: linear-queue
description: >
  Use .github/scripts/linear_queue.sh to read and write the Linear queue of
  work for agents. Use when filing a follow-up or any finding outside your
  own issue, when asked what is next in the queue, and when dispatching an
  issue to a worker.
---

# Linear queue

An operation goes through `.github/scripts/linear_queue.sh` if the queue's
correctness depends on it; everything else goes through the Linear MCP server.
Never write GraphQL by hand. The script needs `LINEAR_API_KEY`, and
`LINEAR_TEAM_KEY` when the workspace has several teams. The top of the script
lists every option, and `docs/linear.md` defines the queue.

| Operation | Path | Why |
| -- | -- | -- |
| List dispatchable issues (`list`, `list --parent`) | script | Encodes the dispatch rule: `agent-ready`, no `needs-person`, not started, no delegate, every blocker Done or Canceled. |
| Read an issue's sub-issues in any state (`children`) | script | Works with only `LINEAR_API_KEY`, when the MCP is unavailable; `list --parent` hides sub-issues that are started or Done. |
| File an issue (`create`), with `--parent` | script | Deduplicates by title, adds `agent-filed`, the `repo` label, and the project. |
| Add blocked-by relations when filing | script | Decides dispatch order. |
| Delegate an issue to Cursor (`delegate`) | script | Starts an agent; looks up the Cursor app user. |
| Read an issue, its comments, or search issues | MCP | Nothing depends on how it is done. |
| Comment, change state, move an existing issue under a parent, edit a description | MCP | Same. |

Find the MCP's tools at run time, because their names change when Linear
updates the server. When the MCP is unavailable, meaning its tools are missing
or report `needsAuth`, still do every queue operation through the script. Skip
each MCP-only step, such as commenting on the issue, and list it under "Needs a
person" or Follow-ups in your PR. `docs/linear.md` says which runs have the
MCP.

## File

Run this for each problem you find outside your own issue, instead of fixing
it:

1. Write the issue from the template in `docs/linear.md` to a file.
2. Run `.github/scripts/linear_queue.sh create --title TITLE
   --description-file FILE`, with `--repo owner/name` for another repository
   and `--parent ISSUE_ID` for a sub-issue, and `--blocked-by ISSUE_ID` for
   each issue that must be Done first. Rerunning with the same title makes no
   duplicate and adds any blocked-by relation the issue lacks.
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

## Children

Run `.github/scripts/linear_queue.sh children ISSUE_ID` to get every sub-issue
of an issue, in any state, as JSON with each one's identifier, title, url,
state, delegate, and labels. It prints `[]` when there are none. Use it, not
`list --parent`, to tell whether an issue has sub-issues at all.

## Delegate

Run `.github/scripts/linear_queue.sh delegate ISSUE_ID` to start a Cursor
cloud agent on an issue from `list`. Before each call, check the limits in
`docs/orchestration.md`: at most 5 open agent PRs and at most 10 running
workers. Delegate nothing while either limit is reached.
