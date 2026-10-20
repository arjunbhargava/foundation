# Delegating Linear issues to agents

The owner starts the work by delegating an `agent-ready` Linear issue to
Cursor. Cursor, not an orchestrator, launches the worker: one cloud agent per
delegated issue, which opens one pull request (PR). This page is for the owner
who delegates and the agents that run delegated issues. When the owner starts
an orchestrator by hand in Cursor instead, [orchestration](orchestration.md)
applies, and it also holds what both entrypoints share: the
[agent naming scheme](orchestration.md#naming-agents), the
[limits](orchestration.md#cost), and the [handoff](orchestration.md#handoff).
[Linear conventions](linear.md) says how to file the issue and holds its
template.

## Handing an issue to an agent

- A person adds the `agent-ready` label when the template is filled in,
  everything the issue needs has merged, and any plan the change needs
  is approved, if the `plan` skill says it needs approval. Sub-issues don't inherit labels, so
  add it to each sub-issue.
- Delegate only `agent-ready` issues to Cursor: pick Cursor in the assignee
  field, or mention `@Cursor` in a comment. Linear keeps the person as the
  assignee and records Cursor as the delegate.
- The agent names itself from the issue's ID and title, as
  [Naming agents](orchestration.md#naming-agents) says, so the issue title
  you write is the agent's name in Cursor's agent list and in
  `mise run spend`. To name a running agent differently, mention `@Cursor`
  in a comment asking for the new name.
- Each delegated issue becomes one agent, one branch, and one PR. The PR
  description includes `Fixes <issue ID>`, for example `Fixes ENG-123`, as
  `.github/pull_request_template.md` asks. Linear links the PR to that issue,
  or sub-issue, and marks it done when the PR merges.
- An agent lists a problem outside its issue under Follow-ups instead of
  fixing it; any issue it files uses the template, without `agent-ready`.

## How agents reach Linear

Agents use two paths, split by one rule: an operation goes through
`.github/scripts/linear_queue.sh` if the queue's correctness depends on it
(which issues are dispatchable, filing without duplicates, parent and
blocked-by links, and the delegate), and every other operation goes through
the Linear MCP server. The
[`linear-queue` skill](https://github.com/arjunbhargava/foundation/blob/main/.cursor/skills/linear-queue/SKILL.md)
lists each operation and its path.

The two paths use different credentials:

- `LINEAR_API_KEY` is a Cursor secret, injected as an environment variable
  into every new cloud agent, whatever started it. The script uses it.
- Linear MCP OAuth belongs to one Cursor user, not to a chat or a device
  ([Cloud Agent capabilities](https://cursor.com/docs/cloud-agent/capabilities.md)).
  A run whose MCP is not authorized gets the event `mcp_auth_error`, skips
  the MCP's tools, and keeps running.

So the script must work with only the API key, and an agent without the MCP
skips its MCP-only steps, as the skill says.

| Run started by | `LINEAR_API_KEY` | Linear MCP | Checked |
| -- | -- | -- | -- |
| Cursor | Injected (verified) | Not available in a run that was already running when the owner authorized it; unverified for a run started afterwards | 2026-10-19 |
| Linear delegation | Injected (verified) | Not available: `needsAuth` and an `mcp_auth_error` event | 2026-10-19 |
| Automation | Unverified | Unverified | |
| API | Unverified | Unverified | |
| Slack | Unverified | Unverified | |

Findings from 2026-10-19:

- In a run started from Cursor, the owner authorized the MCP mid-run, and the
  run still reported it as `needsAuth` twice afterwards. A running agent does
  not pick up a new authorization.
- The run that wrote this section was started by delegating INFRA-57 in
  Linear
  ([run](https://cursor.com/agents/bc-baf5f1e6-5af3-404c-97b8-f75434a94d6b),
  source `linear`). Its events held one `mcp_auth_error` for "Linear", and
  its Linear MCP namespace reported `needsAuth` with no tools. The run's
  owner had authorized the MCP earlier the same day, so a delegated run
  does not appear to inherit the owner's authorization. The run did have
  `LINEAR_API_KEY`. INFRA-57 is not a trivial issue, and the check was one run, so
  repeat it on a trivial issue before relying on it.
- Delegated workers therefore skip MCP-only steps.

### Decision: no static header for the Linear MCP

Decided on 2026-10-19 by the owner in
[INFRA-58](https://linear.app/tri-replicator/issue/INFRA-58): the team does
not add a static `Authorization` header for the Linear MCP, so unattended
runs, such as those started by Linear delegation, keep skipping MCP-only
steps. A delegated run can still reach Linear through `LINEAR_API_KEY`,
which it always has. Linear still marks an issue done when its PR merges,
because the PR description holds `Fixes <issue ID>`.

- **Why not:** the header would be a second copy of `LINEAR_API_KEY`, stored
  in Cursor's team MCP settings, and the MCP only adds ready-made tools for
  operations the key already allows. It is also unconfirmed that a managed
  MCP server accepts a custom header, or that a Linear-delegated run uses
  team-level MCP servers.
- **If needed later:** on 2026-10-19, `https://mcp.linear.app/mcp` accepted
  `LINEAR_API_KEY` as a bearer token: `initialize` returned HTTP 200 and
  `tools/list` returned the issue and comment tools, including `save_issue`
  and `save_comment`. A made-up token got HTTP 401 `invalid_token`. No write
  tool was called. So a custom team MCP server with
  `Authorization: Bearer <LINEAR_API_KEY>` should work, and a delegated
  run's events must then hold no `mcp_auth_error`. Rotating the key would
  mean changing both copies.
