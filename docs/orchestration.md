# Orchestrating long-running agent work

An orchestrator is a Cursor cloud agent that dispatches the sub-issues of one
Linear parent issue to worker agents, watches the workers' pull requests
(PRs), and reports to the owner. This page is the standing instruction set for
every orchestrator, and for the owner who starts one. It covers where the
queue is, how an orchestrator starts and dispatches, how to keep spend from
growing without bound, and how to hand an orchestration to a fresh agent. It
doesn't depend on any one project: [Linear](linear.md) holds the task list,
and [auto mode](auto-mode.md) decides how PRs merge.

## Terms

- **Owner**: the person who merges PRs and sets the limits. Usually on a phone.
- **Queue**: the Linear issues that agents work from. It is the only task
  list; see [The queue is Linear](#the-queue-is-linear).
- **Parent issue**: a Linear issue with sub-issues, one per PR
  ([Linear conventions](linear.md#filing-an-issue)).
- **Delegate**: the Linear field that names the agent working an issue.
  Setting it to Cursor starts a cloud agent on that issue.
- **Orchestrator**: the cloud agent described above. It writes no feature
  code.
- **Worker**: a cloud agent that does one issue on one branch and opens one PR.
- **Handoff**: the orchestrator's instructions written as a prompt, which
  starts a fresh orchestrator so the old one's context stops costing money.
- **bcId**: a cloud agent's id, such as `bc-489632bd-...`. Its page is
  `https://cursor.com/agents/<bcId>`.

## Why this design

- Each worker has its own context and PR. In [Cursor's design][cursor],
  workers "don't coordinate with other workers or worry about the big picture".
- The orchestrator writes no feature code, so its context stays small (see
  [Cost](#cost)). That is this page's choice, not a finding of the sources.
- The orchestrator checks each PR against its issue's acceptance criteria
  before the owner sees it. [arXiv 2512.08296][paper] reports error amplification of 4.4 under
  centralized coordination and 17.2 for independent agents.
- The orchestrator launches independent tasks in parallel and sequences
  dependent ones. The paper measured +80.8% on decomposable financial
  reasoning and -39% to -70% on sequential planning. [Anthropic][anthropic]
  wrote that "most coding tasks involve fewer truly parallelizable tasks".

[cursor]: https://cursor.com/blog/scaling-agents
[paper]: https://arxiv.org/abs/2512.08296
[anthropic]: https://www.anthropic.com/engineering/multi-agent-research-system

## The queue is Linear

The queue is Linear, the only list of work for agents.
[Linear conventions](linear.md) defines it, and
`.github/scripts/linear_queue.sh` reads and writes it, as the
[`linear-queue` skill](https://github.com/arjunbhargava/foundation/blob/main/.cursor/skills/linear-queue/SKILL.md)
says. An issue is dispatchable when it has `agent-ready` and not
`needs-person`, is not started, has no delegate, and every issue that blocks
it is Done or Canceled.

An orchestrator's state is therefore in Linear (each issue's state, blocked-by
relations, and delegate) and in GitHub (the open PRs), and a fresh
orchestrator rebuilds it from them. See [Handoff](#handoff).

## Start an orchestrator from Linear

Cursor acts as the orchestrator for a parent issue when either happens:

- The owner delegates to Cursor an issue that has sub-issues.
- Someone comments `@Cursor orchestrate this` on a parent issue.

Delegating an issue that has no sub-issues starts a worker, not an
orchestrator. The orchestrator then does these steps. None of them needs the Linear MCP server,
which a delegated run lacks ([Linear conventions](linear.md#how-agents-reach-linear)):

1. Read this page and the `linear-queue` skill.
2. Run `.github/scripts/linear_queue.sh list --parent PARENT_ID` to get the
   parent's dispatchable sub-issues.
3. [Delegate](#dispatch-by-delegate) each one within the limits.
4. Subscribe to each delegated issue with `subscribe_linear_issue`. When its
   state changes, find its PR with
   `gh pr list --state all --search "ISSUE_ID in:body"`, and subscribe to the
   PR with `subscribe_github_pr`. Then end the turn: events arrive as
   follow-ups, and waiting costs no model tokens.
5. On each event, handle it as in
   [Watching workers](#watching-workers-and-reporting-to-the-owner). After a
   merge, run `list --parent` again and delegate the sub-issues it unblocked.

The orchestrator can't merge a PR for the owner, so it stops dispatching when
every dispatchable sub-issue is in review. It then sends the owner one
message, in Cursor, listing each open PR in merge order with what it needs.
It keeps its subscriptions and ends the turn, and the next merge wakes it to
dispatch what that merge unblocked. It finishes when every sub-issue is Done,
or when each one left is blocked, lacks `agent-ready`, or has `needs-person`;
its last message names each such issue and what it waits for.

Linear marks each sub-issue Done when its PR merges, and the parent stays open
until its sub-issues are done.

## Dispatch by delegate

`.github/scripts/linear_queue.sh delegate ISSUE_ID` sets the issue's delegate
to Cursor. That starts one cloud agent in the repository the issue's `repo`
label names and moves the issue to In Progress (checked in INFRA-6). The
worker's prompt is the issue, so a worker needs no launch message, and it
reports through its PR and its Linear issue, not to the orchestrator.

Before each `delegate`, check the limits in [Cost](#cost): at most 5 open agent
PRs and at most 10 running workers. Count the PRs with
`gh pr list --state open --label agent --json number --jq length`, and the
workers with the `cursor-cloud` `list-cloud-agents` tool, filtered to running
agents. Delegate nothing while either limit is reached; a merge or a finished
worker frees a slot.

## Launch tiers

The owner decided on 2026-10-14 when an orchestrator dispatches a worker
without asking. The queue is Linear. An agent never adds `agent-ready`, so
only work a person has marked ready is dispatched.

| Work | The orchestrator |
|---|---|
| A dispatchable issue in the queue | Delegates it without asking. |
| Essential or useful work whose need is obvious, and cleanup | Files it with `linear_queue.sh create`, without `agent-ready`, for a person to ready. |
| An entirely new feature, or an unrelated initiative | Asks the owner. |
| Work only a person can do or decide | Files it with `needs-person`. |

If the next task is obvious and needs no human input, the orchestrator does it.
It doesn't ask the owner about queued work: it makes the call and says what it
decided in its next message.
Every tier keeps the limits in [Cost](#cost): at most 5 open agent PRs, at most
10 running workers, nothing new within $50 of the daily limit, and, for API
launches, the [model routing](#which-model).

## Launching through the API instead

[Dispatch by delegate](#dispatch-by-delegate) is the default. Launch a worker
or orchestrator through the Cursor API only for work that has no Linear issue,
for a relaunch from a branch, and for a successor orchestrator in a
[handoff](#handoff). Launch it as a top-level cloud agent. Do not use a
subagent for a task that produces a PR.

- A top-level agent has its own bcId, page, transcript, branch, and PR. The
  owner can open it, read it, and stop it. A subagent runs inside the
  orchestrator's run, so the owner sees it only through the orchestrator's
  transcript.
- A top-level agent has its own context. Its cost doesn't grow the
  orchestrator's context (see [Cost](#cost)).

Use a subagent only for a short, read-only question whose answer is a few
lines, such as "which files call this function". If the answer would be
longer than the question that asked it, launch a worker instead.

```sh
jq -n --rawfile prompt worker-prompt.md --arg name "$worker_name" '{
  name: $name,
  prompt: {text: $prompt},
  model: {id: "claude-sonnet-5-5",
          params: [{id: "reasoning_effort", value: "high"}]},
  repos: [{url: "https://github.com/<owner>/<repository>",
           startingRef: "main"}],
  autoCreatePR: true
}' | curl -s -u "$CURSOR_API_KEY:" -H 'Content-Type: application/json' \
       -d @- https://api.cursor.com/v1/agents
```

- Build the body with `jq --rawfile`, so that the prompt's quotes and
  newlines are escaped. `CURSOR_API_KEY` is a cloud agent secret; never print
  it.
- `name` is the worker's display name in Cursor's agent list, set as in
  [Naming agents](#naming-agents). Without it, Cursor derives a name from the
  prompt.
- `startingRef` is the branch the worker starts from. A stacked PR starts from
  `main` after the PR below it merges.
- Send a follow-up to a worker with
  `POST https://api.cursor.com/v1/agents/<bcId>/runs` and
  `{"prompt": {"text": "..."}}`. The API answers `agent_busy` while the worker
  has an active run. Retry every 20 to 30 seconds, in a shell loop in a tmux
  session, which costs no model tokens.
- Record each launch where the owner can find it: put the worker's task,
  bcId, and page URL in the orchestrator's next message to the owner.
- Cursor's documentation doesn't say whether API-launched agents show in the
  sidebar list. The owner has seen them disappear when deselected. Until
  that's solved, the links in the orchestrator's messages are the way to open
  a worker.

### Naming agents

`POST /v1/agents` accepts an optional `name`, a display name of at most 100
characters. Set it on every launch, so the owner can tell orchestrators and
workers apart by time and order in Cursor's agent list. `mise run spend`
shows each run's name in its "Task" column, so the name also labels the spend
report.

- **Orchestrator**: `Orchestrator <MM/DD HH:MMZ>: <short descriptor>`, for
  example `Orchestrator 10/15 00:21Z: issue queue`.
- **Worker**: `Worker <MM/DD HH:MMZ>: <short descriptor>`, for example
  `Worker 10/15 00:18Z: document agent names`. The descriptor is a few
  plain words saying what the worker does. It is not the task ID, which stays
  in the worker's prompt and PR. The name doesn't include its orchestrator's.
  A relaunched worker, or a worker launched for a follow-up, gets a new launch
  time.
- **Date and time** is the agent's UTC launch time to the minute, with the
  date as `MM/DD` with no year, so names sort by time. A time
  stamp rather than a counter means nothing has to be remembered through a
  [handoff](#handoff).
- **Length**: at most 100 characters in total, the API's limit for `name`.
- **First orchestrator**: an orchestrator that the owner starts renames itself
  in its first step with the `cursor-cloud` `rename-chat` tool.

Agents launched before this scheme keep their old names.

### Which model

These are the defaults for API launches; `linear_queue.sh delegate` takes no
model, so the Cursor dashboard's default applies to a delegated worker. A
project may route other models by the scope of the work; record each addition
in this table.

| Task | Model id | Parameters |
|---|---|---|
| Design work: plans, rulesets, CI security, changes spanning several areas | `claude-opus-5-5` | `effort=medium`, `fast=false` |
| Extremely challenging or confusing feature | `claude-opus-5-5` | `effort=xhigh`, `fast=false` |
| Routine work with checkable acceptance criteria | `claude-sonnet-5-5` | `reasoning_effort=high` |
| Orchestrator | `claude-sonnet-5-5` | `reasoning_effort=high` |

The Opus API parameters are
`"model":{"id":"claude-opus-5-5","params":[{"id":"effort","value":"medium"},{"id":"fast","value":"false"}]}`.
`effort=xhigh` is reserved for an extremely challenging or confusing feature.
The orchestrator says why in its launch message to the owner.

A Sonnet worker that fails twice on the same CI failure or Bugbot finding is
relaunched on Opus at `effort=medium` from its branch, unless the failure
itself looks confusing, in which case it is relaunched at `effort=xhigh`. Do
not start on Opus "to be safe". In one project's `mise run spend` report for
the 7 days to 2026-10-12, each Opus worker, run at `effort=xhigh`, cost $9 to
$16, and a Sonnet orchestrator cost $11.54 over 38 events.

### What a worker prompt contains

This section applies to API launches. A delegated worker's prompt is its Linear
issue, so the issue holds the same things (a person's request to review goes in
the issue text). A worker prompt is short, because the worker reads the
repository itself.

1. The task, as a pointer to its issue ID, plus any fact a
   reader of the issue wouldn't have (decisions made in chat).
2. "Done when": the checkable acceptance criteria.
3. For auto mode, the review-thread instruction in
   [auto-mode.md](auto-mode.md).
4. If a person asked to review the task's PR, this line: "Add the
   `needs-human-review` label to your PR; a person reviews it before it
   merges." AGENTS.md says when a worker adds the label on its own.
5. The report-back instruction: wait for CI and the Cursor Bugbot check on the
   final commit, fix or answer each finding, then
   `POST {"prompt":{"text":"<task> worker on branch <b>: <PR URL or blocker>"}}`
   to `https://api.cursor.com/v1/agents/<orchestrator bcId>/runs`, retrying
   every 60 seconds on `409 agent_busy` for up to 30 minutes.

The orchestrator finds its own bcId with the `cursor-cloud` `run-info` tool.

## Cost

A cloud agent's cost is dominated by cache-read tokens: on each step, the
model re-reads its whole context. A long-lived agent therefore costs more per
step as its context grows. In that report, the orchestrator that ran 38
events read about 13.3 million cache-read tokens, about 350,000 per event. The rules below keep each context short and each wait free.

- **Hand off, don't grow.** Start a fresh orchestrator after about 5 merges,
  or when the context is large, whichever comes first (see
  [Handoff](#handoff)).
- **Wait without the model.** After subscribing to a PR with
  `subscribe_github_pr`, end the turn. Events arrive as follow-ups. Don't poll
  GitHub in a loop of model steps. Ignore routine push, ready-for-review,
  and synchronize events.
- **Read only what a decision needs.** Use the PR's JSON and file list. Read
  a full diff only for owned paths (the paths in `.github/CODEOWNERS`) and
  for anything that changes rules or policy.
- **Keep prompts short** and point to files instead of pasting them.
- **Limit concurrency.** Keep the open agent PRs within the project's
  limit (5 by default), because the owner's review time is the bottleneck.
  Also keep at most 10 workers running at once, of any model. The owner
  decided this on 2026-10-14 and expects to reach it rarely. The owner raises
  it for very ambitious or complex work, because splitting such work across
  more workers keeps each context short and lowers cost. Raising it does not
  raise the open-PR limit (D9 in [the template plan](https://github.com/arjunbhargava/foundation/blob/main/docs/template-plan.md)).
- **Check spend at each pause**, and tell the owner the totals:
  `mise run spend -- --since "$(date -u +%F)"`. The "All N cloud agent
  runs" total counts every repository's agents; this
  repository's spend is at most its "Repository" row plus the "Repository
  unknown" row, which holds runs the agent listing lacks (both need
  `CURSOR_API_KEY`). `/teams/spend` must be compared as `spendCents` plus
  `includedSpendCents`.
- **The real cap is in the Cursor dashboard.** The repository can't stop a run
  partway through. The starting limit is $500 per day across cloud agent
  runs (see [auto mode's limits](auto-mode.md#limits)). When the day's total
  is within $50 of the limit, launch nothing new and ask the owner.
- **Compute jobs on other machines** follow the `compute-cost` rule, not this
  page.

## Watching workers and reporting to the owner

- **One PR per worker, one subscription per PR.** Subscribe when the PR
  appears, as in [Start an orchestrator from Linear](#start-an-orchestrator-from-linear).
  The subscription closes itself when the PR merges.
- **After each merge**, run `list --parent` again and delegate what the merge
  unblocked, which starts from the new `main`. If another open PR now
  conflicts with `main`, ask its worker to merge `origin/main` with a merge
  commit, by mentioning `@Cursor` in a comment on its Linear issue.
- **Before launching two workers whose PRs may touch the same files**, test
  them with `git merge-tree --write-tree --name-only <branchA> <branchB>`.
- **A worker with no PR.** If an issue has been In Progress for 30 minutes
  without a PR, look up its agent with `list-cloud-agents` and read its page.
  The PR and the issue are the record, not a report from the worker.
- **Before telling the owner a PR is ready**, check it against its "Done
  when". Say: head SHA, CI result, size, what changed, decisions needed,
  merge order, and conflicts with other open PRs. Say plainly what you did
  not check.
- **Owner messages** are short, written for a phone, and number each manual
  step with its URL, tap by tap. Tell the owner once per batch of PRs that
  need the owner's merge, in one numbered list, not one message per PR. A PR
  whose body has nothing under "Needs a person" needs nothing from the owner
  beyond that merge.
- **In auto mode**, a worker resolves a Bugbot thread only after fixing it. A
  disputed thread stays open for the owner. The orchestrator never merges a
  PR or enables auto-merge itself.

## Handoff

Hand off when the [cost rules](#cost) say so, or when the orchestrator has
finished the work it was given. Linear and GitHub hold the queue and the
state, so the handoff prompt carries neither. It is a prompt for a fresh
Sonnet orchestrator, in this order:

1. **Role and read-first list**: this page, `AGENTS.md`, and the `linear-queue`
   skill. Nothing else up front.
2. **The parent issue**, as its ID, such as `INFRA-38`. The successor rebuilds
   the state from `list --parent`, the sub-issues' states in Linear, and
   `gh pr list --state open --label agent`, then subscribes to each open PR,
   because a subscription belongs to the agent that made it.
3. **Decisions already made in chat** that no issue records, so the new
   orchestrator doesn't ask again. Put a decision in a comment on the issue it
   concerns where you can.
4. **Standing rules that this page doesn't hold.**

The outgoing orchestrator launches the successor through the API with `name`
set to the successor's own launch time and a descriptor, as in
[Naming agents](#naming-agents), so no model step is needed. Workers need no
message, because they report through their PRs and issues. Then stop. Don't
contact the previous orchestrator from the new one.

The handoff lives in chat, not in the repository: it changes with every
merge, and a committed copy would be out of date within an hour and add a PR
for the owner to review. This page holds what doesn't change.

## Failure modes seen so far

- **API token expiry.** The `gh` token may expire after about an hour. For
  read-only PR information, use the public REST API with `curl` instead. It
  is rate limited per IP address and sometimes answers "rate limit exceeded";
  when it does, use `gh` if its token still works.
- **A merge by auto-merge starts no workflows on `main`**, so CodeQL on `main`
  goes stale until a GitHub App token exists for the repository.
- **A Sonnet worker stuck on one finding** costs more each retry; relaunch on
  Opus at `effort=medium` after the second failure, through the API, since a
  delegate carries no model.
- **A stale branch.** GitHub has shown a PR as "clean" while behind `main`.
  The owner's checklist includes confirming the Merge button on such a
  branch.

## Decisions still open

| # | Question | Proposed default |
|---|---|---|
| O1 | Where the owner sees a list of API-launched workers that survives deselecting them (a delegated worker shows on its Linear issue) | Links in each orchestrator message now; a Slack message or a pinned issue per launch once the owner picks one |
