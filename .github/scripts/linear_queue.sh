#!/usr/bin/env bash
# Reads and writes the Linear queue of work for agents, so that an
# orchestrator, or any agent that finds work outside its own issue, never
# writes a GraphQL request by hand. docs/linear.md defines the queue.
#
# Usage:
#   .github/scripts/linear_queue.sh list
#   .github/scripts/linear_queue.sh create --title TITLE --description-file FILE
#       [--repo owner/name] [--label NAME]... [--parent ISSUE_ID]
#   .github/scripts/linear_queue.sh delegate ISSUE_ID
#
# list: prints a JSON array of the dispatchable issues. An issue is
#   dispatchable when it has the "agent-ready" label and not "needs-person",
#   its state is Backlog or Todo (not started), it has no delegate, and every
#   issue that blocks it is Done or Canceled. Each element has identifier,
#   title, url, and repo (the "owner/name" label from the "repo" label group,
#   on the issue or else its project; null if neither has one).
# create: prints the identifier of the issue whose title is exactly TITLE,
#   creating the issue first if none exists, so that a rerun makes no
#   duplicate. The issue is in the team's Backlog. Fails if the workspace has
#   several teams and LINEAR_TEAM_KEY is not set. --repo adds the issue label
#   and the project that carry that name. --parent makes it a sub-issue of
#   ISSUE_ID, such as ENG-12. The description is the file's contents.
# delegate: sets the issue's delegate to the Cursor app user, which starts a
#   Cursor cloud agent on the issue in the repository its repo label names,
#   and moves the issue to In Progress.
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
repo_label_group=repo
delegate_app_name=Cursor
# Linear rejects a query whose complexity exceeds 10,000; 50 issues with the
# relations below is well under that.
page_size=50

main() {
  if [[ -z ${LINEAR_API_KEY:-} ]]; then
    echo "error: LINEAR_API_KEY is not set; add it to .env, or set it as a Cursor secret" >&2
    exit 1
  fi

  local command=${1:-}
  shift || true
  case $command in
    list) list_dispatchable_issues ;;
    create) create_issue "$@" ;;
    delegate) delegate_issue "$@" ;;
    *)
      echo "error: unknown command '$command'; use list, create, or delegate (see the top of $0)" >&2
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
  local document='
    query ListQueue($after: String, $first: Int!, $readyLabel: String!) {
      issues(
        first: $first
        after: $after
        filter: {
          labels: { some: { name: { eq: $readyLabel } } }
          state: { type: { in: ["backlog", "unstarted"] } }
        }
      ) {
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
  local after=null all_issues='[]' page has_next_page

  while true; do
    page=$(graphql ListQueue "$document" \
      "$(jq -n --argjson after "$after" --argjson first "$page_size" --arg ready "$ready_label" \
        '{after: $after, first: $first, readyLabel: $ready}')")
    all_issues=$(jq -n --argjson all "$all_issues" --argjson page "$page" '$all + $page.issues.nodes')
    has_next_page=$(jq -r '.issues.pageInfo.hasNextPage' <<< "$page")
    if [[ $has_next_page != true ]]; then
      break
    fi
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

create_issue() {
  local title="" description_file="" repo="" parent="" labels=()
  while (($# > 0)); do
    case $1 in
      --title) title=${2:?--title needs a value}; shift 2 ;;
      --description-file) description_file=${2:?--description-file needs a value}; shift 2 ;;
      --repo) repo=${2:?--repo needs a value}; shift 2 ;;
      --label) labels+=("${2:?--label needs a value}"); shift 2 ;;
      --parent) parent=${2:?--parent needs a value}; shift 2 ;;
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

  local existing
  existing=$(graphql FindIssue \
    'query FindIssue($title: String!) { issues(filter: { title: { eq: $title } }) { nodes { identifier } } }' \
    "$(jq -n --arg title "$title" '{title: $title}')" | jq -r '.issues.nodes[0].identifier // empty')
  if [[ -n $existing ]]; then
    echo "$existing"
    return
  fi

  # Each lookup is a plain assignment, not inside another command's
  # arguments, so that a failed lookup stops the script before it files an
  # issue without the label or project that routes it.
  local label_ids='[]' project_id=null parent_id=null label_name label_id team_id
  if [[ -n $repo ]]; then
    labels+=("$repo")
    project_id=$(find_project_id_for_repo "$repo")
  fi
  for label_name in "${labels[@]+"${labels[@]}"}"; do
    label_id=$(find_issue_label_id "$label_name")
    label_ids=$(jq -n --argjson ids "$label_ids" --arg id "$label_id" '$ids + [$id]')
  done
  team_id=$(find_team_id)
  if [[ -n $parent ]]; then
    parent_id=$(graphql FindParent 'query FindParent($id: String!) { issue(id: $id) { id } }' \
      "$(jq -n --arg id "$parent" '{id: $id}')" | jq '.issue.id')
  fi

  local input
  input=$(jq -n --arg team "$team_id" --arg title "$title" --rawfile description "$description_file" \
    --argjson labels "$label_ids" --argjson project "$project_id" --argjson parent "$parent_id" \
    '{teamId: $team, title: $title, description: $description, labelIds: $labels}
     + (if $project == null then {} else {projectId: $project} end)
     + (if $parent == null then {} else {parentId: $parent} end)')
  graphql CreateIssue \
    'mutation CreateIssue($input: IssueCreateInput!) { issueCreate(input: $input) { issue { identifier } } }' \
    "$(jq -n --argjson input "$input" '{input: $input}')" | jq -r '.issueCreate.issue.identifier'
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
# that name; fails if there is none, because a typo would otherwise file the
# issue without the label that routes it.
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
  app_user_id=$(graphql ListApps 'query ListApps { users { nodes { id name app } } }' |
    jq -r --arg name "$delegate_app_name" '[.users.nodes[] | select(.app and .name == $name) | .id] | first // empty')
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
