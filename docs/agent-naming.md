# Naming agents

Every cloud agent gets a display name that says its role and when it was
launched, so the owner can tell orchestrators and workers apart by time and
order in Cursor's agent list. `mise run spend` shows each run's name in its
"Task" column, so the name also labels the spend report. Both entrypoints use
this scheme: [Orchestrating agents from Cursor](orchestration.md) and
[Delegating Linear issues to agents](linear-delegation.md).

## Who sets the name

| Agent | Started by | Named by | How |
|---|---|---|---|
| First orchestrator | The owner, in Cursor | Itself, in its first step | The `cursor-cloud` `rename-chat` tool |
| Successor orchestrator | The outgoing orchestrator, at [handoff](orchestration.md#handoff) | The outgoing orchestrator | `name` in `POST /v1/agents` |
| Worker launched through the API | An orchestrator | The orchestrator | `name` in `POST /v1/agents` |
| Run started by Linear delegation | Linear, when the owner or an orchestrator delegates an issue | Itself, in its first step | The `cursor-cloud` `rename-chat` tool |

`POST /v1/agents` accepts an optional `name`, a display name of at most 100
characters. Set it on every launch; without it, Cursor derives a name from
the prompt. Cursor names a run started by Linear delegation with a few words
of its own choosing, such as `Ci filter missing files`, and has no setting or
`[key=value]` option for the name, which is why that run renames itself.

## Name forms

- **Orchestrator**: `Orchestrator <MM/DD HH:MMZ>: <short descriptor>`, for
  example `Orchestrator 10/15 00:21Z: issue queue`.
- **Worker launched through the API**: `Worker <MM/DD HH:MMZ>: <short
  descriptor>`, for example `Worker 10/15 00:18Z: document agent names`. The
  descriptor is a few plain words saying what the worker does. It is not the
  task ID, which stays in the worker's prompt and PR. The name doesn't
  include its orchestrator's. A relaunched worker, or a worker launched for a
  follow-up, gets a new launch time.
- **Run started by Linear delegation**:
  `Worker <MM/DD HH:MMZ>: <issue ID> <issue title>`, for example
  `Worker 10/19 21:04Z: INFRA-61 Narrow the CI Python filter`. The time is
  the run's `createdAtMs` from `run-info`, and the issue ID and title come
  from the issue in its prompt. Unlike an orchestrator's worker, the name
  includes the issue ID, because no orchestrator message links the run to
  its issue. A title that would take the name past 100 characters is cut to
  fit.

In every form:

- **Date and time** is the agent's UTC launch time to the minute, with the
  date as `MM/DD` with no year, so names sort by time. A time stamp rather
  than a counter means nothing has to be remembered through a
  [handoff](orchestration.md#handoff).
- **Length**: at most 100 characters in total, the API's limit for `name`.

Agents launched before this scheme keep their old names.
