#!/usr/bin/env bash
# Checks the ruleset files in this directory: each is valid JSON, and the
# auto-mode review ruleset (docs/auto-mode.md) differs from main-review.json
# only in its name, its required approval count, and whether review threads
# must be resolved, so an edit to one review ruleset is made to both. It also
# checks that auto mode keeps code-owner review and thread resolution on,
# because without either, a PR could merge with no person or Bugbot gate.
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

if ! jq -e '.rules[] | select(.type == "pull_request") | .parameters | .require_code_owner_review and .required_review_thread_resolution' main-review-auto.json > /dev/null; then
  echo "error: main-review-auto.json must set require_code_owner_review and required_review_thread_resolution to true." >&2
  exit 1
fi

echo "The ruleset files are valid JSON, and the review rulesets differ only in name, approval count, and thread resolution."
