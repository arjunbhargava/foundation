#!/usr/bin/env bash
# Checks the open items on docs/open-items.md and, in the template
# repository, docs/template-open-items.md. Every non-blank line under a
# "## Needs a person" or "## Technical debt" heading must be one item in the
# page's format, ids must be unique and below the page's next id, and no
# "last confirmed" date may be later than today in UTC+14, the earliest time
# zone, so that a person anywhere can write their own date. Prints an error
# naming the file and line of each problem, and exits 1 if there was one.
# With --confirmed-before YYYY-MM-DD, also prints each item last confirmed
# before that date, for .github/workflows/open-items.yml. Keep it working
# under bash 3.2, the version macOS ships.
#
# Usage: .github/scripts/open_items.sh [--confirmed-before YYYY-MM-DD] [file...]
# Without files, it reads the pages named above.
set -euo pipefail

item_pattern='^- \*\*OI-([1-9][0-9]*)\*\* ([^ ].*) \*\*Why:\*\* ([^ ].*) \*\*Action:\*\* ([^ ].*) \*\*Added in:\*\* \[#([0-9]+)\]\(https://github\.com/[^/ ]+/[^/ ]+/pull/([0-9]+)\)\. \*\*Last confirmed:\*\* ([0-9]{4}-[0-9]{2}-[0-9]{2})\.$'
next_id_pattern="^The next item's id is OI-([1-9][0-9]*)\.$"
field_labels=("**Why:**" "**Action:**" "**Added in:**" "**Last confirmed:**")
format_hint="An item is one line: - **OI-<n>** <what it is> **Why:** <why it matters> **Action:** <what a person does or decides> **Added in:** [#<PR>](https://github.com/<owner>/<repo>/pull/<PR>). **Last confirmed:** YYYY-MM-DD."

failures=0
seen_ids=" "
next_id=""
next_id_lines=0
confirmed_before=""
latest_today=$(TZ=UTC-14 date +%F)

main() {
  if [[ ${1:-} == --confirmed-before ]]; then
    confirmed_before=${2:-}
    if ! [[ $confirmed_before =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "error: --confirmed-before needs a date as YYYY-MM-DD; got: $confirmed_before" >&2
      exit 1
    fi
    shift 2
  fi

  local files=("$@") file
  if ((${#files[@]} == 0)); then
    cd "$(dirname "$0")/../.."
    files=(docs/open-items.md)
    if [[ -f docs/template-open-items.md ]]; then
      files+=(docs/template-open-items.md)
    fi
  fi

  for file in "${files[@]}"; do
    check_file "$file"
  done
  check_next_id "${files[*]}"

  if ((failures > 0)); then
    echo "error: found the $failures problem(s) above in the open items. $format_hint" >&2
    exit 1
  fi
  [[ -n $confirmed_before ]] || echo "Every open item in ${files[*]} is well formed."
}

check_file() {
  local file=$1 line line_number=0 in_items=false
  if [[ ! -f $file ]]; then
    report "$file doesn't exist. Restore it from git; projects get it from the template."
    return
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    case $line in
      "## Needs a person" | "## Technical debt") in_items=true && continue ;;
      "#"*) in_items=false && continue ;;
    esac
    if [[ $line =~ $next_id_pattern ]]; then
      next_id=${BASH_REMATCH[1]}
      next_id_lines=$((next_id_lines + 1))
    elif [[ $in_items == true && -n $line ]]; then
      check_item "$file:$line_number" "$line"
    fi
  done < "$file"
}

check_item() {
  local place=$1 line=$2 label
  if [[ $line != "- **OI-"* ]]; then
    report "$place: only items go under this heading, and this line doesn't start with \"- **OI-\". Move other text above the first item heading."
    return
  fi
  for label in "${field_labels[@]}"; do
    if [[ $line != *"$label"* ]]; then
      report "$place: the item lacks its $label field."
      return
    fi
  done
  if ! [[ $line =~ $item_pattern ]]; then
    report "$place: the line doesn't match the format of an item."
    return
  fi

  local id=${BASH_REMATCH[1]} what=${BASH_REMATCH[2]}
  local linked_pr=${BASH_REMATCH[5]} url_pr=${BASH_REMATCH[6]} confirmed=${BASH_REMATCH[7]}
  local month=$((10#${confirmed:5:2})) day=$((10#${confirmed:8:2}))

  if [[ $seen_ids == *" $id "* ]]; then
    report "$place: OI-$id is the id of an earlier item too. Give this item the next id, and raise the next id by one."
  fi
  seen_ids="$seen_ids$id "
  if [[ $linked_pr != "$url_pr" ]]; then
    report "$place: OI-$id's Added in link says #$linked_pr but points at pull request $url_pr. Make them the same PR."
  fi
  if ((month < 1 || month > 12 || day < 1 || day > 31)); then
    report "$place: OI-$id's last confirmed date, $confirmed, is not a date. Write it as YYYY-MM-DD."
  elif [[ $confirmed > $latest_today ]]; then
    report "$place: OI-$id's last confirmed date, $confirmed, is later than today ($latest_today in UTC+14). Write the date it was last checked."
  elif [[ -n $confirmed_before && $confirmed < $confirmed_before ]]; then
    echo "- OI-$id, last confirmed $confirmed, in ${place%:*}: $what"
  fi
}

check_next_id() {
  local pages=$1 id
  if ((next_id_lines != 1)); then
    report "$pages: found $next_id_lines lines that read \"The next item's id is OI-<n>.\"; keep exactly one, above the items."
    return
  fi
  for id in $seen_ids; do
    if ((id >= next_id)); then
      report "$pages: OI-$id is not below the next id, OI-$next_id. Set the next id to one more than the largest id ever used."
    fi
  done
}

report() {
  echo "error: $1" >&2
  failures=$((failures + 1))
}

main "$@"
