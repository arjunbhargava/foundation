#!/usr/bin/env bash
# Mutation-tests the code that the current branch changed, and reports each
# mutant that survived. A mutant is a small deliberate bug, such as `<`
# replaced by `<=`. It survives when every test still passes, which marks
# behaviour that no test checks.
#
# Usage: scripts/mutate.sh python|rust [base]
#
# Changed means different from the merge base with base (default
# origin/main), including uncommitted changes. The mutated files are the
# changed source files, plus every source file of a package whose tests
# changed, because a changed test can stop checking any code in its package.
# A change to this script or its workflow mutates every package.
#
# The report goes to stdout and, in GitHub Actions, to the job summary.
# Surviving mutants don't fail the script: for now, mutation testing reports
# and doesn't block merging (T14 in docs/template-plan.md). It fails only when
# the tool does, for example when a test fails before any code is mutated.
#
# Keep it working under bash 3.2, the version macOS ships: no mapfile.
set -euo pipefail
cd "$(dirname "$0")/.."

language=${1:-}
base=${2:-origin/main}
if ! merge_base=$(git merge-base "$base" HEAD); then
  echo "error: HEAD and '$base' have no merge base. Fetch the base, for example with 'git fetch origin main', or pass another one." >&2
  exit 1
fi

main() {
  case $language in
    python) mutate_python ;;
    rust) mutate_rust ;;
    *)
      echo "error: scripts/mutate.sh mutates python or rust, not '$language'." >&2
      exit 1
      ;;
  esac
}

mutate_python() {
  local files
  files=$(files_to_mutate 'src/*.py' tests/)
  if [[ -z $files ]]; then
    report Python "" 0 0 ""
    return
  fi

  # mutmut names each mutant <module>.x<function>__mutmut_<n>, and the module
  # of a package's __init__.py is the package. So a package's glob also
  # matches its submodules whose names start with x, which only tests extra
  # mutants.
  local module_globs=() path module
  for path in $files; do
    module=${path#src/}
    module=${module%.py}
    module=${module%/__init__}
    module_globs+=("${module//\//.}.x*")
  done

  # mutmut reuses results from earlier runs, which a changed test can make
  # wrong.
  rm -rf mutants
  mkdir mutants
  if ! uv run mutmut run "${module_globs[@]}" 2>&1 | tee mutants/run.log; then
    if grep -qF "Filtered for specific mutants, but nothing matches" mutants/run.log; then
      report Python "$files" 0 0 "mutmut found no code to mutate in these files."
      return
    fi
    echo "error: mutmut failed; its output is above." >&2
    return 1
  fi

  # Each line is "<mutant>: <status>". mutmut generates mutants in every file,
  # and leaves those outside the globs "not checked". "no tests" means no test
  # calls the mutated function.
  local results survivors survived_count tested_count status_counts
  results=$(uv run mutmut results --all true)
  survivors=$(awk -F': ' '$2 == "survived" || $2 == "no tests" { print $1 }' <<< "$results")
  survived_count=$(count_lines "$survivors")
  tested_count=$(awk -F': ' '$2 != "not checked" { n++ } END { print n + 0 }' <<< "$results")
  status_counts=$(awk -F': ' '$2 != "not checked" { count[$2]++ } END { for (status in count) printf "%s%d %s", (n++ ? ", " : ""), count[status], status }' <<< "$results")

  local mutant
  {
    echo '```diff'
    for mutant in $survivors; do
      uv run mutmut show "$mutant"
    done
    echo '```'
  } | report Python "$files" "$survived_count" "$tested_count" "mutmut: $status_counts."
}

mutate_rust() {
  local files crate
  files=$(for crate in crates/*/; do files_to_mutate "${crate}src/*.rs" "${crate}tests/"; done)
  if [[ -z $files ]]; then
    report Rust "" 0 0 ""
    return
  fi

  local file_options=() path
  for path in $files; do
    file_options+=(--file "$path")
  done
  # cargo-mutants builds the mutants in a copy of the source tree.
  # --gitignore true leaves out what git ignores: 500 MB of .venv,
  # node_modules, and build output here, and mutmut's mutants/, which
  # mutate:python rewrites while `mise run mutate` runs both.
  local status=0
  cargo mutants --gitignore true --no-shuffle --output target "${file_options[@]}" || status=$?
  # 2 means some mutants survived, and 3 that some timed out: results to
  # report, not failures.
  if ((status != 0 && status != 2 && status != 3)); then
    echo "error: cargo mutants exited with status $status; its output is above." >&2
    return "$status"
  fi

  local results_dir=target/mutants.out mutant_count
  mutant_count=$(jq length "$results_dir/mutants.json")
  if ((mutant_count == 0)); then
    report Rust "$files" 0 0 "cargo-mutants found no code to mutate in these files."
    return
  fi

  local survived_count outcome_counts
  survived_count=$(jq .missed "$results_dir/outcomes.json")
  outcome_counts=$(jq -r '"cargo-mutants: \(.caught) caught, \(.missed) missed, \(.timeout) timed out, \(.unviable) unviable (failed to build)."' "$results_dir/outcomes.json")
  {
    echo '```text'
    cat "$results_dir/missed.txt"
    echo '```'
  } | report Rust "$files" "$survived_count" "$mutant_count" "$outcome_counts"
}

# Prints the source files to mutate in one package: all of them if any of its
# tests changed, and otherwise those that changed. A change to this script or
# its workflow counts as a change to every package's tests, so that the PR
# making it runs every step here in CI.
files_to_mutate() {
  local sources=$1 tests=$2
  if git diff --quiet "$merge_base" -- "$tests" scripts/mutate.sh .github/workflows/mutation.yml; then
    git diff --name-only --diff-filter=d "$merge_base" -- "$sources"
  else
    git ls-files -- "$sources"
  fi
}

# Prints one language's report, and in GitHub Actions appends it to the job
# summary. With surviving mutants, it reads their list from stdin.
report() {
  local language=$1 files=$2 survived=$3 total=$4 tool_counts=$5
  if [[ -z $files ]]; then
    echo "### $language mutation testing: no source or test file changed since the merge base with $base"
  else
    echo "### $language mutation testing: $survived of $total mutants survived"
    echo
    echo "Mutated files: ${files//$'\n'/, }"
    echo
    echo "$tool_counts"
    if ((survived > 0)); then
      echo
      echo "Every test still passes with each change below. Add a test that fails on it, or say in the PR why the change can't alter behaviour."
      echo
      cat
    fi
  fi | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Prints the number of non-empty lines in its argument.
count_lines() {
  awk 'NF { n++ } END { print n + 0 }' <<< "$1"
}

main "$@"
