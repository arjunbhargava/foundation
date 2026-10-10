#!/usr/bin/env bash
# Tests the scripts in .github/rulesets/ without calling GitHub. apply.sh runs
# with --dry-run against a fake gh that lists canned existing rulesets, and
# each case compares the changes apply.sh would make with the expected ones.
# check.sh runs on copies of the ruleset files, each broken in one way.
#
# Usage: mise run test:rulesets
set -euo pipefail

rulesets_dir=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

main() {
  make_fake_gh
  local checks='{"id": 1, "name": "main: checks"}'
  local review='{"id": 2, "name": "main: review"}'
  local auto='{"id": 3, "name": "main: review (auto mode)"}'

  expect_changes default_mode_makes_the_same_changes_as_before_auto_mode "[$checks, $review]" '
Would allow only merge commits: PATCH repos/o/r
Would update ruleset "main: checks" (id 1): PUT repos/o/r/rulesets/1
Would update ruleset "main: review" (id 2): PUT repos/o/r/rulesets/2
Would turn on secret scanning with push protection: PATCH repos/o/r'

  expect_changes auto_mode_creates_its_ruleset_then_disables_main_review "[$checks, $review]" '
Would allow only merge commits: PATCH repos/o/r
Would update ruleset "main: checks" (id 1): PUT repos/o/r/rulesets/1
Would create ruleset "main: review (auto mode)": POST repos/o/r/rulesets
Would disable ruleset "main: review" (id 2): PUT repos/o/r/rulesets/2
Would turn on secret scanning with push protection: PATCH repos/o/r' --auto

  expect_changes default_mode_switches_back_from_auto_mode "[$checks, $review, $auto]" '
Would allow only merge commits: PATCH repos/o/r
Would update ruleset "main: checks" (id 1): PUT repos/o/r/rulesets/1
Would update ruleset "main: review" (id 2): PUT repos/o/r/rulesets/2
Would disable ruleset "main: review (auto mode)" (id 3): PUT repos/o/r/rulesets/3
Would turn on secret scanning with push protection: PATCH repos/o/r'

  if ! "$rulesets_dir/check.sh" > /dev/null; then
    fail "check_passes_on_the_committed_rulesets: check.sh failed on the files in .github/rulesets/."
  fi
  expect_check_error check_fails_on_invalid_json main-checks.json '{' \
    "main-checks.json is not valid JSON"
  expect_check_error check_fails_when_the_review_rulesets_differ_elsewhere main-review-auto.json \
    "$(jq '.bypass_actors = []' "$rulesets_dir/main-review-auto.json")" \
    "differ in the lines above"
  expect_check_error check_fails_when_auto_mode_drops_thread_resolution main-review-auto.json \
    "$(jq '(.rules[] | select(.type == "pull_request") | .parameters.required_review_thread_resolution) = false' "$rulesets_dir/main-review-auto.json")" \
    "must set require_code_owner_review and required_review_thread_resolution to true"

  if ((failures > 0)); then
    exit 1
  fi
  echo "apply.sh made the expected changes in all 3 cases, and check.sh passed the committed rulesets and failed all 3 broken ones."
}

# Puts first on PATH a gh that answers only apply.sh's request for the existing
# rulesets, with the JSON array in FAKE_EXISTING_RULESETS.
make_fake_gh() {
  mkdir "$work/bin"
  cat > "$work/bin/gh" << 'EOF'
#!/bin/sh
case "$*" in
  *"/rulesets?includes_parents=false"*) printf '%s\n' "$FAKE_EXISTING_RULESETS" ;;
  *) echo "fake gh: unexpected call: gh $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$work/bin/gh"
  PATH=$work/bin:$PATH
}

# Arguments: the case's name, the existing rulesets as a JSON array, the
# "Would ..." lines apply.sh --dry-run must print, after a leading newline,
# and apply.sh's other options.
expect_changes() {
  local name=$1 existing=$2 expected=${3#$'\n'}
  shift 3
  local status=0 output changes
  output=$(FAKE_EXISTING_RULESETS=$existing "$rulesets_dir/apply.sh" --dry-run "$@" o/r 2>&1) || status=$?
  changes=$(grep '^Would' <<< "$output" || true)
  if ((status != 0)) || [[ $changes != "$expected" ]]; then
    fail "$name: apply.sh exited with status $status and printed:
$output
Expected these changes:
$expected"
  fi
}

# Arguments: the case's name, a ruleset file, the content that replaces it in a
# copy of this directory, and text that check.sh's error must contain.
expect_check_error() {
  local name=$1 file=$2 content=$3 expected_error=$4
  local copy=$work/$name
  mkdir "$copy"
  cp "$rulesets_dir/check.sh" "$rulesets_dir"/*.json "$copy/"
  printf '%s\n' "$content" > "$copy/$file"
  local status=0 output
  output=$("$copy/check.sh" 2>&1) || status=$?
  if ((status == 0)) || [[ $output != *"$expected_error"* ]]; then
    fail "$name: check.sh exited with status $status and printed '$output'; expected a non-zero status and an error containing '$expected_error'."
  fi
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

main "$@"
