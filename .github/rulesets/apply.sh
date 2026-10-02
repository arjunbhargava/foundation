#!/usr/bin/env bash
# Applies the repository settings that GitHub doesn't copy from a template
# (T4 in docs/template-plan.md). Safe to rerun.
#
#   1. Merge commits become the only merge method (D6). main-review.json
#      allows only merge commits too, but admins can bypass that ruleset.
#   2. Each ruleset in this directory is created, or updated if a ruleset
#      with the same name exists. In the JSON, integration_id 15368 is the
#      GitHub Actions app, so only Actions can report the required checks,
#      and actor_id 5 with actor_type RepositoryRole is the admin role.
#   3. Secret scanning and push protection are turned on. This step is last
#      because it fails on a private repository without GitHub Secret
#      Protection, and the steps before it still apply.
#
# Usage: mise exec -- .github/rulesets/apply.sh [--dry-run] [owner/repo]
#
# Needs gh logged in as a repository admin. The repository defaults to the
# one for the current directory. --dry-run prints each change instead of
# making it; it still reads the existing rulesets to decide between create
# and update.
#
# Switching to a merge queue, which GitHub offers only to repositories owned
# by an organization:
#   1. In main-checks.json, set strict_required_status_checks_policy to false
#      and add this rule. Apart from merge_method, the values are GitHub's
#      defaults.
#        { "type": "merge_queue", "parameters": {
#            "merge_method": "MERGE", "grouping_strategy": "ALLGREEN",
#            "check_response_timeout_minutes": 60, "max_entries_to_build": 5,
#            "max_entries_to_merge": 5, "min_entries_to_merge": 1,
#            "min_entries_to_merge_wait_minutes": 5 } }
#   2. Rerun this script. CI already runs on merge_group.
set -euo pipefail
cd "$(dirname "$0")"

dry_run=false
if [[ ${1:-} == --dry-run ]]; then
  dry_run=true
  shift
fi
repo=${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

# Makes one change, or prints it under --dry-run. Arguments: a description,
# the HTTP method, and the API path. The JSON body is read from stdin.
apply() {
  local description=$1 method=$2 path=$3
  if $dry_run; then
    echo "Would $description: $method $path"
    jq .
  else
    gh api --method "$method" "$path" --input - --silent
    echo "Done: $description"
  fi
}

apply "allow only merge commits" PATCH "repos/$repo" << 'EOF'
{ "allow_merge_commit": true, "allow_squash_merge": false, "allow_rebase_merge": false }
EOF

existing_rulesets=$(gh api --paginate "repos/$repo/rulesets?includes_parents=false")
for file in *.json; do
  name=$(jq -r .name "$file")
  id=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<< "$existing_rulesets")
  if [[ -n $id ]]; then
    apply "update ruleset \"$name\" (id $id)" PUT "repos/$repo/rulesets/$id" < "$file"
  else
    apply "create ruleset \"$name\"" POST "repos/$repo/rulesets" < "$file"
  fi
done

apply "turn on secret scanning with push protection" PATCH "repos/$repo" << 'EOF'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF
