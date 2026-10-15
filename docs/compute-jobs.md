# Compute jobs: plan

Status: **proposed**, awaiting the owner's approval (task T16 in
[the template plan](template-plan.md)). Nothing on this page is built yet.
Revised on 2026-10-15 at the owner's request, to evaluate a shared SkyPilot
API server in full.

This page is the plan for letting agents run long jobs, such as model training
or simulations, on AWS machines through SkyPilot (decision D4), and for letting
any agent see each job's progress and result. The owner chose SkyPilot and AWS
on 2026-10-15. SkyPilot facts below come from its documentation for 0.14.0,
read on 2026-10-15; prices are AWS on-demand list prices in `us-east-1`.

## Terms

- **API server**: SkyPilot's server, which holds the cloud credentials and
  the table of every cluster and managed job, and does the launching. A
  **client** is the `sky` command or Python SDK pointed at it.
- **Managed job**: a SkyPilot job that the API server watches, relaunching
  it after a spot preemption and deleting its machine when it ends.
- **Job file**: a YAML file in `jobs/` on a PR's branch, saying what to run,
  on what hardware, for how long, and within what budget.
- **Job name**: `pr<PR number>-<job file name>-<first 8 hex digits of the
  job file's SHA-256>`, such as `pr81-train-small-3f9a2c1d`. The hash is
  always the last 8 characters, so the name splits back into its parts.
- **Job archive**: the copy of a job's run record, result, logs, and output
  that the job writes to S3, so results survive the loss of the API server.
- **Admin**: the person who provisions and operates the API server, with
  the `compute-server-admin` skill. Agents are clients only.

## The requirement that shapes the design

Workers and orchestrators run on separate VMs with no shared state, and must
see every job's status, log tail, result, run record, and cost so far,
including a job another agent launched after that agent has stopped.
SkyPilot's own state (`~/.sky`, `sky status`, `sky logs`, `sky jobs queue`)
lives on the machine that runs the API server. Without a shared server, that
is each launching machine, and no other machine sees it.

## Options

| | (a) Job writes its record to S3 | (b) Shared SkyPilot API server | (c) Managed jobs without (b) |
|---|---|---|---|
| Who can see a job | Anyone with a read-only S3 key | Every client of the server: `sky jobs queue -u` lists all users' jobs | Only the launching machine |
| What an agent holds | A read-only S3 key | An endpoint and a token; no AWS credentials | AWS launch credentials |
| Launch path | A GitHub workflow, through OIDC | The client, through the server | The agent itself |
| Limits enforced by | The workflow's validation | A server-side admin policy, which can reject or rewrite every request | Nothing central |
| Spot recovery | None | Automatic, for managed jobs | Automatic |
| Logs after the machine is gone | Kept in S3 | Kept on the server for 7 days by default, configurable | Kept on the controller |
| Standing cost | About $0.03 per job-day | About $750 per month (below) | A controller VM while jobs run |
| Code we maintain | About 1,100 lines | An admin policy, deployment values, and thin wrappers | Little |

(c) fails the requirement on its own. (b) meets it, and SkyPilot then runs
managed jobs inside the API server ("consolidation mode", its default for a
remote server), so (c) becomes part of (b).

## Option (b) in detail

**Where it runs.** SkyPilot documents two deployments. The Helm chart on
Kubernetes is the one it recommends for production: it alone has graceful
upgrades, server-side authentication with roles, and a database other than
the pod's disk. The cloud-VM deployment (`sky launch` of a VM running
`sky api start --deploy`, 8+ vCPU and 16+ GB) "does not offer failover and
graceful upgrading", and has "no authentication by default". This plan uses
the Helm chart on Amazon EKS.

| Part | Choice | $/month |
|---|---|---|
| EKS control plane | Standard support, $0.10/h | 73 |
| Nodes | 2 × m7i.2xlarge (8 vCPU, 32 GiB, $0.4032/h) in two zones, so the pod reschedules in minutes if one fails | 589 |
| Database | RDS PostgreSQL db.t4g.micro, Multi-AZ, 20 GB, 7-day backups | 28 |
| Load balancer | Application Load Balancer, with TLS | 22 |
| NAT gateway | One, for the private nodes | 35 |
| Other | Node disks, Route 53 zone and health check, domain | 6 |
| **Total** | | **about 750** |

The API server pod gets SkyPilot's minimum of 4 CPU and 8 GiB, which serves 8
long requests (such as log tails) at once, and 16 launching and 400 running
managed jobs. Raising it to 6 CPU and 24 GiB later fits the same nodes. One
node instead of two saves $294 per month, at the cost of about 10 minutes'
downtime when a node fails.

**Authentication and TLS.** The chart exposes the server through
ingress-nginx by default, but Kubernetes archived ingress-nginx on
2026-03-24, and it gets no more security fixes. This plan turns it off
(`ingress-nginx.enabled=false`) and uses the AWS Load Balancer Controller's
ALB instead (`ingress.ingressClassName=alb`), with an ACM certificate for a
name such as `skypilot.<your domain>`; ACM renews it. Basic auth that
nginx did is replaced by the API server's own (`apiService.enableUserManagement=true`),
which keeps SkyPilot's two roles: `admin` (the owner) and `user`. Agents
get a service-account token with the `user` role, so they can launch and
read, but can't change the server's settings or admin policy. The `user`
role can also cancel or tear down any job, so a token holder can stop
another agent's job; the agents' rules forbid it, and the job archive keeps
the evidence.

**Persistence and backup.** The job table, users, and tokens live in RDS
PostgreSQL (`apiService.dbConnectionSecretName`), with automated backups and
point-in-time restore for 7 days. That makes the pod stateless, so a pod or
node loss loses nothing. Task logs are kept on the server, so set
`jobs.controller.task_logs_gc_retention_hours` to 2160 (90 days), and the
job archive keeps a second copy in S3.

**Version pinning.** SkyPilot guarantees compatibility between adjacent
minor versions from 0.10.0 on, and asks that the server be upgraded first.
The client is pinned once, as `skypilot==0.14.0` in `compute/uv.lock`, and
run through `mise run job:*`, because `observe` uses the Python SDK and a
second pin in `mise.toml` would drift. The server's image and chart version
are pinned in `compute/server/values.yaml`, and a test fails when the two
pins name different minor versions. SkyPilot 0.14.0 supports Python up to
3.13, and the repository pins 3.14, so `compute/` is a uv project of its
own pinned to 3.13.

**Upgrades and failures.**

- An upgrade is `helm upgrade` with the new image, then a PR that moves the
  client pin. Clients retry while the pod restarts, and running jobs keep
  running.
- If the server is down, jobs keep running on their machines, but nothing
  can launch, and preempted jobs aren't relaunched until it is back. A Route
  53 health check emails the owner. A scheduled GitHub workflow,
  independent of the server, terminates any job machine past its maximum
  run time.
- If the database is lost, restore it from backup; the job archive in S3
  still holds every result.

**Network.** If Cursor's agent network allowlist is on, it must include the
server's host name. Agents need no AWS domains, because they never call AWS.

**What "set up once and forget" actually needs.** Setup is once. These recur,
from AWS's and SkyPilot's documented lifecycles; the hours are my
estimate:

| Task | How often | Why |
|---|---|---|
| Upgrade EKS one minor version, and its add-ons | About yearly | Standard support lasts 14 months; after it, the control plane costs $0.60/h instead of $0.10/h |
| Update the node group's AMI | Monthly | Security fixes |
| Upgrade SkyPilot, then the client pin | Each minor release | A client more than one minor version behind may stop working |
| Rotate the agents' token | Before it expires (90 days chosen; SkyPilot's default is 30) | Then update the Cursor secret |
| Answer a health-check email | When it fires | Nothing launches while the server is down |

Together that is about two hours a month, plus half a day a year for the EKS
upgrade, done with the `compute-server-admin` skill.

## Recommendation

**Use (b) with the job archive from (a).** The shared server gives every
agent the same view of every job with only an endpoint and a token, enforces
limits on the server, and recovers preempted jobs. The archive keeps results
when the server isn't there. Its costs are about $750 a month and the
operating work above, and every token holder can launch within the limits.

## How a job runs

1. An agent commits `jobs/train-small.yaml` to its PR branch, then runs
   `mise run job:launch -- jobs/train-small.yaml`. The client checks its
   two variables, names the job, labels it with the PR and commit, and
   submits it with `sky jobs launch`. It uploads the working tree at the
   pushed commit, and refuses if the working tree has uncommitted changes.
2. On the server, the admin policy checks the request against
   `compute/server/limits.yaml` and rejects it, or rewrites it, before
   anything launches. It requires `budget_usd > 0` and rejects a job whose
   list price × maximum run time exceeds it. It allows only listed regions
   and instance families, up to 8 GPUs and one node. It wraps the command in
   `timeout` at the maximum run time, and forces
   `aws.remote_identity: compute-jobs-job`. Without that, the default
   `LOCAL_CREDENTIALS` would copy the server's launch credentials onto the
   job's machine. It also rejects any request whose config tries to change
   these settings.
   The policy also mounts `s3://<bucket>/checkpoints/<job name>/` at
   `$COMPUTE_JOB_CHECKPOINT_DIR`, with SkyPilot's `MOUNT_CACHED` mode, so the
   path is the same on every attempt of the job.
3. On the machine, `python -m compute_jobs.run` runs the command. It writes
   the run record and, at the end, `result.json`, `output/`, and the full
   log to the job archive, and prints the run record and result into the
   job's log, where clients read them.
4. The API server relaunches a preempted job on a new machine, which resumes
   from `$COMPUTE_JOB_CHECKPOINT_DIR`. Each attempt writes its own archive
   prefix, and its run record names the attempt. The server deletes the
   machine when the job ends.
5. `.github/workflows/compute-watch.yml` runs every 15 minutes, with its
   own `user`-role server token (SkyPilot has no read-only role) and an AWS
   role through OIDC. It records each job
   machine's id from EC2 tags, which the server sets and a job can't. It
   terminates machines past their maximum run time plus 15 minutes, and
   every job machine once the budget action has fired. It cancels the jobs
   of PRs closed without merging. When a job ends, it comments on the PR
   and adds a completed check run, `compute-job: <job name>`, which a
   Cursor Automation on "CI completed" can start a follow-up agent from.
   Cursor's "workflow run completed" trigger, which T16 names, fires only
   for runs started by a push.
6. Any agent runs `mise run job:observe -- pr81-train-small-3f9a2c1d`.

## Interface

### Client, the default

The only client configuration is two variables, which are SkyPilot's own
names, so the pinned client reads them directly:

| Variable | Meaning |
|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT` | The server's HTTPS URL, such as `https://skypilot.example.com` |
| `SKYPILOT_SERVICE_ACCOUNT_TOKEN` | The agents' service-account token, role `user` |

`mise run job:launch -- <job file>`, `job:observe`, and `job:cancel` check
both before calling SkyPilot. With either unset, or with an endpoint that
isn't `https://` or points at this machine, they exit 2 and start nothing.
This matters because the `sky` client, with no endpoint, starts a local API
server. The message is:

```text
SKYPILOT_API_SERVER_ENDPOINT is not set, so no job can be launched or
observed. This project is a client of a shared SkyPilot API server: ask the
owner to add SKYPILOT_API_SERVER_ENDPOINT and SKYPILOT_SERVICE_ACCOUNT_TOKEN
as Cursor secrets. The server is run with the compute-server-admin skill;
an agent never starts one. Nothing was started.
```

Observe output:

```text
$ mise run job:observe -- pr81-train-small-3f9a2c1d
Job pr81-train-small-3f9a2c1d: RUNNING, managed job 42, recovered 0 times
Pull request: https://github.com/arjunbhargava/foundation/pull/81, commit 1a2b3c4
Machine: g6.xlarge (1 × L4), spot, us-east-1, list price $0.39/h
Elapsed: 1 h 12 min of 2 h maximum; cost so far about $0.47 (list price × elapsed)
Run record: in the job log, and at s3://<bucket>/machines/AROA...:i-0abc.../run-record.json
Last 20 log lines:
...
```

- `--lines N` sets the log tail (default 20); `--json` prints one JSON
  object; `--pr 81` lists that PR's jobs; no argument lists every job.
- Exit 0 when the job was read, whatever its state; 1 when no job has that
  name; 2 for missing or rejected configuration, naming the variable.
- Cost so far is an estimate from SkyPilot's catalog price. The AWS bill lags
  by up to a day.

The job file:

```yaml
command: python -m myproject.train --epochs 10
accelerators: L4:1        # SkyPilot syntax; omit for CPU only
cpus: 4+
use_spot: true
max_runtime_minutes: 120  # 1 to limits.yaml's maximum, 1440 at first
budget_usd: 5.0           # > 0; the task's compute budget bounds it
seed: 1234                # recorded, and passed as COMPUTE_JOB_SEED
settings:                 # free-form; recorded, and passed as JSON
  learning_rate: 3.0e-4
```

### Admin, apart from the client

- The provisioning and operating code is in `compute/server/`: Helm values,
  the admin policy package, IAM policy files, and the `limits.yaml` the
  policy reads. It runs only through `MISE_ENV=admin mise run
  compute-server:<provision|upgrade|rotate-token|status>`. Those tasks and
  their tools (AWS CLI, eksctl, kubectl, Helm) are in `mise.admin.toml`,
  which mise loads only when `MISE_ENV=admin`. So `mise run check`, CI, and
  agents' machines neither list nor install them.
- Each admin task needs the AWS CLI profile named by
  `COMPUTE_SERVER_ADMIN_AWS_PROFILE`, an IAM Identity Center login on the
  owner's machine. It is never a Cursor secret. Each task also asks the person
  to type the cluster name before it changes anything.
- `.cursor/skills/compute-server-admin/SKILL.md` covers provisioning,
  upgrades, token rotation, restore, and the checks after each.
- The always-applied `compute-cost` rule gains: "Never provision, change, or
  delete the compute API server, or run `MISE_ENV=admin` tasks, unless a
  person asked for it in this task. Never run `sky` directly; use
  `mise run job:*`." Rules are written by people (finding F2), so this is a
  draft for the owner to edit.
- Copier: two questions. `compute` (default no) adds the client part.
  `compute_server_admin` (default no, asked only when `compute` is yes) adds
  `compute/server/`, `mise.admin.toml`, and the admin skill. I recommend
  asking rather than leaving the admin part out. A team runs one server,
  from one repository, and every other project needs only the client;
  admin code in every project would be dead weight and something an agent
  might run. But the repository that runs the server must be able to come
  from the template too.

## Credentials and variables

| Name | Where | Secret? | Read by |
|---|---|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT` | Cursor secret | no | client |
| `SKYPILOT_SERVICE_ACCOUNT_TOKEN` | Cursor secret | yes | client |
| `SKYPILOT_API_SERVER_ENDPOINT`, `SKYPILOT_SERVICE_ACCOUNT_TOKEN` (a second, `user`-role token) | GitHub environment `compute` | token: yes | watch |
| `COMPUTE_JOBS_AWS_ROLE_ARN`, `COMPUTE_JOBS_AWS_REGION` | variables on `compute` | no | watch |
| `COMPUTE_SERVER_ADMIN_AWS_PROFILE` | the owner's shell only | no | admin tasks |

The server's own AWS identity is the role `compute-jobs-launcher`, given to
its pod through IAM Roles for Service Accounts (`rbac.serviceAccountAnnotations`),
so no long-lived AWS key exists. If SkyPilot doesn't accept that identity,
the fallback is an access key in the Kubernetes secret the chart reads
(`awsCredentials`), rotated every 90 days. The job's machine runs as
`compute-jobs-job`, which can read the bucket, write only
`machines/${aws:userid}/*` and `checkpoints/*`, and stop or terminate only
its own instance. The archive is per machine, so one job can't alter
another's results. Checkpoints can't be scoped the same way: a relaunch is a
new instance, and IAM can't tie a prefix to a job name. So any job could
overwrite another's checkpoints. That costs at most a restart from a bad
checkpoint, and the archived results stay intact.

## Spending limits

AWS budget data refreshes up to three times a day, and a daily budget acts on
the previous full day's spend, so a budget action can fire a day late. Two
limits act at once instead. The admin policy accepts only the instance
families in `limits.yaml` (G for GPUs, M and C for CPU), and EC2's vCPU
quotas cap how many machines of a family run at once. With 64 G-family
vCPUs on demand, 64 on spot, and 64 Standard vCPUs, spend is at most about
128 × $0.47 (g6e, the dearest G family per vCPU) + 64 × $0.20 ≈ $73 per
hour, or $1,800 per day, under D8's $10,000. The budget action is the
backstop: at $10,000 of actual spend in a day it denies `ec2:RunInstances`
to `compute-jobs-launcher`, and the watch then terminates every job machine.

## Setup for the owner

Each step works in a phone browser except 5 and 9, which run the admin
tasks from a laptop. Steps 1–4 can start now; 5–12 wait for the admin PRs.

1. Create an AWS account for agent jobs, `agent-jobs`, and sign in to it
   with IAM Identity Center:
   <https://console.aws.amazon.com/organizations/v2/home/accounts>.
2. Request vCPU quotas in `us-east-1`: "Running On-Demand G and VT
   instances" and "All G and VT Spot Instance Requests", 64 each; check that
   "Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" is at
   most 64: <https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas>.
3. Pick the server's host name, such as `skypilot.<your domain>`, and create
   a Route 53 hosted zone for the domain, registering one (about $15 a year)
   if you have none: <https://console.aws.amazon.com/route53/v2/hostedzones>.
4. Add GitHub as an identity provider: OpenID Connect, URL
   `https://token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`:
   <https://console.aws.amazon.com/iam/home#/identity_providers/create>.
5. On a laptop with the AWS CLI logged in to `agent-jobs`, set
   `COMPUTE_SERVER_ADMIN_AWS_PROFILE` and run
   `MISE_ENV=admin mise run compute-server:provision`. It creates, from the
   committed files, the EKS cluster, RDS database, ACM certificate, S3 bucket
   (private, 90-day expiry), the roles `compute-jobs-launcher`,
   `compute-jobs-job`, and `compute-jobs-watch`, the policy
   `compute-jobs-deny-launch`, the Route 53 health check, and the server
   with its admin policy. It prints the endpoint and the dashboard URL.
6. Open the dashboard, change the initial admin password, and create two
   service accounts with role `user` and 90-day expiry, `agents` and `watch`.
7. Add the Cursor secrets `SKYPILOT_API_SERVER_ENDPOINT` and
   `SKYPILOT_SERVICE_ACCOUNT_TOKEN` (the `agents` token):
   <https://cursor.com/dashboard>, Cloud Agents > Secrets.
8. Create the GitHub environment `compute`, limited to `main`, with the
   `watch` token as `SKYPILOT_SERVICE_ACCOUNT_TOKEN`, the endpoint, and the
   variables `COMPUTE_JOBS_AWS_ROLE_ARN` (the `compute-jobs-watch` ARN that
   step 5 printed) and `COMPUTE_JOBS_AWS_REGION`:
   <https://github.com/arjunbhargava/foundation/settings/environments/new>.
9. Run `MISE_ENV=admin mise run compute-server:status`, which checks that a
   request without a token is rejected, that the `agents` token can't change
   the server's settings, and that the admin policy rejects a job over the
   limits.
10. Create a daily cost budget, `compute-jobs-daily`, of $10,000, with email
    alerts at 50% and 80%, and an action at 100% of actual cost that applies
    `compute-jobs-deny-launch` to `compute-jobs-launcher` automatically:
    <https://console.aws.amazon.com/costmanagement/home#/budgets/create>.
    Alerts alone don't stop spend; the action and the quotas do.
11. If Cursor's agent network allowlist is on, add the server's host name.
12. Create a Cursor Automation on "CI completed", filtered to checks named
    `compute-job:`, that starts an agent to read the result:
    <https://cursor.com/automations>.

## Files touched

- `compute/`: a uv project pinned to Python 3.13, with `skypilot==0.14.0`
  (Apache-2.0) as the client, boto3 (Apache-2.0) for the job archive, and
  moto (Apache-2.0) to fake S3 and EC2 in tests. Package `compute_jobs`:
  `client_config.py` (the two variables and the refusal), `job_file.py`,
  `launch.py`, `observe.py`, `run.py` (the wrapper), `run_record.py`, and
  `archive.py` (the S3 layout); plus `Dockerfile` (CUDA base image pinned by
  digest) and `tests/`.
- `compute/server/`: `values.yaml`, `admin_policy/` (a package with its own
  tests), `limits.yaml`, `aws/*.json`, and `provision.sh`, `upgrade.sh`,
  `rotate_token.sh`, `status.sh`; `mise.admin.toml`.
- `.github/workflows/`: `compute-image.yml` (build on pushes to `main`, push
  to `ghcr.io/arjunbhargava/foundation/compute-job`), `compute-watch.yml`,
  and a `compute` job in `ci.yml`.
- `mise.toml`: `setup:compute`, `lint:compute`, `test:compute`,
  `job:launch`, `job:observe`, `job:cancel`.
- `.env.example`, `.github/CODEOWNERS` (`compute/server/`), `copier.yml`,
  `docs/conf.py`, `AGENTS.md` and its `.jinja` twin, `docs/architecture.md`,
  and this page, rewritten to describe what was built.
- The `compute-jobs` and `compute-server-admin` skills, and the
  `compute-cost` rule, drafted for the owner to edit (finding F2).

## Acceptance criteria

Each becomes a named test that needs no AWS account, network, or server,
except the last two, which `compute-server:status` checks on the real server.

1. With `SKYPILOT_API_SERVER_ENDPOINT` or `SKYPILOT_SERVICE_ACCOUNT_TOKEN`
   unset, or the endpoint not `https://` or local, `job:launch`,
   `job:observe`, and `job:cancel` exit 2. The message names both variables,
   the `compute-server-admin` skill, and the owner, and a fake `sky` on
   `PATH` records no call.
2. The default mise configuration lists no `compute-server:` task, and those
   tasks exit with a message when `COMPUTE_SERVER_ADMIN_AWS_PROFILE` is
   unset.
3. A project created from the template with default answers has no
   `compute/`; with `compute=true` it has the client and no
   `compute/server/`, `mise.admin.toml`, or admin skill; with both true, it
   has all three.
4. The server pin in `values.yaml` and the client pin in `compute/uv.lock`
   name the same minor version.
5. The admin policy rejects a job over the GPU, node, run-time, region, or
   family limits, without `budget_usd`, or over it. It rejects a config that
   sets `remote_identity` or `admin_policy`, and rewrites every accepted job
   to `remote_identity: compute-jobs-job`, with the `timeout` wrapper.
6. `job:launch` names the job, labels it with the PR and commit, refuses
   uncommitted changes, and passes the SDK the task the tests expect.
7. Observe prints state, recoveries, machine, cost so far, log tail, and run
   record for a job from a fake SDK; `--json` and `--pr` work.
8. The wrapper writes a complete run record and the final state to the
   archive for exit 0, a nonzero exit, and the `timeout`.
9. The job role's policy allows writes only under `machines/${aws:userid}/`
   and `checkpoints/`, and the admin policy mounts the same
   `checkpoints/<job name>/` path at `$COMPUTE_JOB_CHECKPOINT_DIR` on every
   attempt.
10. The watch terminates machines past their deadline, or all of them after
    the budget action fired; cancels the jobs of closed, unmerged PRs; and
    adds one `compute-job:` check run and one comment per finished job.
11. `mise run check` passes with no AWS or server credentials.
12. On the real server: a request without a token gets 401, and the `agents`
    token can't change the server's settings.
13. A `compute-job:` check run starts the Cursor Automation (checked by hand
    in the watch PR; if it doesn't, the PR comment and observing remain).

## Decisions for the owner

- Accept about $750 a month and the operating work above for (b), or
  choose (a) alone, which costs about $1 a month and has no server.
- Two nodes or one: one saves $294 a month and adds about 10 minutes'
  downtime when a node fails.
- Should agents also get a read-only S3 key, to fetch large output files and
  read results while the server is down? The client stays usable without it;
  without it, only the owner reads the archive.

## Not in this plan

T16's GPU tests on a self-hosted GPU runner need a runner, which is a
separate decision and cost; they are a follow-up.

## Pull requests after approval

Stacked, each within 500 lines: (2) the `compute/` project,
`client_config.py` with its refusal, and the CI job; (3) the job file and
`job:launch`; (4) `job:observe` and `job:cancel`; (5) the wrapper, run
record, and archive; (6) the Dockerfile and image workflow; (7) the admin
policy and `limits.yaml`; (8) `values.yaml`, `mise.admin.toml`, and the
provision, upgrade, rotate, and status tasks; (9) the watch workflow; (10)
the skills, the rule, Copier's questions, and the docs.
