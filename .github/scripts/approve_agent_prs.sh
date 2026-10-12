#!/usr/bin/env bash
# Approves each agent PR given, as github-actions[bot], while auto mode is on,
# so that it has the one approval the auto-mode ruleset requires
# (docs/auto-mode.md). github-actions[bot] isn't a code owner, so a PR that
# changes a path in .github/CODEOWNERS still needs a code owner's approval.
# .github/workflows/approve-agent-prs.yml runs it.
#
# Auto mode is on when the ruleset in main-review-auto.json is active and the
# one in main-review.json isn't. Otherwise nothing is approved, because
# main: review would count the bot's approval as the person's it requires.
#
# A PR is left alone if it isn't open, comes from a fork, has no agent label,
# or github-actions[bot] has reviewed it before. The bot approves a PR at most
# once, so an approval that a person, or apply.sh, dismissed stays dismissed.
#
# Usage: .github/scripts/approve_agent_prs.sh <PR number>...
#
# Needs GITHUB_REPOSITORY, which GitHub Actions sets, and gh authenticated
# with a token that can approve PRs: in Actions, GH_TOKEN with
# pull-requests: write, with "Allow GitHub Actions to create and approve pull
# requests" on in Settings > Actions > General. It fails if a request fails.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set; set it to the repository as owner/name}"

# The account GITHUB_TOKEN acts as.
approver='github-actions[bot]'
rulesets_dir=$(cd "$(dirname "$0")/../rulesets" && pwd)

main() {
  local rulesets
  rulesets=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/rulesets?includes_parents=false")
  if ! auto_mode_on "$rulesets"; then
    echo "Auto mode is off, so no PR is approved."
    return
  fi
  local number
  for number in "$@"; do
    approve_agent_pr "$number"
  done
}

# Succeeds if the auto-mode review ruleset is active and the review-mode one
# isn't. Argument: the repository's rulesets, as pages of JSON arrays from the
# REST API.
auto_mode_on() {
  jq -e --arg auto "$(jq -r .name "$rulesets_dir/main-review-auto.json")" \
    --arg review "$(jq -r .name "$rulesets_dir/main-review.json")" '
    flatten |
      any(.name == $auto and .enforcement == "active") and
      (any(.name == $review and .enforcement == "active") | not)' <<< "$1" > /dev/null
}

# Approves one PR, or leaves it alone, and prints what it did and why.
# Argument: the PR's number.
approve_agent_pr() {
  local number=$1
  local pr reason
  pr=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$number")
  reason=$(reason_to_leave_alone "$pr")
  if [[ -n $reason ]]; then
    echo "PR #$number: left alone, because $reason."
    return
  fi

  local reviews earlier_review_states
  reviews=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/pulls/$number/reviews")
  earlier_review_states=$(jq -r --arg approver "$approver" \
    '[flatten[] | select(.user.login == $approver) | .state] | join(", ")' <<< "$reviews")
  if [[ -n $earlier_review_states ]]; then
    echo "PR #$number: left alone, because $approver has reviewed it before ($earlier_review_states), and approves a PR at most once."
    return
  fi

  if ! gh api --method POST "repos/$GITHUB_REPOSITORY/pulls/$number/reviews" --silent -f event=APPROVE \
    -f body="Auto mode is on and this is an agent PR, so $approver gives the approval the auto-mode ruleset requires (docs/auto-mode.md). It isn't a code owner: a change to a path in .github/CODEOWNERS still needs the code owner's approval."; then
    echo "error: GitHub refused $approver's approval of PR #$number. If the error above says GitHub Actions is not permitted to approve pull requests, turn on \"Allow GitHub Actions to create and approve pull requests\" in Settings > Actions > General." >&2
    return 1
  fi
  echo "PR #$number: approved, because auto mode is on and it is an agent PR."
}

# Prints why this script doesn't approve the PR, or nothing if it may.
# Argument: the PR as JSON from the REST API.
reason_to_leave_alone() {
  jq -r --arg repository "$GITHUB_REPOSITORY" '
    if .state != "open" then "it is \(.state)"
    elif .head.repo.full_name != $repository then "it comes from a fork"
    elif (any(.labels[]; .name == "agent") | not) then "it has no agent label"
    else empty
    end' <<< "$1"
}

main "$@"
