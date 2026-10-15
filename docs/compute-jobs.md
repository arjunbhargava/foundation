# Compute jobs: plan

Status: **proposed**, awaiting the owner's approval (task T16 in
[the template plan](template-plan.md)). Nothing on this page is built yet.

This page is the plan for letting agents run long jobs, such as model training
or simulations, on AWS machines through SkyPilot (decision D4), and for letting
any agent see each job's progress and result. The owner chose SkyPilot and AWS
on 2026-10-15.

## Terms

- **Job**: one command run on one AWS machine, launched from a job file.
- **Job file**: a TOML file in `jobs/` on a PR's branch, saying what to run,
  on what hardware, for how long, and within what budget.
- **Job id**: `pr<PR number>-<job file name>-<first 8 hex digits of the job
  file's SHA-256>`, such as `pr81-train-small-3f9a2c1d`. It is also the
  SkyPilot cluster name. The prefix `pr81-train-small-` finds every job
  launched from that file, whatever its content was.
- **Job record**: the files under `s3://$COMPUTE_JOBS_BUCKET/jobs/<job id>/`,
  written by the workflows, and under `machines/<machine id>/`, written by the
  job's machine (layout below). It is the only state that observers read.
- **Observer**: any agent or person reading a job record with
  `mise run job:observe`.

## The requirement that shapes the design

Workers and orchestrators run on separate VMs with no shared state, and must
see every job's status, log tail, result, run record, and cost so far,
including a job another agent launched after that agent has stopped.
SkyPilot's own state (`~/.sky`, `sky status`, `sky logs`, `sky jobs queue`)
lives on the machine that ran `sky launch`, so no other machine sees it unless
everyone shares a SkyPilot API server.

## Options for observing jobs

| | (a) Job writes its record to S3 | (b) Shared SkyPilot API server | (c) SkyPilot managed jobs |
|---|---|---|---|
| Standing cost | None; S3 is about $0.03 per job-day of requests and storage | An always-on VM with the Helm chart's 4 vCPU and 8 GiB, such as m7i.xlarge at about $0.20/h, $147/month | A controller VM of 4+ vCPU (about $0.20/h) while jobs run; it stops after 10 idle minutes |
| Running parts we operate | One bucket | A public HTTPS endpoint with authentication, upgrades, and a database | The controller, found through the launching machine's `~/.sky` |
| What an observer needs | A read-only S3 key and boto3 | The SkyPilot client (Python ≤ 3.13, about 100 packages) and a server token | Same as (b): without a server, a fresh machine can't find the controller |
| Access an observer gets | Read the bucket | SkyPilot's `user` role, which can also launch and cancel; its only other role is `admin` | Same as (b) |
| Logs after the machine is gone | Kept in S3 until the lifecycle rule deletes them (90 days) | Lost for plain clusters unless synced down first | Kept on the controller for 7 days by default |
| Failure modes | Status is self-reported: a machine that dies without warning shows as `lost` after 3 missed heartbeats (3 min), until the watch workflow confirms it in EC2 | Server down means nothing can be observed or launched | Controller loss loses the queue; with (b), the server runs the controller |
| Spot recovery | None; the job records `preempted`, and the agent relaunches from its checkpoint | None for plain clusters | Automatic relaunch |
| Code we maintain | About 1,100 lines of Python (wrapper, observe, launch, watch) plus tests and four workflows | Deployment and configuration | Configuration |

**Recommendation: (a).** It is the only option that meets the requirement
without a server, gives observers read-only access, and keeps logs after the
machine is gone. Its costs are the code we maintain and self-reported status.
Revisit (b) with (c) if jobs need automatic spot recovery, multi-node
clusters, or more than about 20 at once; the S3 record keeps working
alongside them.

## How a job runs

1. An agent commits `jobs/train-small.toml` to its PR branch and pushes.
2. `.github/workflows/compute-launch.yml` runs on `pull_request_target`, so
   the workflow code comes from `main`, not from the PR. It runs only for PRs
   from this repository's branches, never forks, and in the GitHub
   environment `compute`, which only `main`'s workflows can use. It reads the
   job file from the PR's head commit as data, validates it against
   `compute/limits.toml`, and skips a job id that already has a record. It
   refuses to launch if no AWS budget action exists or the action has fired,
   or if the list price × maximum run time exceeds the job's `budget_usd`.
   It then writes `launch.json` and runs `sky launch --down --detach-run` with
   the head commit's files as the working directory and the job image's
   digest, adds the machine id to `launch.json`, and comments the job id on
   the PR. It never runs the PR's code on
   the runner, which is what makes `pull_request_target` safe here; zizmor's
   `dangerous-triggers` audit is suppressed with a comment naming these
   guards.
3. On the machine, `python -m compute_jobs.run` runs the command. It writes
   the run record, a heartbeat every 60 s, and new log output every 30 s. It
   stops the command at the maximum run time, on a cancel request, or on a
   spot interruption notice, then uploads `output/` and the final status.
   SkyPilot's autodown then deletes the machine after 5 idle minutes.
4. `.github/workflows/compute-watch.yml` runs every 15 minutes. It
   terminates any job machine past its maximum run time plus 15 minutes, or
   cancelled more than 10 minutes ago, and every job machine once the budget
   action has fired. It cancels the jobs of PRs closed without merging, and
   marks `lost` the jobs whose machine is gone.
5. When a job ends, the watch comments on its PR once, and starts
   `.github/workflows/compute-job-ended.yml` for it with
   `workflow_dispatch`, one of the two events that `GITHUB_TOKEN` may start.
   That run's completion is the "workflow run completed" event on which a
   Cursor Automation starts a follow-up agent to read the result, as T16
   asks. An agent that is still running learns of the end from the PR
   comment, through a PR subscription, or by observing.
6. Any agent runs `mise run job:observe -- pr81-train-small-3f9a2c1d`.

The launch workflow runs on the `pull_request_target` types `opened`,
`synchronize`, `reopened`, and `closed`, because the default types omit
`closed`. On each run it lists the records under the prefix
`pr<N>-<name>-` for every job file the PR adds, changes, or deletes, so a
deleted file's jobs are found without its content:

- A changed file launches its new content and cancels the file's older jobs
  that are still running.
- A deleted file, or a PR closed without merging, cancels the file's
  running jobs. Merging cancels nothing.
- An unchanged file launches nothing, because its job id already has a
  record. To rerun the same job, change the file, for example by adding
  `attempt = 2`.

A cancel is a `cancel` object in the job record, which the wrapper checks
with each heartbeat. The watch backs up both the `closed` event and the
wrapper.

## Interface

**Job file** (`jobs/<name>.toml`, name of 1–20 characters from `a-z`, `0-9`,
and `-`):

```toml
command = "python -m myproject.train --epochs 10"
accelerators = "L4:1"      # SkyPilot syntax; omit for CPU only
cpus = "4+"
use_spot = true
max_runtime_minutes = 120  # 1 to compute/limits.toml's maximum, 1440 at first
budget_usd = 5.0           # > 0; the task's compute budget bounds it
seed = 1234                # recorded, and passed as COMPUTE_JOB_SEED

[settings]                 # free-form; recorded, and passed as JSON
learning_rate = 3e-4
```

`compute/limits.toml` caps GPUs per job (8), maximum run time (1440 min),
nodes per job (1), and idle minutes before autodown (5), and lists the
allowed regions and instance families.

**Job record.** The workflows write under `jobs/<job id>/`. The machine
writes only under `machines/<machine id>/`, where the machine id is
`<role id>:<instance id>`: the value of IAM's `aws:userid` for an EC2
instance role, so the job role's policy can limit each machine to its own
prefix. `launch.json` names the machine id, so observers trust the
workflows' mapping, never a machine's.

| Object | Written by | Contents |
|---|---|---|
| `jobs/<job id>/launch.json` | launch workflow | Job file, PR, commit, image digest, instance type, region, spot, list price in USD/h, launch time, machine id |
| `jobs/<job id>/status.json` | launch workflow, watch | `state` before the machine starts (`launching`, `launch_failed`), or after it is gone (`cancelled`, `lost`), and `message` |
| `jobs/<job id>/cancel` | launch workflow, watch | Present when cancelled |
| `machines/<machine id>/status.json` | wrapper | `state`, `heartbeat_at`, `started_at`, `ended_at`, `exit_code`, `message` |
| `machines/<machine id>/run-record.json` | wrapper | Commit, uncommitted changes, image digest, settings, seed, GPU model and driver, CPU, memory, start and end times |
| `machines/<machine id>/logs/000001.txt`, … | wrapper | Combined stdout and stderr, in order |
| `machines/<machine id>/result.json` | the job, optional | Small summary such as final metrics |
| `machines/<machine id>/output/` | wrapper, from `$COMPUTE_JOB_OUTPUT_DIR` | Files the job saves |

Checkpoints go to `$COMPUTE_JOB_OUTPUT_DIR`, and large inputs are read from
`s3://$COMPUTE_JOBS_BUCKET/data/`, which only the owner and the launcher can
write; neither goes in git.

`state` is one of `launching`, `launch_failed`, `running`, `succeeded`,
`failed`, `timed_out`, `cancelled`, `preempted`, or `lost`. Observe shows the
workflows' state when it is `cancelled` or `lost`, and otherwise the
machine's state once the machine has written one. It shows `lost` when a
`running` job's heartbeat is more than 180 s old.

**Observe command**, read-only:

```text
$ mise run job:observe -- pr81-train-small-3f9a2c1d
Job pr81-train-small-3f9a2c1d: running, last heartbeat 42 s ago
Pull request: https://github.com/arjunbhargava/foundation/pull/81, commit 1a2b3c4
Machine: g6.xlarge (1 × L4), spot, us-east-1, list price $0.39/h
Elapsed: 1 h 12 min of 2 h maximum; cost so far about $0.47 (list price × elapsed)
Run record: s3://<bucket>/machines/AROA...:i-0abc.../run-record.json
Last 20 log lines:
...
```

- `--lines N` sets the log tail (default 20); `--json` prints the record as
  one JSON object; `--pr 81` lists that PR's jobs; no argument lists every
  job with its state.
- Exit 0 when the record was read, whatever the job's state; 1 when the job id
  has no record; 2 when credentials are missing or rejected, with a message
  naming the variable, such as: `COMPUTE_JOBS_AWS_ACCESS_KEY_ID is not set,
  so job records can't be read. Ask the owner to add the compute-jobs-observer
  key as a Cursor secret (docs/compute-jobs.md, AWS setup, step 8).`
- Cost so far is an estimate from SkyPilot's catalog price. The AWS bill lags
  by up to a day.

## Credentials

Launch credentials never reach an agent. A Cursor cloud agent secret is
injected into every agent, so a launch key there would let any worker launch
anything. Instead, only `main`'s launch and watch workflows can assume the
AWS role `compute-jobs-launcher`, through GitHub's OpenID Connect (OIDC)
tokens, which last one hour. Agents start a job by pushing a job file, which
needs no write access through `gh`.

The job's own code is untrusted: it is whatever the PR's head commit
contains. It runs only on the job machine, as the role `compute-jobs-job`,
which can read the bucket, write only `machines/${aws:userid}/*`, and stop
or terminate only its own instance, so one job can't alter another's record.
SkyPilot's default, `aws.remote_identity: LOCAL_CREDENTIALS`, would
copy the launcher's credentials onto the machine, so the launcher sets
`remote_identity: compute-jobs-job`.

Observers use the access key of the IAM user `compute-jobs-observer`, which
can only list and read the bucket. A leaked key exposes job logs and outputs,
nothing more.

| Name | Where | Secret? | Read by |
|---|---|---|---|
| `COMPUTE_JOBS_AWS_ACCESS_KEY_ID` | Cursor secret | yes | observe |
| `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY` | Cursor secret | yes | observe |
| `COMPUTE_JOBS_BUCKET` | Cursor secret, and variable on the GitHub environment `compute` | no | observe, launch, watch |
| `COMPUTE_JOBS_AWS_REGION` | Cursor secret, and variable on `compute` | no | observe, launch, watch |
| `COMPUTE_JOBS_AWS_ROLE_ARN` | variable on `compute` | no | launch, watch |

Each name goes into `.env.example` in the PR that first reads it.

## Spending limits

AWS budget data refreshes up to three times a day, and a daily budget acts on
the previous full day's spend, so a budget action can fire a day late.
Two limits act at once instead. `compute/limits.toml` lists the instance
families the launcher accepts (G for GPUs, M and C for CPU), and EC2's vCPU
quotas cap how many machines of a family can run at once, and so cap spend
per hour. With 64 G-family vCPUs on demand, 64 on spot, and 64 Standard
vCPUs, spend is at most about 128 × $0.47 (g6e, the dearest G family per
vCPU) + 64 × $0.20 ≈ $73 per hour, or $1,800 per day, under D8's $10,000.
The budget action is the backstop: at $10,000 of actual spend in a day it
denies `ec2:RunInstances` to the launcher role, and the watch workflow then
terminates every job machine. Per job, the launcher refuses a job whose
maximum cost exceeds its `budget_usd`, and the machine stops itself at the
maximum run time.

## AWS setup for the owner

Each step works in a phone browser. Use region `us-east-1` unless you pick
another; it goes in `COMPUTE_JOBS_AWS_REGION`.

1. Create a separate AWS account for agent jobs, named `agent-jobs`:
   <https://console.aws.amazon.com/organizations/v2/home/accounts>. Do the
   remaining AWS steps in it, by switching to its role
   `OrganizationAccountAccessRole`.
2. Request vCPU quotas in `us-east-1`: "Running On-Demand G and VT instances"
   and "All G and VT Spot Instance Requests", 64 each, and check that
   "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" is at
   most 64: <https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas>.
3. Create an S3 bucket, such as `arjunbhargava-foundation-compute-jobs`, with
   all public access blocked, and a lifecycle rule that deletes objects after
   90 days: <https://s3.console.aws.amazon.com/s3/bucket/create>.
4. Add GitHub as an identity provider: type OpenID Connect, URL
   `https://token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`:
   <https://console.aws.amazon.com/iam/home#/identity_providers/create>.
5. Create the role `compute-jobs-job`, trusted by EC2, from the policy that
   the implementation PR commits as `compute/aws/job-role-policy.json`:
   <https://console.aws.amazon.com/iam/home#/roles/create>.
6. Create the role `compute-jobs-launcher`, trusted by the GitHub provider
   with `sub` equal to `repo:arjunbhargava/foundation:environment:compute`,
   from `compute/aws/launcher-role-policy.json`: SkyPilot's [minimal
   policy](https://docs.skypilot.co/en/latest/cloud-setup/cloud-permissions/aws.html#minimal-iam-policy)
   with `compute-jobs-job` in place of `skypilot-v1`, plus the bucket and
   reading budget actions.
7. Create the policy `compute-jobs-deny-launch`, denying `ec2:RunInstances`
   and `ec2:StartInstances`, from `compute/aws/deny-launch-policy.json`:
   <https://console.aws.amazon.com/iam/home#/policies/create>.
8. Create the IAM user `compute-jobs-observer` with
   `compute/aws/observer-policy.json` and an access key, then add the key as
   the Cursor secrets `COMPUTE_JOBS_AWS_ACCESS_KEY_ID` and
   `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY`, with `COMPUTE_JOBS_BUCKET` and
   `COMPUTE_JOBS_AWS_REGION`: <https://console.aws.amazon.com/iam/home#/users/create>,
   then <https://cursor.com/dashboard>, Cloud Agents > Secrets.
9. Create a daily cost budget, `compute-jobs-daily`, of $10,000, with email
   alerts at 50% and 80%, and an action at 100% of actual cost that applies
   `compute-jobs-deny-launch` to the role `compute-jobs-launcher`
   automatically. Let the console create the action's execution role:
   <https://console.aws.amazon.com/costmanagement/home#/budgets/create>.
   Alerts alone don't stop spend; the action and the quotas in step 2 do.
10. In GitHub, create the environment `compute`, limited to the branch `main`,
    with the variables `COMPUTE_JOBS_AWS_ROLE_ARN` (the ARN from step 6),
    `COMPUTE_JOBS_BUCKET`, and `COMPUTE_JOBS_AWS_REGION`:
    <https://github.com/arjunbhargava/foundation/settings/environments/new>.
11. If Cursor's agent network allowlist is on, add `s3.us-east-1.amazonaws.com`
    and `<bucket>.s3.us-east-1.amazonaws.com`.

The policy files land with the code that needs them, so steps 5–8 wait for
those PRs; steps 1–4 can start now.

## Files touched

- `compute/`: a uv project of its own, pinned to Python 3.13, because
  SkyPilot 0.14.0 supports Python only up to 3.13 and the repository pins
  3.14. It depends on boto3 (Apache-2.0), with SkyPilot (`skypilot[aws]`,
  Apache-2.0) in a `launcher` dependency group so that observing doesn't
  install it, and moto (Apache-2.0) for tests that fake S3 and EC2 in
  process. Package `compute_jobs`: `job_record.py` (the S3 layout, its only
  owner), `run_record.py`, `run.py` (the wrapper), `observe.py`,
  `job_file.py` (parse and validate), `launch.py`, `watch.py`; plus
  `limits.toml`, `aws/*.json` policies, `Dockerfile` (CUDA base image pinned
  by digest), and `tests/`.
- `.github/workflows/`: `compute-image.yml` (build on pushes to `main`, push
  to `ghcr.io/arjunbhargava/foundation/compute-job`), `compute-launch.yml`,
  `compute-watch.yml`, `compute-job-ended.yml`, and a `compute` job in
  `ci.yml`. Runner minutes are free for this public repository; a private
  project's watch uses about 2,900 minutes a month, $23 at GitHub's
  $0.008 per Linux minute.
- `mise.toml`: `setup:compute`, `lint:compute`, `test:compute`, and
  `job:observe`.
- `.env.example`, `.github/CODEOWNERS` (`compute/limits.toml` and
  `compute/aws/`), `docs/conf.py` (the package's API pages), `AGENTS.md` and
  its `.jinja` twin, `docs/architecture.md`, and this page, rewritten to
  describe what was built.
- A `compute-jobs` skill drafted for the owner to edit (finding F2), and the
  `compute-cost` rule's first clause tied to step 9 being done instead of to
  the skill existing.

## Acceptance criteria

Each becomes a named test, run against moto with no AWS account or network.

1. Observe prints state, heartbeat age, machine, cost so far, log tail, and
   run record path for a job the wrapper wrote; `--json` and `--pr` work.
2. Observe reports `lost` for a running job whose heartbeat is over 180 s
   old.
3. Observe exits 2, naming the variable, without credentials, and naming
   `compute-jobs-observer` when S3 rejects them.
4. The wrapper writes a complete run record and the final state for exit 0,
   a nonzero exit, the maximum run time, a cancel request, and a spot
   interruption notice.
5. The log tail is in order across chunk boundaries.
6. Job file validation rejects a bad name, too many GPUs or nodes, too long a
   run time, a missing or zero `budget_usd`, and a maximum cost above it.
7. The SkyPilot task and config the launcher builds set
   `remote_identity: compute-jobs-job`, autodown, the image digest, and no
   file mounts from the runner.
8. The launcher refuses when no budget action exists or it has fired.
9. The watch terminates machines past their deadline, cancelled, or after the
   budget action fired; cancels the jobs of PRs closed without merging; and
   comments and starts `compute-job-ended.yml` once per finished job.
10. A changed job file cancels the file's older running jobs, a deleted file
    or a PR closed without merging cancels them, and an unchanged file
    launches nothing.
11. The job role's policy allows writes only under `machines/${aws:userid}/`,
    and observe ignores a machine prefix that `launch.json` doesn't name.
12. `mise run check` passes with no AWS credentials.

## Not in this plan

T16's GPU tests on a self-hosted GPU runner need a runner, which is a
separate decision and cost; they are a follow-up. Until then, tests use small
CPU-sized settings.

## Open questions

- Should the `compute` environment require a person's approval for each
  launch? Default: no, so agents aren't blocked; the quotas and budget
  action bound the spend.
- Should compute support be a Copier question, so projects without jobs
  leave out `compute/` and its workflows? Recommended: yes, defaulting to no,
  in PR 8.

## Pull requests after approval

Stacked, each within 500 lines: (2) the `compute/` project, `job_record.py`,
`run_record.py`, and the CI job; (3) observe; (4) the wrapper; (5) the
Dockerfile and image workflow; (6) job files, the launcher, and the launch
workflow; (7) the watch and job-ended workflows; (8) the skill, the rule,
and the docs.
