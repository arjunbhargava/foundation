# Compute jobs: plan

Status: **proposed**, awaiting the owner's approval (task T16 in
[the template plan](template-plan.md)). Nothing on this page is built yet.

This page is the plan for letting agents and people run long jobs on AWS,
mostly GPU simulation (including evolutionary search over simulations) and
ordinary ML training, without needing to know SkyPilot or AWS. A user picks a
job kind and a hardware profile, runs three commands, and reads one status
view. SkyPilot (decision D4) does the launching, on the owner's AWS account,
which has negotiated rates. SkyPilot facts below come from its documentation
for 0.14.0, read on 2026-10-15. Prices are AWS on-demand list prices in
`us-east-1` from the same week; the negotiated rates are unknown, so every
ceiling below is an upper bound.

## For a user who has never used cloud

You describe the job in a small file, check it, launch it, and watch it.
Nothing starts a machine except `job:launch`, and every job stops itself at its
maximum run time.

```text
$ mise run job:dry-run -- jobs/search.yaml
jobs/search.yaml: kind search, profile gpu-sim, 2 nodes (16 L40S GPUs)
Maximum cost: 2 × $30.13/h × 3 h = $180.78 (list price), within budget_usd 200
Smoke test on this machine's CPU (COMPUTE_JOB_SMOKE=1): 2 generations, 20 evaluations, exit 0
Ready to launch.

$ mise run job:launch -- jobs/search.yaml
Launched pr81-search-3f9a2c1d. Watch it with:
  mise run job:observe -- pr81-search-3f9a2c1d

$ mise run job:observe -- pr81-search-3f9a2c1d
Job pr81-search-3f9a2c1d: RUNNING for 1 h 12 min of 3 h; cost so far about $72 (list price)
Progress: generation 12 of 50, evaluating, 6,400 of 10,000 evaluations; best fitness 0.873
```

When something fails, the message says what happened and what to do:

| You see | What it means | What to do |
|---|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT is not set ...` | This machine isn't connected to the team's job server | Ask the owner for the two secrets; never start a server yourself |
| `profile gpu-sim allows at most 2 nodes` | The job asks for more than the limits allow | Ask for fewer, or ask the owner to raise the limit |
| `maximum cost $180.78 exceeds budget_usd 150` | The job could cost more than you said it may | Shorten `max_runtime_minutes`, use fewer nodes, or raise `budget_usd` within your task's budget |
| `FAILED (exit 1)` in observe | Your command failed | Read the log tail observe prints, fix, push, and launch again |
| `RECOVERING` in observe | AWS took a spot machine back; the job is restarting from its last checkpoint | Nothing, if the job checkpoints |
| `driver supports CUDA 12.4, image needs 12.8` | The machine's GPU driver is older than your image | Use the default image, or ask the owner |

## Terms

- **API server**: SkyPilot's server, which holds the AWS credentials and the
  table of every managed job, and does the launching. A **client** is the
  `sky` command or Python SDK pointed at it.
- **Managed job**: a SkyPilot job that the API server watches, relaunching it
  after a spot preemption and deleting its machines when it ends.
- **Job file**: a YAML file in `jobs/` on a PR's branch, saying the job's
  kind, profile, command, run time, and budget.
- **Job kind**: `single`, `multi-node`, or `search` (below).
- **Hardware profile**: a named machine choice, such as `gpu-sim`, that the
  admin maps to AWS instance types in `limits.yaml`.
- **Job name**: `pr<PR number>-<job file name>-<first 8 hex digits of the job
  file's SHA-256>`, such as `pr81-search-3f9a2c1d`.
- **Job archive**: the copy of a job's run record, progress, result, logs,
  and output that the job writes to S3, so results survive the server.
- **Admin**: the person who provisions and operates the API server, with the
  `compute-server-admin` skill. Agents are clients only.

## Observing jobs from any agent

Workers and orchestrators run on separate VMs with no shared state, and must
see every job's status, progress, log tail, result, run record, and cost so
far, including a job another agent launched after that agent has stopped.
SkyPilot's state lives on the machine that runs the API server; without a
shared server, that is each launching machine, and no other machine sees it.

| | (a) Job writes its record to S3 | (b) Shared SkyPilot API server | (c) Managed jobs without (b) |
|---|---|---|---|
| Who can see a job | Anyone with a read-only S3 key | Every client: `sky jobs queue -u` lists all users' jobs | Only the launching machine |
| What an agent holds | A read-only S3 key | An endpoint and a token; no AWS launch credentials | AWS launch credentials |
| Limits enforced by | A GitHub workflow's validation | A server-side admin policy, which can reject or rewrite every request | Nothing central |
| Spot recovery | None | Automatic | Automatic |
| Standing cost | About $1 a month | About $460 a month (below) | A controller VM while jobs run |

**Recommendation: (b) with the job archive from (a).** The shared server gives
every agent the same view with an endpoint and a token, enforces limits on the
server, and recovers preempted jobs. The archive keeps results and progress
when the server isn't there. (c) fails the requirement on its own; with a
remote server, SkyPilot runs managed jobs inside it ("consolidation mode"), so
(c) becomes part of (b).

## The API server

**Where it runs.** The Helm chart on Amazon EKS, which SkyPilot recommends for
production: it alone has graceful upgrades, server-side authentication with
roles, and an external database. SkyPilot's cloud-VM deployment "does not
offer failover and graceful upgrading" and has "no authentication by default".

| Part | Choice | $/month |
|---|---|---|
| EKS control plane | Standard support, $0.10/h | 73 |
| Node | 1 × m7i.2xlarge (8 vCPU, 32 GiB, $0.4032/h) | 294 |
| Database | RDS PostgreSQL db.t4g.micro, Multi-AZ, 20 GB, 7-day backups | 28 |
| Load balancer | Application Load Balancer, with TLS | 22 |
| NAT gateway | One, for the private node | 35 |
| Other | Node disk, Route 53 zone and health check, domain | 6 |
| **Total** | | **about 460** |

One node means about 10 minutes' downtime when the node fails, while EKS
replaces it; running jobs continue meanwhile, and nothing is lost, because
state is in RDS. A second node, $294 a month more, cuts that to about a
minute. The pod gets SkyPilot's minimum of 4 CPU and 8 GiB, which serves 8
long requests (such as log tails) at once, and 16 launching and 400 running
managed jobs. A search job is one managed job however many evaluations it
runs, so this is ample.

**Authentication and TLS.** The chart's default ingress-nginx was archived by
Kubernetes on 2026-03-24 and gets no more security fixes, so it is turned off
(`ingress-nginx.enabled=false`) in favour of the AWS Load Balancer
Controller's ALB with an ACM certificate for a name such as
`skypilot.<your domain>`. The API server does basic auth itself
(`apiService.enableUserManagement=true`), which keeps SkyPilot's two roles:
`admin` (the owner) and `user`. Agents get a service-account token with the
`user` role: they can launch and read, but can't change the server's settings
or admin policy. A `user` can also cancel any job; the agents' rules forbid
it, and the archive keeps the evidence.

**Persistence and backup.** The job table, users, and tokens live in RDS, with
point-in-time restore for 7 days, so the pod is stateless.
`jobs.controller.task_logs_gc_retention_hours` is 2160 (90 days), and the
archive keeps a second copy in S3.

**Versions.** SkyPilot guarantees compatibility between adjacent minor
versions and asks that the server be upgraded first. The client is pinned once,
as `skypilot==0.14.0` in `compute/uv.lock`, run through `mise run job:*`; the
server's image and chart are pinned in `compute/server/values.yaml`; a test
fails when they name different minor versions. SkyPilot 0.14.0 supports Python
up to 3.13, so `compute/` is a uv project of its own, pinned to 3.13.

**Failures.** If the server is down, running jobs continue, but nothing can
launch, and preempted jobs wait for it. A Route 53 health check that emails
the owner, and a scheduled GitHub workflow, independent of the server, that
terminates any job machine past its maximum run time, are both
[deferred](#deferred). If the database is lost, restore it; the archive still
holds every result.

**What "set up once and forget" actually needs**, from AWS's and SkyPilot's
lifecycles (the hours are my estimate):

| Task | How often |
|---|---|
| Upgrade EKS one minor version, and its add-ons (after 14 months, standard support ends and the control plane costs $0.60/h) | About yearly |
| Update the node's AMI, for security fixes | Monthly |
| Upgrade SkyPilot, then the client pin | Each minor release |
| Rotate the agents' token (90 days) and the read-only S3 key | Quarterly |
| Answer a health-check email, once the check exists | When it fires |

About two hours a month plus half a day a year, all through the
`compute-server-admin` skill.

## Job kinds

| Kind | What runs | Typical use | Nodes |
|---|---|---|---|
| `single` | One command on one machine | A simulation, a training run, an analysis | 1 |
| `multi-node` | The same command on every node, with `MASTER_ADDR`, `NODE_RANK`, `NNODES`, and `GPUS_PER_NODE` set for `torchrun` | Distributed training | 2 to the profile's maximum |
| `search` | One driver that dispatches many short evaluations to every GPU of every node, through `compute_jobs.fanout` | Evolutionary search, sweeps of short simulations | 1 to the profile's maximum |

Every kind is one managed job, so `job:observe`, the archive, the limits, and
the recovery behaviour are the same for all three. Ten independent long runs,
such as seeds of a training run, are ten `single` jobs.

### How a search fans out

At 10,000 evaluations per generation, three SkyPilot mechanisms were
compared:

| | Ray inside one managed job | SkyPilot pools | One managed job per evaluation |
|---|---|---|---|
| How | `~/sky_templates/ray/start_cluster` on every node starts a user Ray cluster on port 6379, separate from SkyPilot's own Ray on 6380; the driver on rank 0 submits Ray tasks | A pool of identical workers; each evaluation is a managed job on a free worker | Each evaluation provisions its own machine |
| Per-evaluation overhead | Milliseconds | A managed job's scheduling, per evaluation | Minutes, to provision and set up a machine |
| Concurrency | Every GPU slot: Ray accepts fractional GPUs, such as 4 evaluations per GPU | One job per worker; SkyPilot's docs list several jobs per worker and fractional GPUs as not yet supported | The server's 16 launching jobs at once (400 running), and the quotas |
| At 10,000 per generation | 10,000 Ray tasks; with 16 L40S at 4 per GPU and 10 s each, about 26 minutes | 10,000 managed jobs per generation in the job table; beta; job files may not carry their own working directory or file mounts | Not feasible |
| Recovery | A preempted node restarts the whole job, so the driver checkpoints each generation | Per evaluation | Per evaluation |

**Recommendation: Ray inside one managed job.** It is the only mechanism whose
overhead is small next to a short evaluation, and it keeps the search one job
to observe. Its costs are that the node count is fixed for the job's life, and
that one preempted node restarts every node, so `fanout` checkpoints the
population and random state after each generation, and `search` jobs default
to on-demand machines. Users don't write Ray code:

```python
from compute_jobs import fanout, progress

for generation in fanout.resume_generations(total=50):
    candidates = optimizer.ask()
    fitness = fanout.map(evaluate, candidates, gpus_per_evaluation=0.25)
    optimizer.tell(candidates, fitness)
    progress.report(
        step=generation, step_name="generation", best=max(fitness), best_name="fitness"
    )
    fanout.checkpoint(generation, optimizer)
```

`fanout.map` connects with `ray.init(address="localhost:6379")`, never
`"auto"`, and turns off forwarding of workers' output to the driver, so 10,000
evaluations don't flood the log; it counts completed and failed evaluations in
`progress.json` instead. Outside a job, with `COMPUTE_JOB_SMOKE=1`, it runs
serially on the local machine, which is what `job:dry-run` uses.

**Spot machines.** Every kind defaults to on-demand. `use_spot: true` is
accepted for any kind; the dry run warns when the job doesn't write
checkpoints, because a preemption then restarts it from the beginning, and,
for multi-node and search jobs, preemption of any one node restarts all of
them.

## Hardware profiles

Users name a profile; the admin policy turns it into SkyPilot resources, an
ordered list of instance types tried in turn. Profiles live in
`compute/server/limits.yaml`, which only the admin changes. A profile has
families, GPUs per node, a maximum node count, a maximum run time, and
`enabled`.

| Profile | GPU, family | Fits | Per node, list price | Max nodes | Max $/h per job | Max per job-day |
|---|---|---|---|---|---|---|
| `cpu` | none; c7i, m7i | CPU simulations, analysis, small drivers | up to 16 vCPU, m7i.4xlarge $0.81/h | 4 | 3.23 | 77 |
| `gpu-small` | 1 × L4 (g6), then 1 × T4 (g4dn) | Development, small simulations, inference | g6.xlarge $0.80/h | 1 | 0.80 | 19 |
| `gpu-sim` | L40S (g6e): 1, 4, or 8 per node | Rendering simulators (Isaac Sim, RTX-based), GPU physics, and search | g6e.48xlarge, 8 GPUs, $30.13/h | 2 | 60.26 | 1,446 |
| `gpu-train` | 8 × L40S (g6e.48xlarge), then 8 × A10G (g5.48xlarge, $16.29/h) | Training that fits in 44 GB per GPU | $30.13/h | 2 | 60.26 | 1,446 |
| `gpu-train-large` | 8 × H100 (p5.48xlarge, $55.04/h), then 8 × A100 (p4d.24xlarge, $21.96/h) | Large training | $55.04/h | 2 | 110.08 | 2,642 |

`gpu-train-large` is [deferred](#deferred); when built, it is `enabled: false`
until the admin opts in.

**Which GPU fits which work.** Isaac Sim's documentation says "GPUs without RT
Cores (A100, H100) are not supported", and names g6e (L40S) for AWS; L40S, L4,
A10G, and T4 all have RT cores. So anything that renders goes on G family, and
the P family is for training and for physics that never renders. I am unsure
about three things: whether T4 (16 GB) is enough for a given scene, since
Isaac Sim's minimum is 16 GB of VRAM; whether a project's simulator needs a
newer driver than SkyPilot's AWS image has (Isaac Sim's tested driver is
595.58.03), which the wrapper's check catches but only a custom machine image
fixes; and the price and availability of G7e (RTX PRO 6000 Blackwell), which
Isaac Sim's AWS page also names. The spike checks the first two.

**Opting in to the P family.** The admin sets `enabled: true`, requests the
"Running On-Demand P instances" quota (new accounts have 0; one p5.48xlarge
needs 192 vCPUs), and reruns `compute-server:status`, which checks the account
ceiling below. On-demand P capacity is often unavailable; AWS's path to
guaranteed capacity is Capacity Blocks for ML, booked 1 to 182 days ahead and
paid up front. Whether SkyPilot 0.14.0 can target a Capacity Block is
something I haven't verified; check it at opt-in.

**Spending ceiling.** D8 caps agent compute at $10,000 a day, which is $416.67
an hour. EC2's vCPU quotas cap how much can run at once, so the worst case is
each quota filled with the dearest allowed machine per vCPU, g6e.xlarge at
$1.861 for 4 vCPUs, which is $0.465 per vCPU-hour:

| Quota | Requested | Worst $/h |
|---|---|---|
| G and VT, on demand | 384 vCPUs | 178.66 |
| G and VT, spot (at most the on-demand price) | 384 vCPUs | 178.66 |
| Standard (m7i, c7i at about $0.05 per vCPU-hour) | 64 vCPUs | 3.23 |
| P, on demand | 0 | 0 |
| **Total** | | **360.55, or $8,653 a day** |

384 G vCPUs is two g6e.48xlarge, 16 L40S, on demand, and two more on spot,
which is why `gpu-sim` and `gpu-train` allow 2 nodes; raising either means
raising the quota and rechecking this sum.
Opting in to one p5.48xlarge (192 P vCPUs, $55.04/h) means lowering the G spot
quota to 256 vCPUs, which keeps the total at $356/h. `compute-server:status`
computes this sum from the quotas and `limits.yaml`, and fails above
$416.67/h. The per-job limits are the admin policy's: profile, node count,
run time, and `budget_usd`. The daily budget action is the backstop, since AWS
budget data lags by up to a day.

## Environments

A job runs in a container image, and the dependencies come from the job's own
commit, so most users never write a Dockerfile.

- **Default:** `ghcr.io/<owner>/<repository>/compute-job`, built by this
  repository's CI from `compute/Dockerfile` on every push to `main`: an
  `nvidia/cuda` runtime image on Ubuntu 24.04 (the agents' release), pinned by
  digest, with mise and uv at the repository's pins. The job's setup runs
  `uv sync --locked` from its commit, about 1–3 minutes per attempt, so the
  job has exactly the packages the agent tested with.
- **A project's own image:** a project made from the template has the same
  Dockerfile and workflow, so it builds its own `compute-job` image in its own
  CI. For the common changes it edits `compute/image.yaml`, not the
  Dockerfile:

  ```yaml
  cuda: "12.8"                 # one of the CUDA versions the Dockerfile knows
  apt_packages: [ffmpeg, libgl1]
  base: default                # or an allowed vendor image, such as Isaac Sim's
  ```

  A vendor base, such as `nvcr.io/nvidia/isaac-sim:<version>`, is pinned by
  digest in `limits.yaml` by the admin, with the vendor's licence terms (Isaac
  Sim's container needs `ACCEPT_EULA=Y`). A job file names `image: project` to
  use it.
- **What the admin policy accepts:** an image from a repository listed in
  `limits.yaml`, by digest only, with a GitHub build-provenance attestation
  (from `actions/attest-build-provenance`) saying it was built from that
  repository's `refs/heads/main`. Agents can't push images, and the
  attestation stops a PR's workflow from passing off an image it built. Any
  other image is rejected.
- **Matching the agent's VM:** the agent's VM is x86_64 Ubuntu 24.04 with no
  GPU and no Docker (checked 2026-10-15). So profiles list only x86 families,
  and no Graviton (g5g, m7g, c7g). `uv.lock` covers every platform, so a
  project needing CUDA wheels, such as PyTorch's, declares conflicting `cpu`
  and `cuda` extras; the agent syncs `cpu`, and the job `cuda`. Before the
  command, the wrapper fails the job if the driver supports an older CUDA than
  the image, naming both. Agents can't run the image, so each image workflow
  runs the wrapper and `uv sync --locked` inside the new image on a CPU
  runner.

## Progress

A job reports progress by writing `progress.json`, through the helper
`compute_jobs.progress.report(...)`. The wrapper uploads it to the archive at
most every 30 seconds and at the end, and prints it to the log as one line
starting `COMPUTE_PROGRESS` at most every 60 seconds.

```json
{
  "schema": 1,
  "phase": "evaluating",
  "step": 12,
  "step_name": "generation",
  "steps_total": 50,
  "done": 6400,
  "total": 10000,
  "failed": 3,
  "best": {"name": "fitness", "value": 0.873, "higher_is_better": true},
  "message": "",
  "updated_at": "2026-10-15T03:26:00Z"
}
```

Every field except `schema` and `updated_at` is optional. `job:observe` shows
the latest progress first, then a log tail of 20 lines, so an agent never reads
a whole log. It reads `progress.json` from the archive, and without the
read-only S3 key, it reads the last `COMPUTE_PROGRESS` line from the log
through the server. The archive is per machine, and rank 0 writes progress.
Observe finds rank 0's machine from the first line of the job's log while the
server is up, and from `index/<job name>/` when it isn't, so the read-only key
alone serves progress, results, and logs. A job could write a false marker
under another job's name, because the job role can't be scoped to one name;
observe then shows both machines, and the watch's index from EC2 tags,
which the server sets and a job can't, is the authoritative mapping once it
is built (deferred).

## How a job runs

1. An agent commits `jobs/search.yaml` and pushes, then runs
   `mise run job:dry-run` and `mise run job:launch`. The client checks its
   configuration, names and labels the job, and submits it with
   `sky jobs launch`, uploading the working tree at the pushed commit; it
   refuses uncommitted changes.
2. On the server, the admin policy turns the kind and profile into resources,
   checks every limit, accepts only an allowed image, and forces
   `aws.remote_identity: compute-jobs-job`. Without that, SkyPilot's default
   `LOCAL_CREDENTIALS` would copy the server's launch credentials onto the
   job's machines. It wraps the command in `timeout`, mounts
   `s3://<bucket>/checkpoints/<job name>/` at `$COMPUTE_JOB_CHECKPOINT_DIR`
   (the same path on every attempt), and rejects a config that tries to
   change any of this.
3. On each machine, `python -m compute_jobs.run` checks the driver and writes
   the run record. For `single` and `multi-node` it runs the command on every
   node. For `search` it starts Ray on every node, runs the command only on
   rank 0, and keeps the other nodes as Ray workers until rank 0 exits, so
   there is one driver. It writes progress, the result, the output, and the
   log to the archive, and an empty marker, `index/<job name>/<machine id>`,
   so the archive can be found by job name without the server.
4. The server relaunches a preempted job, which resumes from its checkpoint,
   and deletes the machines when the job ends.
5. Any agent runs `mise run job:observe`.
6. Deferred: `.github/workflows/compute-watch.yml` runs every 15
   minutes, terminates machines past their deadline or all of them once the
   budget action fires, cancels the jobs of closed, unmerged PRs, and, when a
   job ends, comments on the PR and adds a check run, `compute-job: <job
   name>`, which a Cursor Automation on "CI completed" can start a follow-up
   agent from. (Cursor's "workflow run completed" trigger fires only for runs
   started by a push.)

## Interface

### Client, the default

| Variable | Required | Meaning |
|---|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT` | yes | The server's HTTPS URL |
| `SKYPILOT_SERVICE_ACCOUNT_TOKEN` | yes | The agents' token, role `user` |
| `COMPUTE_JOBS_AWS_ACCESS_KEY_ID`, `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY` | no | The read-only key of the IAM user `compute-jobs-observer`, for progress and output from the archive |
| `COMPUTE_JOBS_BUCKET`, `COMPUTE_JOBS_AWS_REGION` | with the key | The archive's bucket and region |

The first two are SkyPilot's own names, so the pinned client reads them
directly. `job:launch`, `job:observe`, and `job:cancel` check them before
calling SkyPilot. With either unset, or with an endpoint that isn't `https://`
or points at this machine, they exit 2 and start nothing, because the `sky`
client with no endpoint starts a local API server:

```text
SKYPILOT_API_SERVER_ENDPOINT is not set, so no job can be launched or
observed. This project is a client of a shared SkyPilot API server: ask the
owner to add SKYPILOT_API_SERVER_ENDPOINT and SKYPILOT_SERVICE_ACCOUNT_TOKEN
as Cursor secrets. The server is run with the compute-server-admin skill;
an agent never starts one. Nothing was started.
```

`job:dry-run` needs neither: it checks the file against a copy of the limits
and runs the command locally with `COMPUTE_JOB_SMOKE=1` and no GPU visible
(`CUDA_VISIBLE_DEVICES=""`). A job's code reads `COMPUTE_JOB_SMOKE` to run a
tiny CPU case, as `fanout` does. A command that can't run without a GPU sets
`smoke: false` in the job file; the dry run then skips the smoke test, says so,
and still exits 0 if the file is valid.

| Command | Does | Exit codes |
|---|---|---|
| `mise run job:dry-run -- <job file>` | Validates, prices, and runs a CPU smoke test locally unless `smoke: false` | 0 ready, 1 invalid or the smoke test failed |
| `mise run job:launch -- <job file>` | Launches and prints the job name | 0 launched, 1 rejected, 2 not configured |
| `mise run job:observe -- [<job name>] [--pr N] [--lines N] [--json]` | Shows state, recoveries, progress, machine, cost so far, run record, and log tail; with no name, lists jobs | 0 read, 1 no such job, 2 not configured |
| `mise run job:cancel -- <job name>` | Cancels a job the caller launched | 0, 1, 2 as above |

The job file, the same for every kind:

```yaml
kind: search              # single, multi-node, or search
profile: gpu-sim          # a profile in limits.yaml
nodes: 2                  # multi-node and search only
command: python -m myproject.search
max_runtime_minutes: 180  # 1 to the profile's maximum
budget_usd: 200           # > 0; the task's compute budget bounds it
use_spot: false           # default
image: default            # or project
uv_extras: [cuda]
smoke: true              # false if the command can't run without a GPU
seed: 1234                # recorded, and passed as COMPUTE_JOB_SEED
settings:                 # free-form; recorded, and passed as JSON
  population: 10000
```

### Admin, apart from the client

- The provisioning and operating code is in `compute/server/`: Helm values,
  the admin policy package, `limits.yaml`, IAM policy files, and scripts. It
  runs only through `MISE_ENV=admin mise run
  compute-server:<provision|status>`, and later `upgrade` and `rotate-token`
  (deferred). Those tasks and
  their tools (AWS CLI, eksctl, kubectl, Helm) are in `mise.admin.toml`, which
  mise loads only when `MISE_ENV=admin`, so `mise run check`, CI, and agents
  neither list nor install them.
- Each admin task needs the AWS CLI profile named by
  `COMPUTE_SERVER_ADMIN_AWS_PROFILE`, an IAM Identity Center login on the
  owner's machine, never a Cursor secret, and asks for the cluster name to be
  typed before changing anything.
- The always-applied `compute-cost` rule gains: "Never provision, change, or
  delete the compute API server, or run `MISE_ENV=admin` tasks, unless a
  person asked for it in this task. Never run `sky` directly; use
  `mise run job:*`." People write the rules (finding F2), so this is a draft.
- Copier asks `compute` (default no), which adds the client, and then
  `compute_server_admin` (default no), which adds `compute/server/`,
  `mise.admin.toml`, and the admin skill. A team runs one server from one
  repository; every other project needs only the client.

## Credentials

| Name | Where | Secret? | Read by |
|---|---|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT`, `SKYPILOT_SERVICE_ACCOUNT_TOKEN` | Cursor secrets | token: yes | client |
| `COMPUTE_JOBS_AWS_ACCESS_KEY_ID`, `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY`, `COMPUTE_JOBS_BUCKET`, `COMPUTE_JOBS_AWS_REGION` | Cursor secrets | key: yes | observe |
| The same endpoint, and a second `user` token | GitHub environment `compute`, limited to `main` | token: yes | watch (deferred) |
| `COMPUTE_JOBS_AWS_ROLE_ARN`, `COMPUTE_JOBS_AWS_REGION` | variables on `compute` | no | watch (deferred) |
| `COMPUTE_SERVER_ADMIN_AWS_PROFILE` | the owner's shell only | no | admin tasks |

The server's AWS identity is the role `compute-jobs-launcher`, given to its pod
through IAM Roles for Service Accounts, so no long-lived launch key exists; if
SkyPilot doesn't accept that identity, the fallback is a key in the Kubernetes
secret the chart reads, rotated every 90 days. Job machines run as
`compute-jobs-job`, which can read the bucket, write only
`machines/${aws:userid}/*` (its own archive), `index/*`, and `checkpoints/*`, and stop or
terminate only its own instance. So one job can't alter another's archive,
but could overwrite another's checkpoints, which costs at most a restart. The
read-only key exposes job logs and outputs, nothing more.

## Scope: the base first

The owner decided on 2026-10-15 to build the base now and defer the rest,
and accepted the recommended defaults: one server node, a read-only S3 key
for agents, and Copier questions that default to no. The base is enough to
run a real search end to end through the real server, and to learn what this
plan got wrong before building more. It is the nine pull requests at the end
of this page. Everything else is under [Deferred](#deferred), with its design
kept on this page and the condition that frees it.

**Hard to change later**, so the base settles them: the job file's fields and
kinds, the archive layout and `progress.json`'s schema, `job:observe`'s output
and exit codes (agents' scripts will parse them), the job name format, and the
credentials boundary (which variables a client has, and that only the admin
touches AWS). **Easy to change:** the profiles and limits, quotas, the server's
size, the image's contents, and everything deferred.

## Deferred

Each item keeps its design above; the PR that builds it moves it out of this
list.

| Item | Design | Until then | Freed when |
|---|---|---|---|
| The 15-minute watch workflow and its backstops: terminating machines past their deadline, terminating every job machine once the budget action fires, cancelling the jobs of closed, unmerged PRs, and the authoritative `index/` from EC2 tags | [How a job runs](#how-a-job-runs), step 6 | The in-job `timeout`, SkyPilot's teardown when a job ends, the quotas, and the budget action, which blocks new launches but stops no running machine; the owner can terminate machines in the EC2 console | Agents launch jobs that no person is watching, a machine is found running after its job ended, or a job's run time exceeds a day |
| The `compute-job:` check run and the Cursor Automation that starts a follow-up agent | [How a job runs](#how-a-job-runs), step 6 | Agents poll `job:observe` | A job outlasts the agent that launched it and someone must act on its result |
| Copier's `compute` and `compute_server_admin` questions | [Admin, apart from the client](#admin-apart-from-the-client) | `copier.yml` leaves out `compute/`, `mise.admin.toml`, and both skills, so a new project has neither part, which matches the accepted defaults | The first project made from the template needs compute jobs |
| Project images beyond the default: `compute/image.yaml`, vendor bases such as Isaac Sim's, and other repositories in the allowlist | [Environments](#environments) | Every job runs the default image | A project needs a system package, CUDA version, or simulator that the default image lacks |
| The `gpu-train-large` profile (P family), and fan-out beyond the spike: more than 2 nodes, or more GPUs than the base quotas allow | [Hardware profiles](#hardware-profiles), [How a search fans out](#how-a-search-fans-out) | `gpu-train` and `gpu-sim` with at most 2 nodes | A project needs H100 or A100, or a search needs more than 16 L40S at once; both need new quotas and a rechecked ceiling |
| A second server node, the Route 53 health check, automated token rotation, and the upgrade and restore procedures | [The API server](#the-api-server) | One node; the owner notices an outage when a command fails; tokens are rotated by hand in the dashboard before they expire; RDS keeps 7 days of backups, and the archive keeps every result | A node failure's 10 minutes of downtime matters; jobs run unattended; the first token is 2 weeks from expiry; the first SkyPilot upgrade; the job table holds history someone relies on |

## Setup for the owner

Each step works in a phone browser except 5 and 9, which run admin tasks from
a laptop. Steps 1–4 can start now; the rest wait for the provisioning PR.

1. Create an AWS account for agent jobs, `agent-jobs`, under the negotiated
   agreement, and sign in to it with IAM Identity Center:
   <https://console.aws.amazon.com/organizations/v2/home/accounts>.
2. Request vCPU quotas in `us-east-1`: "Running On-Demand G and VT instances"
   384, "All G and VT Spot Instance Requests" 384, and check that "Running
   On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" is at most 64;
   leave "Running On-Demand P instances" at 0:
   <https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas>.
3. Pick the server's host name, such as `skypilot.<your domain>`, and create a
   Route 53 hosted zone for the domain, registering one (about $15 a year) if
   you have none: <https://console.aws.amazon.com/route53/v2/hostedzones>.
4. Add GitHub as an identity provider: OpenID Connect, URL
   `https://token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`:
   <https://console.aws.amazon.com/iam/home#/identity_providers/create>.
5. On a laptop with the AWS CLI logged in to `agent-jobs`, set
   `COMPUTE_SERVER_ADMIN_AWS_PROFILE` and run
   `MISE_ENV=admin mise run compute-server:provision`. From the committed
   files, it creates the EKS cluster, the RDS database, the ACM certificate,
   the S3 bucket (private, 90-day expiry), the roles `compute-jobs-launcher`
   and `compute-jobs-job`, the policy `compute-jobs-deny-launch`, the IAM user
   `compute-jobs-observer` and its key, and the server with its admin policy.
   It prints the
   endpoint, the dashboard URL, and the observer key once.
6. Open the dashboard, change the initial admin password, and create a
   service account named `agents`, with role `user` and 90-day expiry. Note
   the expiry date; rotating it by hand before then is your job until
   rotation is automated.
7. Add the Cursor secrets `SKYPILOT_API_SERVER_ENDPOINT`,
   `SKYPILOT_SERVICE_ACCOUNT_TOKEN` (the `agents` token),
   `COMPUTE_JOBS_AWS_ACCESS_KEY_ID`, `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY`,
   `COMPUTE_JOBS_BUCKET`, and `COMPUTE_JOBS_AWS_REGION`:
   <https://cursor.com/dashboard>, Cloud Agents > Secrets.
8. Create a daily cost budget, `compute-jobs-daily`, of $10,000, with email
   alerts at 50% and 80%, and an action at 100% of actual cost that applies
   `compute-jobs-deny-launch` to `compute-jobs-launcher` automatically:
   <https://console.aws.amazon.com/costmanagement/home#/budgets/create>.
   Alerts alone don't stop spend; the action and the quotas do.
9. Run `MISE_ENV=admin mise run compute-server:status`. It checks that a
   request without a token is rejected, that the `agents` token can't change
   the server's settings, that the admin policy rejects a job over the limits,
   that the budget action exists, and that the quota ceiling is at most
   $416.67 an hour.
10. If Cursor's agent network allowlist is on, add the server's host name and
    `<bucket>.s3.us-east-1.amazonaws.com`.
11. Give the spike task a compute budget, in its Linear issue: $10 covers it.
12. Deferred, with the watch: create the GitHub environment `compute`, limited to `main`, with
    a `watch` token, the endpoint, `COMPUTE_JOBS_AWS_ROLE_ARN` (the
    `compute-jobs-watch` ARN that the watch's PR adds), and
    `COMPUTE_JOBS_AWS_REGION`:
    <https://github.com/arjunbhargava/foundation/settings/environments/new>;
    then a Cursor Automation on "CI completed", filtered to checks named
    `compute-job:`: <https://cursor.com/automations>.

## Files touched

- `compute/`: a uv project pinned to Python 3.13, with `skypilot==0.14.0`
  (Apache-2.0) as the client, boto3 (Apache-2.0) for the archive, Ray
  (Apache-2.0) for `fanout`, and moto (Apache-2.0) to fake S3 and EC2 in
  tests. Package `compute_jobs`: `client_config.py`, `job_file.py`,
  `dry_run.py`, `launch.py`, `observe.py`, `run.py` (the wrapper),
  `run_record.py`, `archive.py`, `progress.py`, and `fanout.py`; plus
  `Dockerfile` and `tests/`; and `examples/toy_search/`, the spike.
  `image.yaml` is deferred.
- `compute/server/`: `values.yaml`, `admin_policy/` (with its own tests),
  `limits.yaml`, `aws/*.json`, and the provision and status scripts (upgrade
  and rotate are deferred); `mise.admin.toml`.
- `.github/workflows/`: `compute-image.yml` (build and attest on pushes to
  `main`, then the smoke test), and a `compute` job in `ci.yml`;
  `compute-watch.yml` is deferred.
- `mise.toml`: `setup:compute`, `lint:compute`, `test:compute`, and
  `job:dry-run`, `job:launch`, `job:observe`, `job:cancel`.
- `.github/dependabot.yml` and its `.jinja` twin, through
  `mise run template:sync` (the `docker` ecosystem for `compute/`).
- `.env.example`, `.github/CODEOWNERS` (`compute/server/`), `copier.yml`
  (excluding the compute parts until its questions land),
  `docs/conf.py`, `AGENTS.md` and its `.jinja` twin, `docs/architecture.md`,
  and this page, rewritten to describe what was built.
- The `compute-jobs` and `compute-server-admin` skills, and the
  `compute-cost` rule, drafted for the owner to edit (finding F2).

## Acceptance criteria

Each becomes a named test that needs no AWS account, network, or server,
except those marked "on the real server", which `compute-server:status` or the
spike checks.

1. With `SKYPILOT_API_SERVER_ENDPOINT` or `SKYPILOT_SERVICE_ACCOUNT_TOKEN`
   unset, or the endpoint not `https://` or local, `job:launch`,
   `job:observe`, and `job:cancel` exit 2; the message names both variables,
   the `compute-server-admin` skill, and the owner; and a fake `sky` on `PATH`
   records no call.
2. The default mise configuration lists no `compute-server:` task, and those
   tasks exit with a message when `COMPUTE_SERVER_ADMIN_AWS_PROFILE` is unset.
3. A project made from the template has no `compute/`, `mise.admin.toml`, or
   compute skill (the Copier questions are deferred).
4. The server pin in `values.yaml` and the client pin in `compute/uv.lock`
   name the same minor version.
5. The job file accepts each kind with its fields and rejects a missing or
   unknown kind or profile, `nodes` on a `single` job, and `nodes` above the
   profile's maximum.
6. The admin policy maps each profile to its ordered instance types; rejects a
   disabled profile, a job over any limit, without `budget_usd` or over it, an
   image not allowed or not by digest, and a config that sets
   `remote_identity` or `admin_policy`; and rewrites every accepted job with
   `remote_identity: compute-jobs-job`, the `timeout` wrapper, and the
   checkpoint mount.
7. `job:dry-run` prints the maximum cost and runs the smoke test with no GPU
   visible; with `smoke: false` it skips it and exits 0 for a valid file; it
   warns on spot without checkpoints.
8. In a 2-node `search` job, the command runs once, on rank 0, and the
   other node's GPUs receive evaluations. `fanout.map` returns results in the
   candidates' order, counts failures in
   progress, and runs serially with `COMPUTE_JOB_SMOKE=1`;
   `resume_generations` resumes after the last checkpoint.
9. `progress.report` writes a valid `progress.json`; the wrapper uploads it at
   most every 30 s; observe shows it from the archive, finding the machine
   through `index/` when the server is down, and, without the S3 key, from the
   last `COMPUTE_PROGRESS` log line.
10. Observe prints state, recoveries, progress, machine, cost so far, log
    tail, and run record for every kind, from a fake SDK; `--json` and `--pr`
    work.
11. The wrapper writes a complete run record and final state for exit 0, a
    nonzero exit, and the `timeout`, and fails before the command when a fake
    `nvidia-smi` reports an older CUDA than the image's.
12. The job role allows writes only under `machines/${aws:userid}/`,
    `index/`, and `checkpoints/`.
13. The quota ceiling check fails above $416.67 an hour.
14. `mise run check` passes with no AWS or server credentials.
15. On the real server: a request without a token gets 401, the `agents`
    token can't change the server's settings, and the spike's search finishes
    5 generations with progress visible from a second agent.
16. The image workflow's smoke test passes inside the built image, and the
    policy rejects an image without a `main` attestation.
17. Deferred, with the watch: it terminates overdue machines and adds one
    `compute-job:` check run per finished job, and the check run starts the
    Cursor Automation (checked by hand).

## Decisions

Accepted by the owner on 2026-10-15, as recommended:

- One server node ($460 a month).
- Agents get the read-only S3 key, so progress and outputs work while the
  server is down.
- Copier's questions, when they come, default to no.
- Every job defaults to on-demand machines; spot is opt-in.
- The fan-out mechanism is Ray inside one managed job.

## Pull requests after approval

Stacked, in this order; each is useful when it merges, and within 500 lines.

1. The `compute/` project, `client_config.py` with its refusal, `copier.yml`'s
   exclusion of the compute parts, and the CI job. Useful: the refusal is in
   place before anything can launch.
2. The job file with kinds and profiles, `job:dry-run`, and `job:launch`.
   Useful: agents can write and check job files.
3. `job:observe` and `job:cancel`, and `progress.py` with the `progress.json`
   schema. Useful: the observe format is fixed before anything writes it.
4. The wrapper, run record, and archive. Useful: a job's machine records
   everything observe reads.
5. The default image and `compute-image.yml`, with its attestation and smoke
   test. Useful: the job environment exists and is tested.
6. The admin policy and `limits.yaml`, with the `cpu`, `gpu-small`,
   `gpu-sim`, and `gpu-train` profiles and the quota ceiling check. Useful:
   limits are enforced in code before a server exists.
7. Server provisioning and the admin tasks: `values.yaml`, `mise.admin.toml`,
   the IAM files, and `compute-server:provision` and `compute-server:status`
   for a one-node server. Useful: the owner can stand up the server.
8. The `compute-jobs` and `compute-server-admin` skills, and the
   `compute-cost` rule's update, drafted for the owner to edit. Useful:
   agents know the rules before the first real job.
9. The spike: `fanout.py`, `examples/toy_search/`, and the run through the
   real server, with `docs/architecture.md` and this page updated to describe
   what was built. Useful: the design is proved end to end.
