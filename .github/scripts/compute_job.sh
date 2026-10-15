#!/usr/bin/env bash
# Runs one command of the compute client, `compute-jobs` from
# foundation-compute, for `mise run job:<command>`. docs/compute-jobs.md
# describes the commands, their exit codes, and the contract they follow.
#
# Before calling the client, it refuses, with exit code 2 and without starting
# anything, when the client isn't installed, or when a command other than
# dry-run lacks the server's endpoint or token or has an endpoint that isn't
# HTTPS or points at this machine. The SkyPilot client underneath starts a
# local API server when it has no endpoint, so this check must come first.
#
# Usage: compute_job.sh <dry-run|launch|observe|cancel> [arguments...]
set -euo pipefail

client=compute-jobs
endpoint_variable=SKYPILOT_API_SERVER_ENDPOINT
token_variable=SKYPILOT_SERVICE_ACCOUNT_TOKEN

main() {
  local command=${1:?usage: compute_job.sh <dry-run|launch|observe|cancel> [arguments...]}
  shift

  if ! command -v "$client" >/dev/null 2>&1; then
    echo "The compute client, $client, isn't installed: this repository doesn't pin foundation-compute yet, because it has released no version. Nothing was started. When a version is released, the owner replaces the placeholder pin in mise.toml (docs/compute-jobs.md, \"The pin\")." >&2
    exit 2
  fi

  if [[ $command != dry-run ]]; then
    require_variable "$endpoint_variable"
    require_variable "$token_variable"
    require_remote_https_endpoint "${!endpoint_variable}"
  fi

  exec "$client" "$command" "$@"
}

require_variable() {
  local name=$1
  if [[ -n ${!name:-} ]]; then
    return
  fi
  echo "$name is not set, so no job can be launched or
observed. This project is a client of a shared SkyPilot API server: ask the
owner to add $endpoint_variable and $token_variable
as Cursor secrets. The server is run with the compute-server-admin skill;
an agent never starts one. Nothing was started." >&2
  exit 2
}

# The endpoint is not a secret, so the message may name it.
require_remote_https_endpoint() {
  local endpoint=$1 host
  host=${endpoint#https://}
  host=${host%%/*}
  host=${host##*@}
  host=${host%:*}
  host=${host#[}
  host=${host%]}
  if [[ $endpoint != https://* ]]; then
    refuse_endpoint "$endpoint" "isn't an https:// URL"
  fi
  case $host in
    localhost | 127.* | ::1 | 0.0.0.0 | "$(hostname)")
      refuse_endpoint "$endpoint" "points at this machine"
      ;;
  esac
}

refuse_endpoint() {
  local endpoint=$1 reason=$2
  echo "$endpoint_variable is $endpoint, which $reason, so no job can be launched or observed. It must be the shared server's https:// URL; ask the owner for it. An agent never starts a server. Nothing was started." >&2
  exit 2
}

main "$@"
