#!/usr/bin/env bash
# Tests .github/scripts/linear_queue.sh without calling Linear. Each case runs
# the script against a fake curl that answers each GraphQL request from a file
# named after the request's operationName, and logs every request, so a case
# can check what the script sent as well as what it printed.
#
# Usage: mise run test:linear-queue-script
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/linear_queue.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
case_count=0
# A value that must never appear in a command line or in the script's output.
export LINEAR_API_KEY=lin_api_test_key_do_not_print

main() {
  make_fake_curl

  list_cases
  create_cases
  delegate_cases
  failure_cases

  if ((failures > 0)); then
    exit 1
  fi
  echo "linear_queue.sh gave the expected output and requests in all $case_count cases."
}

# Puts first on PATH a curl that logs its arguments, the config file it is
# given, and its request body, then answers with
# $FAKE_LINEAR/<operationName>.json, or, for a request whose variable "after"
# is set, $FAKE_LINEAR/<operationName>.after-<after>.json.
make_fake_curl() {
  mkdir "$work/bin"
  cat > "$work/bin/curl" << 'EOF'
#!/usr/bin/env bash
request=$(cat)
printf '%s\n' "$*" >> "$FAKE_LINEAR/curl_arguments.log"
for ((position = 1; position < $#; position++)); do
  if [[ ${!position} == --config ]]; then
    next=$((position + 1))
    cat "${!next}" >> "$FAKE_LINEAR/curl_config.log"
  fi
done
printf '%s\n' "$request" >> "$FAKE_LINEAR/requests.log"
operation=$(jq -r .operationName <<< "$request")
after=$(jq -r '.variables.after // empty' <<< "$request")
response_file=$FAKE_LINEAR/$operation.json
if [[ -n $after ]]; then
  response_file=$FAKE_LINEAR/$operation.after-$after.json
fi
if [[ ! -r $response_file ]]; then
  echo "fake curl: no response file for $operation" >&2
  exit 1
fi
cat "$response_file"
EOF
  chmod +x "$work/bin/curl"
  PATH=$work/bin:$PATH
}

# Starts a case with an empty folder of fake responses and requests.
new_case() {
  FAKE_LINEAR=$work/case_$((++case_count))
  export FAKE_LINEAR
  mkdir "$FAKE_LINEAR"
}

# Arguments: the name of a response file, without ".json", such as an
# operationName, and the response's "data" object.
respond() {
  jq -n --argjson data "$2" '{data: $data}' > "$FAKE_LINEAR/$1.json"
}

# Arguments: the issue's identifier; its label names, comma-separated; the
# states of its blocking issues, comma-separated, or "-" for none; and
# optionally the owner/name label on its project, or "-". Prints one node as
# the ListQueue response lists it.
queue_node() {
  local identifier=$1 labels=$2 blocker_states=$3 project_repo=${4:--}
  jq -n --arg id "$identifier" --arg labels "$labels" --arg blockers "$blocker_states" --arg project "$project_repo" '
    def label_node(name): {name: name, parent: (if (name | contains("/")) then {name: "repo"} else null end)};
    { identifier: $id, title: "Title of \($id)", url: "https://linear.app/t/issue/\($id)", delegate: null,
      labels: {nodes: ($labels | split(",") | map(label_node(.)))},
      project: {labels: {nodes: (if $project == "-" then [] else [label_node($project)] end)}},
      inverseRelations: {nodes: (if $blockers == "-" then [] else ($blockers | split(",") | map({type: "blocks", issue: {state: {type: .}}})) end)} }'
}

# Arguments: the nodes of one ListQueue page, as a JSON array, and whether
# another page follows ("true" or "false").
queue_page() {
  jq -n --argjson nodes "$1" --arg more "$2" \
    '{issues: {pageInfo: {hasNextPage: ($more == "true"), endCursor: "cursor1"}, nodes: $nodes}}'
}

# Arguments: the case's name, the script's arguments' words, the exit status
# expected, and text the output (standard output and error) must contain.
# Sets output for the caller's further checks.
output=""
expect_run() {
  local name=$1 expected_status=$2 expected_text=$3
  shift 3
  local status=0
  output=$("$script" "$@" 2>&1) || status=$?
  if ((status != expected_status)) || [[ $output != *"$expected_text"* ]]; then
    fail "$name" "exit status $status (expected $expected_status), output:
$output
(expected it to contain: $expected_text)"
  fi
}

fail() {
  echo "FAIL: $1: $2" >&2
  failures=$((failures + 1))
}

# Arguments: the case's name, the JSON the script printed, a jq expression
# that must be true of it.
expect_json() {
  if ! jq -e "$3" <<< "$2" > /dev/null 2>&1; then
    fail "$1" "expected the output to satisfy: $3
output: $2"
  fi
}

list_cases() {
  new_case
  respond ListQueue "$(queue_page "$(jq -n \
    --argjson blocked "$(queue_node T-1 agent-ready started)" \
    --argjson blocked_by_unstarted "$(queue_node T-2 agent-ready unstarted,completed)" \
    '[$blocked, $blocked_by_unstarted]')" false)"
  expect_run lists_nothing_while_every_blocker_is_unfinished 0 "[]" list
  expect_json lists_nothing_while_every_blocker_is_unfinished "$output" 'length == 0'

  new_case
  respond ListQueue "$(queue_page "$(jq -n \
    --argjson finished "$(queue_node T-3 agent-ready completed)" \
    --argjson canceled "$(queue_node T-4 agent-ready canceled,completed)" \
    '[$finished, $canceled]')" false)"
  expect_run lists_an_issue_whose_blockers_are_done_or_canceled 0 T-3 list
  expect_json lists_an_issue_whose_blockers_are_done_or_canceled "$output" 'map(.identifier) == ["T-3", "T-4"]'

  new_case
  respond ListQueue "$(queue_page "$(jq -n \
    --argjson first "$(queue_node T-5 agent-ready,arjunbhargava/foundation -)" \
    --argjson second "$(queue_node T-6 agent-ready,arjunbhargava/foundation-compute -)" \
    '[$first, $second]')" false)"
  expect_run lists_two_independent_issues_with_their_repositories 0 T-5 list
  expect_json lists_two_independent_issues_with_their_repositories "$output" \
    'map({identifier, repo}) == [{identifier: "T-5", repo: "arjunbhargava/foundation"}, {identifier: "T-6", repo: "arjunbhargava/foundation-compute"}]'

  new_case
  delegated=$(queue_node T-7 agent-ready - | jq '.delegate = {id: "someone"}')
  respond ListQueue "$(queue_page "$(jq -n \
    --argjson person "$(queue_node T-8 agent-ready,needs-person -)" \
    --argjson delegated "$delegated" \
    --argjson plain "$(queue_node T-9 agent-ready -)" \
    '[$person, $delegated, $plain]')" false)"
  expect_run skips_needs_person_and_delegated_issues 0 T-9 list
  expect_json skips_needs_person_and_delegated_issues "$output" 'map(.identifier) == ["T-9"]'
  expect_json asks_linear_only_for_agent_ready_issues "$(jq -s '.[0].variables' "$FAKE_LINEAR/requests.log")" \
    '.readyLabel == "agent-ready"'

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson node "$(queue_node T-10 agent-ready - arjunbhargava/foundation)" '[$node]')" false)"
  expect_run takes_the_repository_from_the_project_when_the_issue_has_none 0 T-10 list
  expect_json takes_the_repository_from_the_project_when_the_issue_has_none "$output" '.[0].repo == "arjunbhargava/foundation"'

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson node "$(queue_node T-11 agent-ready -)" '[$node]')" true)"
  jq -n --argjson page "$(queue_page "$(jq -n --argjson node "$(queue_node T-12 agent-ready -)" '[$node]')" false)" \
    '{data: $page}' > "$FAKE_LINEAR/ListQueue.after-cursor1.json"
  expect_run lists_issues_from_every_page 0 T-12 list
  expect_json lists_issues_from_every_page "$output" 'map(.identifier) == ["T-11", "T-12"]'
}

# Writes the fake responses a create needs, for a workspace whose only team
# is TEAM, with the issue label names in the arguments and one project that
# carries the label "arjunbhargava/foundation".
respond_to_create() {
  respond ListTeams '{"teams": {"nodes": [{"id": "team-1", "key": "TEAM"}]}}'
  respond FindLabel '{"issueLabels": {"nodes": [{"id": "label-1"}]}}'
  respond FindProject '{"projects": {"nodes": [{"id": "project-1", "labels": {"nodes": [{"name": "arjunbhargava/foundation"}]}}]}}'
  respond FindParent '{"issue": {"id": "parent-1"}}'
  respond CreateIssue '{"issueCreate": {"issue": {"identifier": "TEAM-7"}}}'
}

create_cases() {
  printf 'The description.\n' > "$work/description.md"

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  expect_run creates_an_issue_that_does_not_exist 0 TEAM-7 \
    create --title "Fix it" --description-file "$work/description.md" --repo arjunbhargava/foundation --parent TEAM-1
  create_request=$(jq -s 'map(select(.operationName == "CreateIssue")) | .[0].variables.input' "$FAKE_LINEAR/requests.log")
  expect_json creates_an_issue_that_does_not_exist "$create_request" \
    '.title == "Fix it" and .teamId == "team-1" and .projectId == "project-1" and .parentId == "parent-1"
     and .labelIds == ["label-1"] and .description == "The description.\n"'

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": [{"identifier": "TEAM-3"}]}}'
  expect_run reuses_the_issue_that_already_has_the_title 0 TEAM-3 \
    create --title "Fix it" --description-file "$work/description.md"
  if jq -e -s 'any(.[]; .operationName == "CreateIssue")' "$FAKE_LINEAR/requests.log" > /dev/null; then
    fail reuses_the_issue_that_already_has_the_title "the script created a second issue"
  fi

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  respond FindLabel '{"issueLabels": {"nodes": []}}'
  expect_run fails_without_creating_when_a_label_does_not_exist 1 "no issue label named 'typo-label'" \
    create --title "Fix it" --description-file "$work/description.md" --label typo-label
  if [[ -r $FAKE_LINEAR/requests.log ]] && jq -e -s 'any(.[]; .operationName == "CreateIssue")' "$FAKE_LINEAR/requests.log" > /dev/null; then
    fail fails_without_creating_when_a_label_does_not_exist "the script created the issue anyway"
  fi

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  respond ListTeams '{"teams": {"nodes": [{"id": "team-1", "key": "ONE"}, {"id": "team-2", "key": "TWO"}]}}'
  expect_run fails_when_there_are_several_teams_and_no_team_key 1 "set LINEAR_TEAM_KEY to one of: ONE, TWO" \
    create --title "Fix it" --description-file "$work/description.md"
  LINEAR_TEAM_KEY=TWO expect_run creates_in_the_team_named_by_the_team_key 0 TEAM-7 \
    create --title "Fix it" --description-file "$work/description.md"
  expect_json creates_in_the_team_named_by_the_team_key \
    "$(jq -s 'map(select(.operationName == "CreateIssue")) | .[0].variables.input' "$FAKE_LINEAR/requests.log")" '.teamId == "team-2"'
}

delegate_cases() {
  new_case
  respond ListApps '{"users": {"nodes": [{"id": "person-1", "name": "Cursor", "app": false}, {"id": "app-1", "name": "Cursor", "app": true}]}}'
  respond DelegateIssue '{"issueUpdate": {"issue": {"identifier": "TEAM-9"}}}'
  expect_run delegates_to_the_cursor_app_user_not_a_person_of_that_name 0 "Delegated TEAM-9 to Cursor." delegate TEAM-9
  expect_json delegates_to_the_cursor_app_user_not_a_person_of_that_name \
    "$(jq -s 'map(select(.operationName == "DelegateIssue")) | .[0].variables' "$FAKE_LINEAR/requests.log")" \
    '.id == "TEAM-9" and .delegate == "app-1"'
}

failure_cases() {
  new_case
  (
    unset LINEAR_API_KEY
    expect_run names_the_missing_api_key 1 "LINEAR_API_KEY is not set" list
  )

  new_case
  expect_run rejects_an_unknown_command 1 "unknown command 'frobnicate'" frobnicate

  new_case
  jq -n '{errors: [{message: "Entity not found: Issue"}]}' > "$FAKE_LINEAR/ListApps.json"
  expect_run reports_the_messages_of_a_graphql_error 1 "Entity not found: Issue" delegate TEAM-9

  new_case
  respond ListQueue "$(queue_page '[]' false)"
  expect_run sends_the_key_in_a_config_file_and_never_prints_it 0 "[]" list
  if grep -qF "$LINEAR_API_KEY" "$FAKE_LINEAR/curl_arguments.log" || [[ $output == *"$LINEAR_API_KEY"* ]]; then
    fail sends_the_key_in_a_config_file_and_never_prints_it "the key appeared in curl's arguments or in the output"
  fi
  if ! grep -qF "Authorization: $LINEAR_API_KEY" "$FAKE_LINEAR/curl_config.log"; then
    fail sends_the_key_in_a_config_file_and_never_prints_it "curl's config file had no Authorization header with the key"
  fi
}

main "$@"
