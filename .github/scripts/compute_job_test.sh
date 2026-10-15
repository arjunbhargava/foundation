#!/usr/bin/env bash
# Tests .github/scripts/compute_job.sh against a fake compute client: each case
# sets the server's variables, runs one command, and checks the exit code, the
# message, and whether, and with which arguments, the client was called.
#
# Usage: mise run test:compute-job-script
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/compute_job.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

valid_endpoint=https://skypilot.example.com

main() {
  make_fake_client

  expect refuses_every_command_when_the_client_is_not_installed \
    no-client "$valid_endpoint" token 0 "observe pr81-search-3f9a2c1d" \
    2 "isn't installed" not-called
  expect refuses_launch_when_the_endpoint_is_unset \
    client "" token 0 "launch jobs/search.yaml" \
    2 "SKYPILOT_API_SERVER_ENDPOINT is not set" not-called
  expect names_both_variables_and_the_admin_skill_when_one_is_unset \
    client "$valid_endpoint" "" 0 "observe pr81-search-3f9a2c1d" \
    2 "add SKYPILOT_API_SERVER_ENDPOINT and SKYPILOT_SERVICE_ACCOUNT_TOKEN
as Cursor secrets. The server is run with the compute-server-admin skill" not-called
  expect refuses_an_endpoint_that_is_not_https \
    client "http://skypilot.example.com" token 0 "cancel pr81-search-3f9a2c1d" \
    2 "isn't an https:// URL" not-called
  expect refuses_an_endpoint_on_this_machine \
    client "https://localhost:46580" token 0 "launch jobs/search.yaml" \
    2 "points at this machine" not-called
  expect refuses_a_loopback_address_with_credentials \
    client "https://user:pass@127.0.0.1:46580/" token 0 "launch jobs/search.yaml" \
    2 "points at this machine" not-called
  expect runs_dry_run_without_the_server_variables \
    client "" "" 0 "dry-run jobs/search.yaml" \
    0 "" "dry-run jobs/search.yaml"
  expect passes_observe_arguments_and_exit_code_through \
    client "$valid_endpoint" token 1 "observe pr81-search-3f9a2c1d --lines 5" \
    1 "" "observe pr81-search-3f9a2c1d --lines 5"
  expect passes_the_clients_configuration_exit_code_through \
    client "$valid_endpoint" token 2 "launch jobs/search.yaml" \
    2 "" "launch jobs/search.yaml"

  if ((failures > 0)); then
    exit 1
  fi
  echo "compute_job.sh refused or called the client as expected in all 9 cases."
}

# A fake client that records its arguments and exits with $FAKE_EXIT_CODE.
make_fake_client() {
  mkdir -p "$work/with-client" "$work/without-client"
  cat >"$work/with-client/compute-jobs" <<'EOF'
#!/usr/bin/env bash
echo "$*" >"$FAKE_CALL_LOG"
exit "$FAKE_EXIT_CODE"
EOF
  chmod +x "$work/with-client/compute-jobs"
}

# Arguments: the case's name; "client" or "no-client"; the endpoint and the
# token ("" leaves the variable unset); the fake client's exit code; the
# command and its arguments; the expected exit code; text the output must
# contain ("" for none); and the arguments the client must receive, or
# "not-called".
expect() {
  local name=$1 client=$2 endpoint=$3 token=$4 fake_exit_code=$5 arguments=$6
  local expected_status=$7 expected_text=$8 expected_call=$9
  local bin=$work/without-client status=0 output call=not-called
  if [[ $client == client ]]; then
    bin=$work/with-client
  fi
  rm -f "$work/call"

  local -a environment=(env -u SKYPILOT_API_SERVER_ENDPOINT -u SKYPILOT_SERVICE_ACCOUNT_TOKEN
    "PATH=$bin:/usr/bin:/bin" "FAKE_CALL_LOG=$work/call" "FAKE_EXIT_CODE=$fake_exit_code")
  if [[ -n $endpoint ]]; then
    environment+=("SKYPILOT_API_SERVER_ENDPOINT=$endpoint")
  fi
  if [[ -n $token ]]; then
    environment+=("SKYPILOT_SERVICE_ACCOUNT_TOKEN=$token")
  fi
  # shellcheck disable=SC2086 # The arguments are split into words on purpose.
  output=$("${environment[@]}" bash "$script" $arguments 2>&1) || status=$?
  if [[ -f $work/call ]]; then
    call=$(<"$work/call")
  fi

  if ((status != expected_status)) || [[ $output != *"$expected_text"* || $call != "$expected_call" ]]; then
    echo "FAIL: $name: exited with status $status (expected $expected_status), called the client with: $call (expected: $expected_call), printed:
$output
(expected it to contain: $expected_text)" >&2
    failures=$((failures + 1))
  fi
}

main "$@"
