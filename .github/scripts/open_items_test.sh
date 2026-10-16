#!/usr/bin/env bash
# Tests .github/scripts/open_items.sh: each case writes a page of open items,
# runs the script on it, and checks whether it passes or fails, and what it
# prints. lint:open-items runs it on the repository's own pages.
#
# Usage: mise run test:open-items-script
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/open_items.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
cases=0

link="[#7](https://github.com/octocat/project/pull/7)"
old_item="- **OI-1** Turn on Pages. **Why:** the site doesn't publish. **Action:** set the source. **Added in:** $link. **Last confirmed:** 2026-01-05."
new_item="- **OI-2** Pin the tool. **Why:** a release can break CI. **Action:** pin it. **Added in:** $link. **Last confirmed:** 2026-10-01."

main() {
  expect_check passes_on_well_formed_items passes "is well formed" \
    "$old_item" "$new_item"
  expect_check lists_only_the_items_confirmed_before_the_date passes "OI-1, last confirmed 2026-01-05" \
    --confirmed-before 2026-02-01 "$old_item" "$new_item"
  expect_check names_the_missing_field_and_its_line fails "page.md:5: the item lacks its **Why:** field" \
    "${old_item/\*\*Why:\*\* /}"
  expect_check fails_on_a_malformed_item fails "page.md:5: the line doesn't match the format" \
    "${old_item/OI-1/OI-01}"
  expect_check fails_on_a_line_that_is_not_an_item fails "page.md:5: only items go under this heading" \
    "Some notes about the items."
  expect_check fails_on_a_duplicate_id fails "page.md:6: OI-1 is the id of an earlier item too" \
    "$old_item" "${new_item/OI-2/OI-1}"
  expect_check fails_on_a_date_in_the_future fails "2999-01-01, is later than today" \
    "${old_item/2026-01-05/2999-01-01}"
  expect_check fails_on_a_date_that_is_not_a_date fails "2026-13-05, is not a date" \
    "${old_item/2026-01-05/2026-13-05}"
  expect_check fails_on_a_link_to_another_pr fails "says #7 but points at pull request 8" \
    "${old_item/pull\/7/pull/8}"
  expect_check fails_on_an_id_not_below_the_next_id fails "OI-3 is not below the next id, OI-3" \
    "${new_item/OI-2/OI-3}"

  if ((failures > 0)); then
    exit 1
  fi
  echo "open_items.sh passed or failed as expected in all $cases cases."
}

# Arguments: the case's name, whether the script "passes" or "fails", text
# its output must contain, the script's options if any, and the page's items,
# one per argument. Line 5 of the page is the first item.
expect_check() {
  local name=$1 expected_outcome=$2 expected_text=$3
  shift 3
  local options=()
  if [[ $1 == --confirmed-before ]]; then
    options=("$1" "$2")
    shift 2
  fi
  local page=$work/page.md status=0 output outcome=passes
  {
    printf '# Open items\n\n'
    printf "The next item's id is OI-3.\n"
    printf '## Needs a person\n'
    printf '%s\n' "$@"
    printf '\n## Technical debt\n'
  } > "$page"
  output=$("$script" ${options[@]+"${options[@]}"} "$page" 2>&1) || status=$?
  cases=$((cases + 1))
  if ((status != 0)); then
    outcome=fails
  fi
  if [[ $outcome != "$expected_outcome" || $output != *"$expected_text"* ]]; then
    echo "FAIL: $name: open_items.sh exited with status $status (expected: it $expected_outcome), printed:
$output
(expected it to contain: $expected_text)" >&2
    failures=$((failures + 1))
  fi
}

main "$@"
