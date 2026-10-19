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
  PR. The parent stays open until its sub-issues are done. Make each
  "blocked by" relation with `linear_queue.sh create --blocked-by`, so that
  the queue holds a sub-issue until its blockers are Done.
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

Labels that decide whether an agent may take an issue:

| Label | Meaning | Who adds it |
| -- | -- | -- |
| `agent-ready` | The issue is fully specified, so an agent may work on it. | A person, after reading the issue. An agent never adds it. |
| `needs-person` | Only a person can do or decide this. The queue never dispatches it. | The agent that files the issue, with `create --label needs-person`, or a person. |
| `agent-filed` | An agent filed the issue. Linear shows the owner as creator of everything an agent makes through the owner's API key, so this label is the only record. | `linear_queue.sh create`, always. |

- A person adds `agent-ready` when the template is filled in and any plan the
  change needs (decision D7 in the plan) is approved, if the `plan` skill says
  it needs approval. The issue need not wait for the issues it depends on to
  merge: a "blocked by" relation holds it out of the queue until they are
  Done or Canceled. Sub-issues don't inherit labels, so add `agent-ready` to
  each sub-issue.
- The queue is the issues `linear_queue.sh list` prints: `agent-ready`, not
  `needs-person`, not started, no delegate, and every blocker Done or
  Canceled. `list --parent ISSUE_ID` restricts it to one parent's
  sub-issues.
- Delegate only `agent-ready` issues to Cursor: pick Cursor in the assignee
  field, or mention `@Cursor` in a comment. Linear keeps the person as the
  assignee and records Cursor as the delegate. An orchestrator delegates
  through `linear_queue.sh delegate`, which sets the same field through the
  API. Setting the delegate through the API starts a Cursor agent, moves the
  issue to In Progress, and gives the agent the issue and `LINEAR_API_KEY`
  (checked in [INFRA-6](https://linear.app/tri-replicator/issue/INFRA-6)).
- Each delegated issue becomes one agent, one branch, and one PR. The PR
  description includes `Fixes <issue ID>`, for example `Fixes ENG-123`, as
  `.github/pull_request_template.md` asks. Linear links the PR to that issue,
  or sub-issue, and marks it done when the PR merges.
- Delegating a parent issue that has sub-issues, or commenting
  `@Cursor orchestrate this` on one, starts an orchestrator for its
  sub-issues instead of a worker. It dispatches the sub-issues that are
  `agent-ready` and unblocked, and
  [orchestration](orchestration.md#start-an-orchestrator-from-linear) says
  what it does next. It never merges: in auto mode a PR that changes no owned
  path merges itself, and the owner merges the rest.
- An agent files a problem outside its issue with `linear_queue.sh create`
  instead of fixing it, and lists it under Follow-ups in its PR. The issue
  uses the template, without `agent-ready`.

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
- A run started by delegating INFRA-40 had the `subscribe_github_pr`,
  `subscribe_linear_issue`, and `subscribe_linear_comment` tools, so an
  orchestrator started from Linear can wait for PR and issue events, as
  [orchestration](orchestration.md#start-an-orchestrator-from-linear) says.
- Delegated workers therefore skip MCP-only steps. Whether the team could
  give unattended runs the MCP through a static `Authorization` header in
  Cursor's team MCP settings is untested, and is the owner's decision, because
  it adds a second copy of the key.

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
