#!/usr/bin/env bash
# Tests .github/scripts/ci_changes.sh in a temporary git repository that has
# each language's manifest. Each case commits some files on a branch of the
# base commit, runs the script, and checks which outputs are true: the files
# of each language must start that language's job, and a file of another
# language must not. It also checks that the outputs match those the changes
# job of .github/workflows/ci.yml declares.
#
# Usage: mise run test:ci-changes-script
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/ci_changes.sh
ci_workflow=$(cd "$(dirname "$0")/../workflows" && pwd)/ci.yml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
case_count=0

# Every output the script prints, sorted and separated by spaces, which is the
# form the cases give the outputs expected to be true.
every_output=""

main() {
  create_repository
  every_output=$(run_script main | sed 's/=.*//' | sort | tr '\n' ' ')

  expect_outputs_match_ci_workflow

  expect_true unrelated_file_starts_no_job "LICENSE" ""
  expect_true install_script_files_start_install_script ".cursor/install.sh" "install-script"
  expect_true docs_files_start_docs "docs/index.md README.md" "docs"

  expect_true python_source_starts_python "src/example/a.py" "python"
  expect_true python_tests_start_python "tests/test_a.py" "python"
  expect_true python_workspace_member_starts_python "member/src/member/a.py member/pyproject.toml" "python"
  expect_true python_repository_script_starts_python ".github/scripts/agent_spend.py" "python"
  expect_true python_lockfile_and_version_start_python "uv.lock .python-version" "python"
  expect_true python_mise_file_starts_python_and_install_script ".config/mise/conf.d/python.toml" "install-script language-listings python"
  expect_true docs_project_file_does_not_start_python "docs/pyproject.toml" "docs"
  expect_true rust_source_does_not_start_python "crates/example/src/lib.rs" "rust"
  expect_true typescript_source_does_not_start_python "packages/statistics/src/variance.ts" "typescript"
  expect_true cpp_source_does_not_start_python "cpp/src/a.cpp cpp/tests/a_test.cpp" "cpp"

  expect_true rust_crate_files_start_rust "crates/example/src/lib.rs crates/example/tests/a.rs" "rust"
  expect_true rust_workspace_files_start_rust "Cargo.toml Cargo.lock rust-toolchain.toml deny.toml" "rust"
  expect_true rust_mise_file_starts_rust_and_install_script ".config/mise/conf.d/rust.toml" "install-script language-listings rust"

  expect_true typescript_package_files_start_typescript "packages/statistics/src/variance.ts packages/statistics/package.json" "typescript"
  expect_true typescript_workspace_files_start_typescript \
    "package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json biome.json .dependency-cruiser.cjs" "typescript"
  expect_true typescript_mise_file_starts_typescript_and_install_script ".config/mise/conf.d/typescript.toml" "install-script language-listings typescript"

  expect_true cpp_files_start_cpp "cpp/include/example/a.hpp cpp/src/a.cpp cpp/tests/a_test.cpp" "cpp"
  expect_true cpp_root_files_start_cpp "CMakeLists.txt CMakePresets.json .clang-format .clang-tidy Doxyfile" "cpp"
  expect_true cpp_mise_file_starts_cpp_and_install_script ".config/mise/conf.d/cpp.toml" "cpp install-script language-listings"

  expect_true rulesets_start_rulesets ".github/rulesets/main.json" "rulesets"
  expect_true workflows_start_workflows_and_language_listings ".github/workflows/codeql.yml" "language-listings workflows"
  expect_true docs_build_script_starts_language_listings_and_docs "docs/build.sh" "docs language-listings"
  expect_true github_readme_starts_language_listings ".github/README.md" "language-listings"
  expect_true open_items_file_starts_open_items_and_docs "docs/open-items.md" "docs open-items"
  expect_true ci_changes_test_starts_ci_changes_script ".github/scripts/ci_changes_test.sh" "ci-changes-script"
  expect_true ci_changes_script_starts_ci_changes_script_and_language_listings ".github/scripts/ci_changes.sh" "ci-changes-script language-listings"
  expect_true auto_merge_files_start_auto_merge_script ".github/scripts/auto_merge.sh" "auto-merge-script"
  expect_true approve_agent_prs_files_start_approve_agent_prs_script ".github/rulesets/main-review.json" "approve-agent-prs-script rulesets"
  expect_true owned_paths_files_start_two_scripts ".github/scripts/owned_paths.sh" "auto-merge-script owned-paths-script"
  expect_true codeowners_starts_two_scripts ".github/CODEOWNERS" "auto-merge-script owned-paths-script"
  expect_true needs_human_review_files_start_needs_human_review_script ".github/scripts/needs_human_review_test.sh" "needs-human-review-script"
  expect_true linear_queue_files_start_linear_queue_script ".github/scripts/linear_queue.sh" "linear-queue-script"

  expect_true ci_workflow_starts_every_job ".github/workflows/ci.yml" "$every_output"
  expect_true mise_toml_starts_every_job "mise.toml" "$every_output"
  expect_true block_unlisted_tools_script_starts_every_job ".github/scripts/block_unlisted_tools.sh" "$every_output"

  expect_true language_without_manifest_starts_no_job "rm:Cargo.toml crates/example/src/lib.rs" ""
  expect_true_for_unknown_base unknown_base_starts_every_job "$every_output"

  if ((failures > 0)); then
    exit 1
  fi
  echo "ci_changes.sh gave the expected outputs in all $case_count cases."
}

# Creates the repository in $work/repository, whose first commit, on the
# branch main, has each language's manifest and a README.
create_repository() {
  git init --quiet --initial-branch=main "$work/repository"
  cd "$work/repository"
  git config user.name test
  git config user.email test@example.com
  # Signing and the file system monitor, which a developer's global git
  # configuration may turn on, make each commit take seconds.
  git config commit.gpgsign false
  git config core.fsmonitor false
  local file
  for file in pyproject.toml Cargo.toml package.json CMakeLists.txt .github/workflows/ci.yml mise.toml README.md; do
    mkdir -p "$(dirname "$file")"
    echo original > "$file"
  done
  git add --all
  git commit --quiet --message "Base commit"
}

# Runs the script in the repository and prints its output lines.
# Arguments: the base to compare with.
run_script() {
  "$script" "$1" 2> /dev/null
}

# Prints the outputs that are true, sorted and separated by spaces.
# Arguments: the base to compare with.
true_outputs() {
  run_script "$1" | { grep '=true$' || true; } | sed 's/=true$//' | sort | tr '\n' ' '
}

# Commits the files on a new branch of main. A file named rm:<path> is
# deleted, and a file that main has is modified, so that a manifest can change.
# Arguments: the files.
commit_files() {
  local file
  git checkout --quiet --force -B work main
  for file in "$@"; do
    if [[ $file == rm:* ]]; then
      rm "${file#rm:}"
    else
      mkdir -p "$(dirname "$file")"
      echo changed >> "$file"
    fi
  done
  git add --all
  git commit --quiet --allow-empty --message "Change files"
}

# Commits each file alone, so that one matching file can't hide another that
# no longer matches, and checks the true outputs. The files are committed
# together if one is a deletion, which a case uses to remove a manifest.
# Arguments: the case's name, the files separated by spaces, and the outputs
# that must be true and no others, sorted and separated by spaces.
expect_true() {
  local name=$1 files=$2 expected=$3 file
  if [[ $files == *rm:* ]]; then
    # shellcheck disable=SC2086 # Each file name is a word.
    expect_true_for_commit "$name" "$expected" $files
    return
  fi
  for file in $files; do
    expect_true_for_commit "$name: $file" "$expected" "$file"
  done
}

# Arguments: the case's name, the outputs expected, and the files to commit.
expect_true_for_commit() {
  local name=$1 expected=$2
  shift 2
  commit_files "$@"
  check_case "$name" "$expected" "$(true_outputs main)"
}

# Arguments: the case's name, and the outputs that must be true.
expect_true_for_unknown_base() {
  local name=$1 expected=$2
  commit_files LICENSE
  check_case "$name" "$expected" "$(true_outputs no-such-ref)"
}

# Arguments: the case's name, the outputs expected, and those found.
check_case() {
  local name=$1 expected=${2% } actual=${3% }
  case_count=$((case_count + 1))
  if [[ $actual != "$expected" ]]; then
    echo "FAIL: $name: got [$actual], expected [$expected]." >&2
    failures=$((failures + 1))
    return
  fi
  echo "$name: passed."
}

# Fails if the script prints an output that the changes job doesn't declare,
# or the job declares one the script doesn't print.
expect_outputs_match_ci_workflow() {
  local from_script from_workflow
  from_script=$every_output
  from_workflow=$(sed -n 's/^      [a-z-]*: \${{ steps.diff.outputs.\([a-z-]*\) }}$/\1/p' "$ci_workflow" | sort | tr '\n' ' ')
  check_case outputs_match_the_changes_job_in_ci_yml "$from_workflow" "$from_script"
}

main "$@"
