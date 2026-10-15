# Compute jobs

Status: **integration layer drafted; the client isn't released yet.** Until
[foundation-compute](https://github.com/arjunbhargava/foundation-compute)
releases a version and this repository pins it, every `mise run job:*`
command exits 2 and starts nothing.

A project runs long jobs, such as GPU simulations, evolutionary searches over
simulations, and training runs, on the owner's AWS account through a shared
SkyPilot API server. The project never sees SkyPilot or AWS: it writes a job
file and runs four commands. The server, its admin tasks, and the client
package are built in
[foundation-compute](https://github.com/arjunbhargava/foundation-compute).
This repository holds only the integration: the commands below, the
`compute-jobs` skill, the `compute-cost` rule, the variables' names in
`.env.example`, and the client's pin. The design behind all of it is the
[T16 plan at commit `0a2f134`](https://github.com/arjunbhargava/foundation/blob/0a2f134ea7d5ccaf8d6bfe5f598dcc273f2049e2/docs/compute-jobs.md),
which became foundation-compute's first plan; the owner's setup steps live
with that plan, not here.

## For a user who has never used cloud

Describe the job in a small file, check it, launch it, and watch it. Nothing
starts a machine except `job:launch`, and every job stops itself at its
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

| You see | What it means | What to do |
|---|---|---|
| `The compute client, compute-jobs, isn't installed` | This repository doesn't pin a released client yet | Nothing; tell the owner if your task needs a job |
| `SKYPILOT_API_SERVER_ENDPOINT is not set ...` | This machine isn't connected to the job server | Ask the owner for the two secrets; never start a server yourself |
| `profile gpu-sim allows at most 2 nodes` | The job asks for more than the limits allow | Ask for fewer, or ask the owner to raise the limit |
| `maximum cost $180.78 exceeds budget_usd 150` | The job could cost more than you said it may | Shorten `max_runtime_minutes`, use fewer nodes, or raise `budget_usd` within your task's budget |
| `FAILED (exit 1)` in observe | Your command failed | Read the log tail observe prints, fix, push, and launch again |
| `RECOVERING` in observe | AWS took a spot machine back; the job restarts from its last checkpoint | Nothing, if the job checkpoints |
| `driver supports CUDA 12.4, image needs 12.8` | The machine's GPU driver is older than the image | Ask the owner |

## Commands

| Command | Does | Exit codes |
|---|---|---|
| `mise run job:dry-run -- <job file>` | Validates, prices, and runs a CPU smoke test on this machine unless `smoke: false`; needs no server | 0 ready, 1 invalid or the smoke test failed |
| `mise run job:launch -- <job file>` | Launches the pushed commit and prints the job's name | 0 launched, 1 rejected, 2 not configured |
| `mise run job:observe -- [<job name>] [--pr N] [--lines N] [--json]` | Shows state, recoveries, progress, machine, cost so far, run record, and log tail; with no name, lists jobs | 0 read, 1 no such job, 2 not configured |
| `mise run job:cancel -- <job name>` | Cancels a job the caller launched | 0, 1, 2 as above |

Every command also exits 2 while the client isn't installed.

## Variables

| Variable | Required | Meaning |
|---|---|---|
| `SKYPILOT_API_SERVER_ENDPOINT` | for launch, observe, cancel | The server's https:// URL |
| `SKYPILOT_SERVICE_ACCOUNT_TOKEN` | for launch, observe, cancel | The agents' token, SkyPilot role `user` |
| `COMPUTE_JOBS_AWS_ACCESS_KEY_ID`, `COMPUTE_JOBS_AWS_SECRET_ACCESS_KEY` | no | The read-only key of the IAM user `compute-jobs-observer`, so observe reads progress and outputs from the archive, also while the server is down |
| `COMPUTE_JOBS_BUCKET`, `COMPUTE_JOBS_AWS_REGION` | with the key | The archive's bucket and region |

The owner adds them as Cursor secrets; `.env.example` lists them for local
use. Without the endpoint or token, or with an endpoint that isn't https:// or
points at this machine, launch, observe, and cancel exit 2 with this message,
because the SkyPilot client underneath starts a local server when it has no
endpoint:

```text
SKYPILOT_API_SERVER_ENDPOINT is not set, so no job can be launched or
observed. This project is a client of a shared SkyPilot API server: ask the
owner to add SKYPILOT_API_SERVER_ENDPOINT and SKYPILOT_SERVICE_ACCOUNT_TOKEN
as Cursor secrets. The server is run with the compute-server-admin skill;
an agent never starts one. Nothing was started.
```

## Job file and profiles

```yaml
kind: search              # single, multi-node, or search
profile: gpu-sim          # a profile below
nodes: 2                  # multi-node and search only
command: python -m myproject.search
max_runtime_minutes: 180  # 1 to the profile's maximum
budget_usd: 200           # > 0; the task's compute budget bounds it
use_spot: false           # default; spot needs checkpoints
image: default
uv_extras: [cuda]
smoke: true               # false if the command can't run without a GPU
seed: 1234                # recorded, and passed as COMPUTE_JOB_SEED
settings:                 # free-form; recorded, and passed as JSON
  population: 10000
```

| Profile | GPU | Fits | Max nodes |
|---|---|---|---|
| `cpu` | none | CPU simulations, analysis, small drivers | 4 |
| `gpu-small` | 1 × L4 | Development, small simulations, inference | 1 |
| `gpu-sim` | L40S, 1 to 8 per node | Rendering simulators such as Isaac Sim, GPU physics, and searches | 2 |
| `gpu-train` | 8 × L40S, or 8 × A10G | Training that fits in 44 GB per GPU | 2 |

Anything that renders needs `gpu-sim`: Isaac Sim doesn't support GPUs without
RT cores, such as A100 and H100. The server's admin sets the profiles and
their limits.

## Contract v0

The interface between this repository and foundation-compute is fixed as the
"Interface" section of the
[plan at `0a2f134`](https://github.com/arjunbhargava/foundation/blob/0a2f134ea7d5ccaf8d6bfe5f598dcc273f2049e2/docs/compute-jobs.md#interface),
together with its "Progress" section. In summary:

- **Commands and exit codes:** the four above.
- **Variables:** `SKYPILOT_API_SERVER_ENDPOINT` and
  `SKYPILOT_SERVICE_ACCOUNT_TOKEN`, required; the four `COMPUTE_JOBS_*`
  variables, optional.
- **Job file:** the fields above; the job's name is
  `pr<PR number>-<file name>-<first 8 hex digits of the file's SHA-256>`.
- **Archive layout**, in the bucket: each machine writes only under
  `machines/<machine id>/` (its run record, `progress.json`, result, output,
  and log), plus an empty marker `index/<job name>/<machine id>`; checkpoints
  are under `checkpoints/<job name>/`, mounted at
  `$COMPUTE_JOB_CHECKPOINT_DIR`.
- **`progress.json`:** `schema` (1) and `updated_at` are required; `phase`,
  `step`, `step_name`, `steps_total`, `done`, `total`, `failed`, `best`
  (`name`, `value`, `higher_is_better`), and `message` are optional. The job
  writes it with `compute_jobs.progress.report(...)`.

Changing any of these needs the owner's agreement, through the T16
orchestrator, in both repositories.

## The pin

`mise.toml` holds a marked placeholder where the pin will go.
`.github/scripts/compute_job.sh`, which every `job:*` task runs, calls the
client's `compute-jobs <command>` with the task's arguments. Before that it
exits 2, starting nothing, when the client isn't on `PATH`, or when a
command other than dry-run lacks the variables or a remote https://
endpoint. The client's own exit code is passed through. When foundation-compute
releases a version, the owner replaces the placeholder with that version,
in the form its release notes give; nothing else here changes, unless the
release changes the contract.

`mise run test:compute-job-script` checks the script against a fake client.

## Who owns what

| This repository | [foundation-compute](https://github.com/arjunbhargava/foundation-compute) |
|---|---|
| `mise run job:*` and `compute_job.sh` | The client package: launch, dry-run, observe, cancel, the in-job wrapper, the run record, the archive and `progress.json` formats, `fanout`, and the job image |
| The `compute-jobs` skill and the `compute-cost` rule | The server, the admin policy, the profiles and limits, the IAM policies, provisioning and the admin tasks, and the `compute-server-admin` skill |
| The variables' names in `.env.example`, and the client's pin | Releases, the owner's setup steps, and the plan's deferred items |

## Deferred

- The Copier question `compute` (default no), which adds or leaves out this
  integration in a new project. Freed when the pin is real. Until then, a new
  project gets the `job:*` tasks, which exit 2 with the "isn't installed"
  message.
