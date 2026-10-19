# Linear conventions

Work is planned as Linear issues, and Cursor cloud agents turn each issue into
one pull request (PR). This page is for people and agents who file or pick up
issues. The repository owner sets up the Linear and Cursor settings
these conventions rely on (task T17 in [the template plan](https://github.com/arjunbhargava/foundation/blob/main/docs/template-plan.md)).

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
  (decision D7 in the plan) is approved, if the `plan` skill says it needs
  approval. Sub-issues don't inherit labels, so
  add it to each sub-issue.
- Delegate only `agent-ready` issues to Cursor: pick Cursor in the assignee
  field, or mention `@Cursor` in a comment. Linear keeps the person as the
  assignee and records Cursor as the delegate.
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
- Delegated workers skip MCP-only steps until the header below is added.

### Decision: unattended runs get the MCP through a static header

Decided on 2026-10-19 by the owner in
[INFRA-58](https://linear.app/tri-replicator/issue/INFRA-58): unattended
runs, such as those started by Linear delegation, should be authorized for
the Linear MCP server. The only way to do that without a person's OAuth is a
static `Authorization` header in Cursor's team MCP settings, so the team
adds one for the Linear server.

- **Header:** `Authorization: Bearer <value of LINEAR_API_KEY>`.
- **Works:** on 2026-10-19, `https://mcp.linear.app/mcp` accepted
  `LINEAR_API_KEY` as the bearer token: `initialize` returned HTTP 200 and
  `tools/list` returned the issue and comment tools, including `save_issue`
  and `save_comment`. A made-up token got HTTP 401 `invalid_token`. No write
  tool was called.
- **Cost:** the header is a second copy of `LINEAR_API_KEY`, stored in
  Cursor's team MCP settings instead of the Cursor secrets. Rotating the key
  means changing both. Comments and state changes made through the MCP are
  attributed to the key's owner.
- **Not yet done:** a person must add the header in the Cursor dashboard,
  because an agent can't change team settings. Until it is added and a
  delegated run's events hold no `mcp_auth_error`, agents still skip
  MCP-only steps, as the skill says. [OI-36](open-items.md) tracks it.

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
