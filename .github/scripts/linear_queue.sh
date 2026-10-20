#!/usr/bin/env bash
# Reads and writes the Linear queue of work for agents, so that an
# orchestrator, or any agent that finds work outside its own issue, never
# writes a GraphQL request by hand. docs/linear-delegation.md defines the queue.
#
# Usage:
#   .github/scripts/linear_queue.sh list [--parent ISSUE_ID]
#   .github/scripts/linear_queue.sh children ISSUE_ID
#   .github/scripts/linear_queue.sh create --title TITLE --description-file FILE
#       [--repo owner/name] [--label NAME]... [--parent ISSUE_ID]
#       [--blocked-by ISSUE_ID]...
#   .github/scripts/linear_queue.sh delegate ISSUE_ID
#
# list: prints a JSON array of the dispatchable issues, each with identifier,
#   title, url, and repo (the "owner/name" label from the "repo" label group,
#   on the issue or else its project, or null). An issue is dispatchable when
#   it has "agent-ready" and not "needs-person", is not started, has no
#   delegate, and every issue that blocks it is Done or Canceled. --parent
#   lists only the sub-issues of ISSUE_ID, such as ENG-12, and fails, naming
#   it, if Linear has no such issue.
# children: prints a JSON array of every sub-issue of ISSUE_ID, such as
#   ENG-12, in any state, each with identifier, title, url, state (its name and
#   type), delegate (its name, or null), and labels (their names). Prints []
#   when there are none, and fails, naming ISSUE_ID, if Linear has no such
#   issue. Unlike list, it applies no dispatch rule.
# create: prints the identifier of the issue titled exactly TITLE, creating it
#   in the team's Backlog only if none exists, so a rerun makes no duplicate.
#   Fails if there are several teams and LINEAR_TEAM_KEY is not set. --repo
#   adds the issue label and project of that name; --parent makes it a
#   sub-issue of ISSUE_ID, such as ENG-12. It always adds the "agent-filed"
#   label, because Linear shows the owner's personal API key as the creator of
#   every issue an agent files, so the label is the only record that an agent
#   filed it; it fails before creating anything if that label does not exist.
#   --blocked-by makes ISSUE_ID block the issue, so that list skips the issue
#   until ISSUE_ID is Done or Canceled. A rerun adds the blocked-by relations
#   the issue lacks, also when the issue already existed.
# delegate: sets the issue's delegate to the Cursor app user, which starts a
#   Cursor cloud agent in the repository its repo label names and moves the
#   issue to In Progress.
#
# Reads LINEAR_API_KEY (a Linear personal API key) and, optionally,
# LINEAR_TEAM_KEY. The key goes to curl through a config file on a pipe, so it
# is never in a command line or in output.
# GraphQL variables, such as $title, are written in single quotes on purpose.
# shellcheck disable=SC2016
set -euo pipefail

linear_endpoint=https://api.linear.app/graphql
ready_label=agent-ready
person_label=needs-person
agent_filed_label=agent-filed
repo_label_group=repo
delegate_app_name=Cursor
# Linear rejects a query above complexity 10,000; 50 issues here is well under.
page_size=50

main() {
  if [[ -z ${LINEAR_API_KEY:-} ]]; then
    echo "error: LINEAR_API_KEY is not set; add it to .env, or set it as a Cursor secret" >&2
    exit 1
  fi

  local command=${1:-}
  shift || true
  case $command in
    list) list_dispatchable_issues "$@" ;;
    children) list_children "$@" ;;
    create) create_issue "$@" ;;
    delegate) delegate_issue "$@" ;;
    *)
      echo "error: unknown command '$command'; use list, children, create, or delegate (see the top of $0)" >&2
      exit 1
      ;;
  esac
}

# Arguments: a name for the request, the GraphQL document, and its variables
# as a JSON object. Prints the response's "data" object. Fails, printing
# Linear's messages, on an HTTP error or a GraphQL error.
graphql() {
  local operation=$1 document=$2 variables=${3:-\{\}}
  local response
  response=$(jq -n --arg operation "$operation" --arg document "$document" --argjson variables "$variables" \
    '{operationName: $operation, query: $document, variables: $variables}' |
    curl --silent --show-error --fail-with-body "$linear_endpoint" \
      --config <(printf 'header = "Authorization: %s"\n' "$LINEAR_API_KEY") \
      --header 'Content-Type: application/json' --data @-) || {
    echo "error: the Linear request '$operation' failed: ${response:-no response}" >&2
    exit 1
  }
  if jq -e '.errors' <<< "$response" > /dev/null; then
    echo "error: Linear rejected the request '$operation': $(jq -c '[.errors[].message]' <<< "$response")" >&2
    exit 1
  fi
  jq '.data' <<< "$response"
}

list_dispatchable_issues() {
  local parent=""
  while (($# > 0)); do
    case $1 in
      --parent) parent=${2:?--parent needs a value}; shift 2 ;;
      *) echo "error: unknown option '$1' for list (see the top of $0)" >&2; exit 1 ;;
    esac
  done

  # Linear's own filter does the label, state, and parent selection; the jq
  # filter below applies the rules Linear's filter can't express.
  local parent_id=null
  if [[ -n $parent ]]; then
    parent_id=$(find_issue_id "$parent") ||
      { echo "error: cannot list the sub-issues of '$parent' (see above)" >&2; exit 1; }
  fi
  local issue_filter
  issue_filter=$(jq -n --arg ready "$ready_label" --argjson parent "$parent_id" '
    { labels: {some: {name: {eq: $ready}}}, state: {type: {in: ["backlog", "unstarted"]}} }
    + (if $parent == null then {} else {parent: {id: {eq: $parent}}} end)')

  local document='
    query ListQueue($after: String, $first: Int!, $filter: IssueFilter!) {
      issues(first: $first, after: $after, filter: $filter) {
        pageInfo { hasNextPage endCursor }
        nodes {
          identifier
          title
          url
          delegate { id }
          labels { nodes { name parent { name } } }
          project { labels { nodes { name parent { name } } } }
          inverseRelations { nodes { type issue { state { type } } } }
        }
      }
    }'
  local after=null all_issues='[]' page

  while true; do
    page=$(graphql ListQueue "$document" \
      "$(jq -n --argjson after "$after" --argjson first "$page_size" --argjson filter "$issue_filter" \
        '{after: $after, first: $first, filter: $filter}')")
    all_issues=$(jq -n --argjson all "$all_issues" --argjson page "$page" '$all + $page.issues.nodes')
    jq -e '.issues.pageInfo.hasNextPage' <<< "$page" > /dev/null || break
    after=$(jq '.issues.pageInfo.endCursor' <<< "$page")
  done

  jq --arg person "$person_label" --arg group "$repo_label_group" '
    def repo_of(labels): [labels[] | select(.parent.name == $group) | .name] | first;
    def is_resolved: .issue.state.type == "completed" or .issue.state.type == "canceled";
    [ .[]
      | select(.delegate == null)
      | select(all(.labels.nodes[]; .name != $person))
      | select(all(.inverseRelations.nodes[] | select(.type == "blocks"); is_resolved))
      | { identifier, title, url,
          repo: (repo_of(.labels.nodes) // repo_of(.project.labels.nodes // [])) } ]' <<< "$all_issues"
}

list_children() {
  local issue_id=${1:?children needs an issue id, such as ENG-12}

  local document='
    query ListChildren($id: String!, $after: String, $first: Int!) {
      issue(id: $id) {
        children(first: $first, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes {
            identifier
            title
            url
            state { name type }
            delegate { name }
            labels { nodes { name } }
          }
        }
      }
    }'
  local after=null all_children='[]' page

  while true; do
    page=$(graphql ListChildren "$document" \
      "$(jq -n --arg id "$issue_id" --argjson after "$after" --argjson first "$page_size" \
        '{id: $id, after: $after, first: $first}')" |
      jq --arg id "$issue_id" '.issue // error("Linear has no issue \($id)")') ||
      { echo "error: cannot read the sub-issues of '$issue_id' (see above)" >&2; exit 1; }
    all_children=$(jq -n --argjson all "$all_children" --argjson page "$page" '$all + $page.children.nodes')
    jq -e '.children.pageInfo.hasNextPage' <<< "$page" > /dev/null || break
    after=$(jq '.children.pageInfo.endCursor' <<< "$page")
  done

  jq '[ .[] | { identifier, title, url, state,
                delegate: (.delegate.name // null),
                labels: [.labels.nodes[].name] } ]' <<< "$all_children"
}

create_issue() {
  local title="" description_file="" repo="" parent="" labels=() blockers=()
  while (($# > 0)); do
    case $1 in
      --title) title=${2:?--title needs a value}; shift 2 ;;
      --description-file) description_file=${2:?--description-file needs a value}; shift 2 ;;
      --repo) repo=${2:?--repo needs a value}; shift 2 ;;
      --label) labels+=("${2:?--label needs a value}"); shift 2 ;;
      --parent) parent=${2:?--parent needs a value}; shift 2 ;;
      --blocked-by) blockers+=("${2:?--blocked-by needs a value}"); shift 2 ;;
      *) echo "error: unknown option '$1' for create (see the top of $0)" >&2; exit 1 ;;
    esac
  done
  if [[ -z $title || -z $description_file ]]; then
    echo "error: create needs --title and --description-file (see the top of $0)" >&2
    exit 1
  fi
  if [[ ! -r $description_file ]]; then
    echo "error: the description file '$description_file' is not readable" >&2
    exit 1
  fi

  # Resolved before anything is created, so that a mistyped blocker leaves no
  # issue behind without its relation.
  local blocker_ids='[]' blocker blocker_id
  for blocker in ${blockers[@]+"${blockers[@]}"}; do
    blocker_id=$(find_issue_id "$blocker") ||
      { echo "error: cannot use '$blocker' as a blocking issue (see above)" >&2; exit 1; }
    blocker_ids=$(jq -nc --argjson ids "$blocker_ids" --argjson id "$blocker_id" '$ids + [$id]')
  done

  local existing identifier
  existing=$(graphql FindIssue \
    'query FindIssue($title: String!) { issues(filter: { title: { eq: $title } }) { nodes { identifier } } }' \
    "$(jq -n --arg title "$title" '{title: $title}')" | jq -r '.issues.nodes[0].identifier // empty')
  if [[ -n $existing ]]; then
    add_blocked_by_relations "$existing" "$blocker_ids"
    echo "$existing"
    return
  fi

  # Each lookup is a plain assignment, so a failure stops the script before it
  # files an issue without the label or project that routes it.
  local label_ids='[]' project_id=null parent_id=null label_name label_id team_id
  if [[ -n $repo ]]; then
    labels+=("$repo")
    project_id=$(find_project_id_for_repo "$repo")
  fi
  labels+=("$agent_filed_label")
  for label_name in "${labels[@]}"; do
    label_id=$(find_issue_label_id "$label_name")
    label_ids=$(jq -n --argjson ids "$label_ids" --arg id "$label_id" '$ids + [$id] | unique')
  done
  team_id=$(find_team_id)
  if [[ -n $parent ]]; then
    parent_id=$(find_issue_id "$parent") ||
      { echo "error: cannot use '$parent' as the parent issue (see above)" >&2; exit 1; }
  fi

  local input
  input=$(jq -n --arg team "$team_id" --arg title "$title" --rawfile description "$description_file" \
    --argjson labels "$label_ids" --argjson project "$project_id" --argjson parent "$parent_id" \
    '{teamId: $team, title: $title, description: $description, labelIds: $labels}
     + (if $project == null then {} else {projectId: $project} end)
     + (if $parent == null then {} else {parentId: $parent} end)')
  identifier=$(graphql CreateIssue \
    'mutation CreateIssue($input: IssueCreateInput!) { issueCreate(input: $input) { issue { identifier } } }' \
    "$(jq -n --argjson input "$input" '{input: $input}')" | jq -r '.issueCreate.issue.identifier')
  add_blocked_by_relations "$identifier" "$blocker_ids"
  echo "$identifier"
}

# Arguments: an issue identifier, and a JSON array of the ids of the issues
# that must block it. Adds each "blocks" relation the issue lacks.
add_blocked_by_relations() {
  local identifier=$1 blocker_ids=$2
  if jq -e 'length == 0' <<< "$blocker_ids" > /dev/null; then
    return
  fi

  local issue_state
  issue_state=$(graphql FindBlockers \
    'query FindBlockers($id: String!) { issue(id: $id) { id inverseRelations { nodes { type issue { id } } } } }' \
    "$(jq -n --arg id "$identifier" '{id: $id}')")
  local blocked_id missing_blocker_ids blocker_id
  blocked_id=$(jq -r .issue.id <<< "$issue_state")
  missing_blocker_ids=$(jq -r --argjson wanted "$blocker_ids" \
    '[.issue.inverseRelations.nodes[] | select(.type == "blocks") | .issue.id] as $existing
     | $wanted - $existing | .[]' <<< "$issue_state")
  for blocker_id in $missing_blocker_ids; do
    graphql BlockIssue \
      'mutation BlockIssue($input: IssueRelationCreateInput!) { issueRelationCreate(input: $input) { success } }' \
      "$(jq -n --arg blocker "$blocker_id" --arg blocked "$blocked_id" \
        '{input: {issueId: $blocker, relatedIssueId: $blocked, type: "blocks"}}')" > /dev/null
  done
}

# Argument: an issue identifier, such as ENG-12. Prints the issue's id as a
# JSON string; fails, naming the identifier, if Linear has no such issue.
find_issue_id() {
  graphql FindIssueId 'query FindIssueId($id: String!) { issue(id: $id) { id } }' \
    "$(jq -n --arg id "$1" '{id: $id}')" |
    jq --arg id "$1" '.issue.id // error("Linear has no issue \($id)")'
}

# Prints the id of the only team, or of the team named by LINEAR_TEAM_KEY.
find_team_id() {
  graphql ListTeams 'query ListTeams { teams { nodes { id key } } }' |
    jq -r --arg key "${LINEAR_TEAM_KEY:-}" '
      .teams.nodes as $teams
      | if $key != "" then ($teams | map(select(.key == $key)) | .[0].id // error("no team has the key \($key)"))
        elif ($teams | length) == 1 then $teams[0].id
        else error("the workspace has \($teams | length) teams; set LINEAR_TEAM_KEY to one of: \($teams | map(.key) | join(", "))")
        end' ||
    { echo "error: cannot choose a team (see above)" >&2; exit 1; }
}

# Argument: a label's name. Prints the id of the workspace issue label with
# that name; fails if there is none, since a typo would drop the routing label.
find_issue_label_id() {
  local label_id
  label_id=$(graphql FindLabel \
    'query FindLabel($name: String!) { issueLabels(filter: { name: { eq: $name } }) { nodes { id } } }' \
    "$(jq -n --arg name "$1" '{name: $name}')" | jq -r '.issueLabels.nodes[0].id // empty')
  if [[ -z $label_id ]]; then
    echo "error: Linear has no issue label named '$1'; create it in Settings > Issues > Labels" >&2
    exit 1
  fi
  echo "$label_id"
}

# Argument: "owner/name". Prints the project id as a JSON string, or null if
# no project carries the project label of that name.
find_project_id_for_repo() {
  graphql FindProject \
    'query FindProject { projects(first: 100) { nodes { id labels { nodes { name } } } } }' |
    jq --arg repo "$1" '[.projects.nodes[] | select(any(.labels.nodes[]; .name == $repo)) | .id] | first // null'
}

delegate_issue() {
  local issue_id=${1:?delegate needs an issue id, such as ENG-12}
  local app_user_id
  app_user_id=$(graphql ListApps \
    'query ListApps($name: String!) { users(filter: { app: { eq: true }, name: { eq: $name } }) { nodes { id } } }' \
    "$(jq -n --arg name "$delegate_app_name" '{name: $name}')" | jq -r '.users.nodes[0].id // empty')
  if [[ -z $app_user_id ]]; then
    echo "error: Linear has no app user named '$delegate_app_name'; connect Cursor in Settings > Integrations" >&2
    exit 1
  fi
  graphql DelegateIssue \
    'mutation DelegateIssue($id: String!, $delegate: String!) { issueUpdate(id: $id, input: { delegateId: $delegate }) { issue { identifier } } }' \
    "$(jq -n --arg id "$issue_id" --arg delegate "$app_user_id" '{id: $id, delegate: $delegate}')" |
    jq -r '"Delegated \(.issueUpdate.issue.identifier) to '"$delegate_app_name"'."'
}

main "$@"
