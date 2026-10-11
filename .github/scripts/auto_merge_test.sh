#!/usr/bin/env bash
# Tests .github/scripts/auto_merge.sh without calling GitHub. Each case runs
# the script on PR 7 against a fake gh that serves a canned repository, PR, and
# Bugbot check runs, and compares the `gh pr merge` calls the script makes with
# the expected ones.
#
# Usage: mise run test:auto-merge-script
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/auto_merge.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

agent_pr='{
  "number": 7, "state": "open", "draft": false, "user": {"login": "arjunbhargava"},
  "head": {"sha": "new", "repo": {"full_name": "o/r"}}, "base": {"ref": "main"},
  "labels": [{"name": "agent"}], "auto_merge": null
}'
reviewed='{"id": 2, "status": "completed", "conclusion": "neutral",
  "output": {"summary": "**Final Result:** Bugbot completed review and found 1 potential issue."}}'
cancelled='{"id": 2, "status": "completed", "conclusion": "neutral",
  "output": {"summary": "**Result:** Bugbot run cancelled because the review request was cancelled"}}'
in_progress='{"id": 3, "status": "in_progress", "conclusion": null,
  "output": {"summary": "Bugbot Analysis Progress (1m 2s elapsed)"}}'
turn_on='gh pr merge 7 --repo o/r --auto --merge --match-head-commit new'
turn_off='gh pr merge 7 --repo o/r --disable-auto'

main() {
  make_fake_gh
  expect_merge_calls turns_auto_merge_on_once_bugbot_has_reviewed_the_head_commit \
    . "[$reviewed]" true "$turn_on"
  expect_merge_calls waits_while_bugbot_is_reviewing_the_head_commit \
    . "[$reviewed, $in_progress]" true ""
  expect_merge_calls waits_when_bugbot_run_on_the_head_commit_was_cancelled \
    . "[$cancelled]" true ""
  expect_merge_calls turns_auto_merge_off_after_a_push_bugbot_has_not_reviewed \
    '.auto_merge = {"merge_method": "merge"}' "[]" true "$turn_off"
  expect_merge_calls leaves_auto_merge_on_once_bugbot_has_reviewed_the_head_commit \
    '.auto_merge = {"merge_method": "merge"}' "[$reviewed]" true ""
  expect_merge_calls waits_while_the_pr_is_a_draft \
    '.draft = true' "[$reviewed]" true ""
  expect_merge_calls does_nothing_when_allow_auto_merge_is_off \
    . "[$reviewed]" false ""
  expect_merge_calls still_turns_auto_merge_off_after_a_push_when_allow_auto_merge_is_off \
    '.auto_merge = {"merge_method": "merge"}' "[]" false "$turn_off"
  expect_merge_calls leaves_closed_prs_alone \
    '.state = "closed"' "[$reviewed]" true ""
  expect_merge_calls leaves_prs_without_the_agent_label_alone \
    '.labels = [{"name": "dependencies"}]' "[$reviewed]" true ""
  expect_merge_calls leaves_dependabot_prs_alone \
    '.user.login = "dependabot[bot]"' "[$reviewed]" true ""
  expect_merge_calls leaves_prs_from_forks_alone \
    '.head.repo.full_name = "fork/r"' "[$reviewed]" true ""
  expect_merge_calls leaves_prs_into_other_branches_alone \
    '.base.ref = "stacked-base"' "[$reviewed]" true ""

  if ((failures > 0)); then
    exit 1
  fi
  echo "auto_merge.sh made the expected gh pr merge calls in all 13 cases."
}

# Puts first on PATH a gh that answers auto_merge.sh's requests from the files
# in $FAKE_GH_CASE, and appends each `gh pr merge` call to its merge-calls
# file. Only the head commit, "new", has Bugbot check runs.
make_fake_gh() {
  mkdir "$work/bin"
  cat > "$work/bin/gh" << 'EOF'
#!/bin/sh
case "$*" in
  "api repos/o/r") cat "$FAKE_GH_CASE/repository.json" ;;
  "api repos/o/r/pulls/7") cat "$FAKE_GH_CASE/pr.json" ;;
  "api --method GET repos/o/r/commits/new/check-runs -f app_id=1210556 -f check_name=Cursor Bugbot")
    cat "$FAKE_GH_CASE/check-runs.json" ;;
  "pr merge "*) echo "gh $*" >> "$FAKE_GH_CASE/merge-calls" ;;
  *) echo "fake gh: unexpected call: gh $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$work/bin/gh"
  PATH=$work/bin:$PATH
}

# Arguments: the case's name; a jq filter that turns the agent PR into the
# case's PR; Bugbot's check runs on the head commit, as a JSON array; the
# repository's allow_auto_merge setting; and the `gh pr merge` calls expected,
# one per line.
expect_merge_calls() {
  local name=$1 pr_filter=$2 check_runs=$3 allow_auto_merge=$4 expected=$5
  local case_dir=$work/$name
  mkdir "$case_dir"
  echo "{\"default_branch\": \"main\", \"allow_auto_merge\": $allow_auto_merge}" > "$case_dir/repository.json"
  jq "$pr_filter" <<< "$agent_pr" > "$case_dir/pr.json"
  echo "{\"check_runs\": $check_runs}" > "$case_dir/check-runs.json"
  touch "$case_dir/merge-calls"

  local status=0 output calls
  output=$(FAKE_GH_CASE=$case_dir GITHUB_REPOSITORY=o/r "$script" 7 2>&1) || status=$?
  calls=$(cat "$case_dir/merge-calls")
  if ((status != 0)) || [[ $calls != "$expected" ]]; then
    fail "$name: auto_merge.sh exited with status $status, printed:
$output
and made these gh pr merge calls:
${calls:-(none)}
Expected these calls:
${expected:-(none)}"
  fi
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

main "$@"
