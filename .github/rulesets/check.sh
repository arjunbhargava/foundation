#!/usr/bin/env bash
# Checks the ruleset files in this directory: each is valid JSON, and the
# auto-mode review ruleset (docs/auto-mode.md) differs from main-review.json
# only in its name, its required approval count, and whether review threads
# must be resolved, so an edit to one review ruleset is made to both. It also
# checks those values against docs/auto-mode.md: auto mode needs 0 approvals,
# review mode at least 1, and only auto mode needs resolved threads. Auto mode
# must keep code-owner review and thread resolution on, because without
# either, a PR could merge with no person or Bugbot gate.
#
# Usage: mise run lint:rulesets
set -euo pipefail
cd "$(dirname "$0")"

for file in *.json; do
  if ! jq empty "$file"; then
    echo "error: .github/rulesets/$file is not valid JSON; fix the parse error above." >&2
    exit 1
  fi
done

without_auto_mode_fields='del(.name, (.rules[] | select(.type == "pull_request") | .parameters | .required_approving_review_count, .required_review_thread_resolution))'
if ! diff -u <(jq -S "$without_auto_mode_fields" main-review.json) <(jq -S "$without_auto_mode_fields" main-review-auto.json) >&2; then
  echo "error: main-review.json and main-review-auto.json differ in the lines above, which auto mode doesn't change. Make the same edit to both files." >&2
  exit 1
fi

# Arguments: a review ruleset file, a jq condition on its pull_request rule's
# parameters, and the error to print, after the file name, if it is false.
require_review_setting() {
  if ! jq -e ".rules[] | select(.type == \"pull_request\") | .parameters | $2" "$1" > /dev/null; then
    echo "error: $1 $3" >&2
    exit 1
  fi
}
require_review_setting main-review-auto.json '.require_code_owner_review and .required_review_thread_resolution' \
  "must set require_code_owner_review and required_review_thread_resolution to true."
require_review_setting main-review-auto.json '.required_approving_review_count == 0' \
  "must set required_approving_review_count to 0, so auto mode needs no approval."
require_review_setting main-review.json '.required_approving_review_count >= 1' \
  "must set required_approving_review_count to at least 1, so review mode needs an approval."
require_review_setting main-review.json '.required_review_thread_resolution == false' \
  "must set required_review_thread_resolution to false, as the table in docs/auto-mode.md says."

echo "The ruleset files are valid JSON, and the review rulesets differ only in name, approval count, and thread resolution, with the values docs/auto-mode.md gives."
