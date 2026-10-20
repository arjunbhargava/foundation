# Linear conventions

Work is planned as Linear issues, and Cursor cloud agents turn each issue into
one pull request (PR). This page is for people and agents who file or pick up
issues. The repository owner sets up the Linear and Cursor settings
these conventions rely on.

## Filing an issue

- Start every issue from the issue template below. Write each acceptance
  criterion as behaviour someone can check, because each one becomes a named
  test in the PR.
- Split work that needs several PRs into a parent issue with one sub-issue
  per PR, each sub-issue from the template. Linear marks an issue done when
  every PR linked to it has merged, and the next PR in a stack is usually not
  open when the first merges, so one shared issue would close after the first
  PR. The parent stays open until its sub-issues are done.
- Each Linear project carries a label from the `repo` label group, named
  after its repository as `owner/name`, for example
  `arjunbhargava/foundation`. Cursor takes an issue's repository from the
  first of: `[repo=owner/name]` in the issue text, a `repo` label on the
  issue, a `repo` label on its project, or the default repository in the
  Cursor dashboard
  ([Cursor docs](https://cursor.com/docs/integrations/linear#repository-selection)).
- Linear keeps issue labels and project labels apart, so the `repo` group
  exists in both. A new repository made from this template adds its label to
  both groups, then puts it on its Linear projects. If Linear's or Cursor's
  GitHub app has access only to selected repositories, add the new one there
  too.

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

So the script must work with only the API key, and an agent uses the MCP when
its tools are present and skips its MCP-only steps when they are not, as the
skill says.

| Run started by | `LINEAR_API_KEY` | Linear MCP | Checked |
| -- | -- | -- | -- |
| Cursor | Injected (verified) | Not available in a run that was already running when the owner authorized it; unverified for a run started afterwards | 2026-10-19 |
| Linear delegation | Injected (verified) | Available in two runs started after the owner authorized it: `get_issue` and `list_issues` returned data, with no `needsAuth` and no `mcp_auth_error` event ([INFRA-53 run](https://cursor.com/agents/bc-c188ed5c-8e9e-4d08-843e-393a410d6498) and [INFRA-72 run](https://cursor.com/agents/bc-2353985e-19db-49bf-930b-7f64fd88f15d)). Not available in the 2026-10-19 run for INFRA-57: `needsAuth` and an `mcp_auth_error` event | 2026-10-20 (2026-10-19 for INFRA-57) |
| Automation | Unverified | Unverified | |
| API | Unverified | Unverified | |
| Slack | Unverified | Unverified | |

Findings:

- 2026-10-19, run started from Cursor: the owner authorized the MCP mid-run,
  and the run still reported it as `needsAuth` twice afterwards. A running
  agent does not pick up a new authorization.
- 2026-10-19, run started by delegating INFRA-57 in Linear
  ([run](https://cursor.com/agents/bc-baf5f1e6-5af3-404c-97b8-f75434a94d6b),
  source `linear`): its events held one `mcp_auth_error` for "Linear", and
  its Linear MCP namespace reported `needsAuth` with no tools. The run had
  `LINEAR_API_KEY`. The owner had authorized the MCP earlier the same day,
  but it is not known whether the authorization was in place when this run
  started.
- 2026-10-20, two runs started by delegation from Linear (source `linear`):
  the run for INFRA-53
  ([run](https://cursor.com/agents/bc-c188ed5c-8e9e-4d08-843e-393a410d6498))
  and the run for INFRA-72, which made this correction
  ([run](https://cursor.com/agents/bc-2353985e-19db-49bf-930b-7f64fd88f15d)).
  In both, `get_issue` and `list_issues` returned data and `needsAuth` did
  not appear. The INFRA-72 run's events were empty, so it had no
  `mcp_auth_error`.
- Both observations hold, and one explanation fits both: a delegated run has
  the MCP when the owner's authorization was in place before the run started,
  as in a run started from Cursor. This is not confirmed. If a later
  delegated run reports `needsAuth` although the owner had authorized the MCP
  before it started, the rule is wrong, and this table needs a new row.
- A delegated run therefore uses the MCP when its tools are present, and
  skips MCP-only steps when they are not. Queue operations always go through
  the script.

### Decision: no static header for the Linear MCP

Decided on 2026-10-19 by the owner in
[INFRA-58](https://linear.app/tri-replicator/issue/INFRA-58): the team does
not add a static `Authorization` header for the Linear MCP, so an unattended
run, such as one started by Linear delegation, has the MCP only through the
owner's authorization, and skips MCP-only steps when it lacks it. A delegated
run can always reach Linear through `LINEAR_API_KEY`. Linear still marks an issue done when its PR merges,
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

## Issue template

Paste this template into Linear under Settings > Templates. The line under each
heading is a hint for the person filing the issue; mark it as placeholder
text in Linear's template editor.

```markdown
## Goal

What this issue achieves and why, in one or two sentences.

## Acceptance criteria

- [ ] Behaviour someone can check, for example: `mise run lint` fails when a public function has no doc comment.

## Verification command

The command that checks every criterion, for example `mise run test`.

## Out of scope

What this issue deliberately leaves out.

## Compute budget

The most this issue may spend on compute jobs, in US dollars, or 0 if it launches none.

## Designs

Links to designs, plans, or related issues. Delete this section when there are none.
```
