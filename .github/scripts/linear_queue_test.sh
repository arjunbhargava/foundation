#!/usr/bin/env bash
# Tests .github/scripts/linear_queue.sh without calling Linear, against a fake
# curl that answers each GraphQL request from a file named after its
# operationName and logs every request.
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

# Puts first on PATH a curl that logs its arguments, config file, and request
# body, then answers with $FAKE_LINEAR/<operationName>.json, or, when the
# request's variable "after" is set, <operationName>.after-<after>.json.
make_fake_curl() {
  mkdir "$work/bin"
  cat > "$work/bin/curl" << 'EOF'
#!/usr/bin/env bash
request=$(cat)
printf '%s\n' "$*" >> "$FAKE_LINEAR/curl_arguments.log"
while (($# > 0)); do
  [[ $1 == --config ]] && cat "$2" >> "$FAKE_LINEAR/curl_config.log"
  shift
done
printf '%s\n' "$request" >> "$FAKE_LINEAR/requests.log"
operation=$(jq -r .operationName <<< "$request")
after=$(jq -r '.variables.after // empty' <<< "$request")
response_file=$FAKE_LINEAR/$operation${after:+.after-$after}.json
[[ -r $response_file ]] || { echo "fake curl: no response file for $operation" >&2; exit 1; }
cat "$response_file"
EOF
  chmod +x "$work/bin/curl"
  PATH=$work/bin:$PATH
}

new_case() {
  FAKE_LINEAR=$work/case_$((++case_count))
  export FAKE_LINEAR
  mkdir "$FAKE_LINEAR"
}

# Arguments: an operationName, and the "data" object of its response.
respond() {
  jq -n --argjson data "$2" '{data: $data}' > "$FAKE_LINEAR/$1.json"
}

# Arguments: an issue's identifier; its label names and the states of its
# blockers, each comma-separated or "-" for none; optionally its project's
# owner/name label. Prints the node as ListQueue lists it.
queue_node() {
  local identifier=$1 labels=$2 blocker_states=$3 project_repo=${4:--}
  jq -n --arg id "$identifier" --arg labels "$labels" --arg blockers "$blocker_states" --arg project "$project_repo" '
    def label_node(name): {name: name, parent: (if (name | contains("/")) then {name: "repo"} else null end)};
    { identifier: $id, title: "Title of \($id)", url: "https://linear.app/t/issue/\($id)", delegate: null,
      labels: {nodes: ($labels | split(",") | map(label_node(.)))},
      project: {labels: {nodes: (if $project == "-" then [] else [label_node($project)] end)}},
      inverseRelations: {nodes: (if $blockers == "-" then [] else ($blockers | split(",") | map({type: "blocks", issue: {state: {type: .}}})) end)} }'
}

# Arguments: a ListQueue page's nodes as a JSON array, and "true" if more follow.
queue_page() {
  jq -n --argjson nodes "$1" --arg more "$2" \
    '{issues: {pageInfo: {hasNextPage: ($more == "true"), endCursor: "cursor1"}, nodes: $nodes}}'
}

# Arguments: the case's name, the exit status expected, text the output must
# contain, then the script's arguments. Sets output for further checks.
output=""
expect_run() {
  local name=$1 expected_status=$2 expected_text=$3
  shift 3
  local status=0
  output=$("$script" "$@" 2>&1) || status=$?
  if ((status != expected_status)) || [[ $output != *"$expected_text"* ]]; then
    fail "$name" "exit status $status (expected $expected_status), output: $output (expected it to contain: $expected_text)"
  fi
}

fail() {
  echo "FAIL: $1: $2" >&2
  failures=$((failures + 1))
}

# Arguments: the case's name, the JSON the script printed, a jq expression
# that must be true of it.
expect_json() {
  jq -e "$3" <<< "$2" > /dev/null 2>&1 || fail "$1" "expected $2 to satisfy: $3"
}

# Arguments: a case's name, and the identifiers "list" must print, in order.
expect_listed() {
  expect_run "$1" 0 "" list
  expect_json "$1" "$output" "map(.identifier) | join(\",\") == \"$2\""
}

list_cases() {
  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson a "$(queue_node T-1 agent-ready started)" \
    --argjson b "$(queue_node T-2 agent-ready unstarted,completed)" '[$a, $b]')" false)"
  expect_listed lists_nothing_while_a_blocker_is_unfinished ""

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson a "$(queue_node T-3 agent-ready completed)" \
    --argjson b "$(queue_node T-4 agent-ready canceled,completed)" '[$a, $b]')" false)"
  expect_listed lists_an_issue_whose_blockers_are_done_or_canceled "T-3,T-4"

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson a "$(queue_node T-5 agent-ready,arjunbhargava/foundation -)" \
    --argjson b "$(queue_node T-6 agent-ready - arjunbhargava/foundation-compute)" '[$a, $b]')" false)"
  expect_listed lists_two_independent_issues "T-5,T-6"
  expect_json names_the_repository_from_the_issue_or_else_its_project "$output" \
    '.[0].repo == "arjunbhargava/foundation" and .[1].repo == "arjunbhargava/foundation-compute"'

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson a "$(queue_node T-8 agent-ready,needs-person -)" \
    --argjson b "$(queue_node T-7 agent-ready - | jq '.delegate = {id: "someone"}')" \
    --argjson c "$(queue_node T-9 agent-ready -)" '[$a, $b, $c]')" false)"
  expect_listed skips_needs_person_and_delegated_issues "T-9"
  expect_json asks_linear_only_for_agent_ready_issues "$(jq -s '.[0].variables' "$FAKE_LINEAR/requests.log")" \
    '.readyLabel == "agent-ready"'

  new_case
  respond ListQueue "$(queue_page "$(jq -n --argjson a "$(queue_node T-11 agent-ready -)" '[$a]')" true)"
  queue_page "$(jq -n --argjson a "$(queue_node T-12 agent-ready -)" '[$a]')" false |
    jq '{data: .}' > "$FAKE_LINEAR/ListQueue.after-cursor1.json"
  expect_listed lists_issues_from_every_page "T-11,T-12"
}

# Fake responses for one team and one project labelled "arjunbhargava/foundation".
respond_to_create() {
  respond ListTeams '{"teams": {"nodes": [{"id": "team-1", "key": "TEAM"}]}}'
  respond FindLabel '{"issueLabels": {"nodes": [{"id": "label-1"}]}}'
  respond FindProject '{"projects": {"nodes": [{"id": "project-1", "labels": {"nodes": [{"name": "arjunbhargava/foundation"}]}}]}}'
  respond FindParent '{"issue": {"id": "parent-1"}}'
  respond CreateIssue '{"issueCreate": {"issue": {"identifier": "TEAM-7"}}}'
}

expect_no_issue_created() {
  if jq -e -s 'any(.[]; .operationName == "CreateIssue")' "$FAKE_LINEAR/requests.log" > /dev/null 2>&1; then
    fail "$1" "the script created an issue"
  fi
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
  expect_no_issue_created reuses_the_issue_that_already_has_the_title

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  respond FindLabel '{"issueLabels": {"nodes": []}}'
  expect_run fails_without_creating_when_a_label_does_not_exist 1 "no issue label named 'typo-label'" \
    create --title "Fix it" --description-file "$work/description.md" --label typo-label
  expect_no_issue_created fails_without_creating_when_a_label_does_not_exist

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  respond FindParent '{"issue": null}'
  expect_run fails_without_creating_when_the_parent_does_not_exist 1 "Linear has no issue TEAM-404" \
    create --title "Fix it" --description-file "$work/description.md" --parent TEAM-404
  expect_no_issue_created fails_without_creating_when_the_parent_does_not_exist

  new_case
  respond_to_create
  respond FindIssue '{"issues": {"nodes": []}}'
  respond ListTeams '{"teams": {"nodes": [{"id": "team-1", "key": "ONE"}, {"id": "team-2", "key": "TWO"}]}}'
  expect_run fails_when_there_are_several_teams_and_no_team_key 1 "set LINEAR_TEAM_KEY to one of: ONE, TWO" \
    create --title "Fix it" --description-file "$work/description.md"
}

delegate_cases() {
  new_case
  respond ListApps '{"users": {"nodes": [{"id": "app-1"}]}}'
  respond DelegateIssue '{"issueUpdate": {"issue": {"identifier": "TEAM-9"}}}'
  expect_run delegates_to_the_cursor_app_user 0 "Delegated TEAM-9 to Cursor." delegate TEAM-9
  expect_json asks_for_the_app_user_named_cursor_and_delegates_to_it "$(jq -s 'map(.variables)' "$FAKE_LINEAR/requests.log")" \
    '.[0].name == "Cursor" and .[1] == {id: "TEAM-9", delegate: "app-1"}'
}

failure_cases() {
  new_case
  LINEAR_API_KEY="" expect_run names_the_missing_api_key 1 "LINEAR_API_KEY is not set" list

  new_case
  jq -n '{errors: [{message: "Entity not found: Issue"}]}' > "$FAKE_LINEAR/ListApps.json"
  expect_run reports_the_messages_of_a_graphql_error 1 "Entity not found: Issue" delegate TEAM-9

  new_case
  respond ListQueue "$(queue_page '[]' false)"
  expect_run sends_the_key_in_a_config_file_and_never_prints_it 0 "[]" list
  if grep -qF "$LINEAR_API_KEY" "$FAKE_LINEAR/curl_arguments.log" || [[ $output == *"$LINEAR_API_KEY"* ]]; then
    fail sends_the_key_in_a_config_file_and_never_prints_it "the key appeared in curl's arguments or in the output"
  fi
  grep -qF "Authorization: $LINEAR_API_KEY" "$FAKE_LINEAR/curl_config.log" ||
    fail sends_the_key_in_a_config_file_and_never_prints_it "curl's config file had no Authorization header"
}

main "$@"
