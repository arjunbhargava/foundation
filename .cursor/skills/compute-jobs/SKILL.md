---
name: compute-jobs
description: >
  Run a long job, such as a simulation, an evolutionary search, or a training
  run, on the shared compute server, then follow it and report its result.
  Use before writing a job file, launching, observing, or cancelling a job,
  or reporting a job's cost or result in a PR. Never use it to provision or
  change the server.
---

<!-- An agent's draft, for the owner to edit (finding F2). -->

# Compute jobs

A job runs on AWS machines through a shared SkyPilot API server that the
owner operates. This repository is only a client: four `mise run job:*`
commands, described in `docs/compute-jobs.md`, which also defines the job
file, the exit codes, and `progress.json`.

## Before launching

1. Check that the task's Linear issue gives a compute budget. Without one the
   budget is $0, and the `compute-cost` rule says to ask first.
2. Write `jobs/<name>.yaml` on your branch. Pick the kind: `single` (one
   machine), `multi-node` (distributed training), or `search` (many short
   evaluations, through `compute_jobs.fanout`). Pick the smallest profile
   that fits; anything that renders, such as Isaac Sim, needs `gpu-sim`.
3. Make the command run a tiny CPU case when `COMPUTE_JOB_SMOKE=1` is set, or
   set `smoke: false` if it can't run without a GPU.
4. Run `mise run job:dry-run -- jobs/<name>.yaml`. It prints the maximum
   cost: the profile's list price × nodes × `max_runtime_minutes`. If that,
   plus what the task has already spent, exceeds the budget, ask in the PR
   before launching.
5. Commit and push. `job:launch` uploads the pushed commit and refuses
   uncommitted changes.

Write checkpoints to `$COMPUTE_JOB_CHECKPOINT_DIR` for any job longer than
an hour, and always with `use_spot: true`: a preempted job restarts from the
last checkpoint, or from the beginning without one.

## Launching and following

- `mise run job:launch -- jobs/<name>.yaml` prints the job's name. Put it in
  the PR.
- `mise run job:observe -- <job name>` shows state, progress, cost so far, and
  a 20-line log tail. Read that, not whole logs. `--pr <number>` lists a PR's
  jobs, and `--json` gives one object to parse.
- A job's progress comes from `compute_jobs.progress.report(...)`. Report at
  least once a minute in a long job, so others can tell it is alive.
- `mise run job:cancel -- <job name>` cancels a job you launched. Never
  cancel another agent's job.

Any agent can observe any job, including one whose launcher has stopped, so
an orchestrator or a later worker can pick up a job by its name.

## Reporting in the PR

Under "Verified", give one line per job: its name, its final state, its cost
from `job:observe`, and where its result is (the run record's path from
`job:observe`). Include failed runs in the task's total spend.

## When something fails

Follow the table in "For a user who has never used cloud" in
`docs/compute-jobs.md`. If a command exits 2, the client or its
configuration is missing: tell the owner which variable or step the message
names, and stop. Never run `sky` directly, start a server, or change the
server's settings: the server and its admin tasks belong to the owner, in
https://github.com/arjunbhargava/foundation-compute.
