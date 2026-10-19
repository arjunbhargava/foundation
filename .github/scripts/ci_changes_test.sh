#!/usr/bin/env bash
# Tests .github/scripts/ci_changes.sh in a scratch git repository. Each case
# changes one file in a commit on top of a base commit that has every
# language's manifest, runs the script, and checks that exactly the expected
# jobs are 'true'. Other cases remove a manifest, and pass a base that does
# not exist.
#
# Usage: mise run test:ci-changes-script
set -euo pipefail

script_source=$(cd "$(dirname "$0")" && pwd)/ci_changes.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
failures=0
cases=0

every_job=(install-script docs python rust typescript cpp rulesets workflows language-listings auto-merge-script approve-agent-prs-script owned-paths-script needs-human-review-script linear-queue-script ci-changes-script)

main() {
  create_repository

  # Files that define or affect every job.
  for file in .github/workflows/ci.yml mise.toml \
    .github/scripts/block_unlisted_tools.sh .github/scripts/block_unlisted_tools_test.sh \
    .github/scripts/ci_changes_test.sh; do
    expect_jobs "$file" "${every_job[@]}"
  done
  expect_jobs .github/scripts/ci_changes.sh "${every_job[@]}"
  expect_jobs LICENSE

  # install-script
  expect_jobs .cursor/install.sh install-script
  expect_jobs .cursor/environment.json install-script
  expect_jobs .config/mise/conf.d/template.toml install-script language-listings

  # docs
  expect_jobs docs/index.md docs
  expect_jobs README.md docs
  expect_jobs AGENTS.md docs language-listings
  expect_jobs docs/api/python.md docs language-listings
  expect_jobs docs/build.sh docs language-listings
  expect_jobs docs/pyproject.toml docs
  expect_jobs docs/conf.py docs python

  # python
  expect_jobs pyproject.toml python
  expect_jobs uv.lock python
  expect_jobs .python-version python
  expect_jobs .config/mise/conf.d/python.toml python install-script language-listings
  expect_jobs src/foundation/__init__.py python
  expect_jobs src/foundation/py.typed python
  expect_jobs tests/test_quadrature.py python
  expect_jobs tests/data.json python
  expect_jobs tools/check.py python
  expect_jobs .github/scripts/agent_spend.py python
  expect_jobs members/member/pyproject.toml python
  expect_jobs members/member/src/member/py.typed python
  expect_jobs members/member/tests/data.json python

  # rust
  expect_jobs Cargo.toml rust
  expect_jobs Cargo.lock rust
  expect_jobs rust-toolchain.toml rust
  expect_jobs deny.toml rust
  expect_jobs .config/mise/conf.d/rust.toml rust install-script language-listings
  expect_jobs crates/foundation/Cargo.toml rust
  expect_jobs crates/foundation/src/lib.rs rust
  expect_jobs crates/foundation/tests/verlet.rs rust

  # typescript
  expect_jobs package.json typescript
  expect_jobs pnpm-lock.yaml typescript
  expect_jobs pnpm-workspace.yaml typescript
  expect_jobs tsconfig.json typescript
  expect_jobs biome.json typescript
  expect_jobs .dependency-cruiser.cjs typescript
  expect_jobs .config/mise/conf.d/typescript.toml typescript install-script language-listings
  expect_jobs packages/statistics/package.json typescript
  expect_jobs packages/statistics/src/variance.ts typescript
  expect_jobs packages/statistics/src/variance.test.ts typescript

  # cpp
  expect_jobs CMakeLists.txt cpp
  expect_jobs CMakePresets.json cpp
  expect_jobs .clang-format cpp
  expect_jobs .clang-tidy cpp
  expect_jobs Doxyfile cpp
  expect_jobs .config/mise/conf.d/cpp.toml cpp install-script language-listings
  expect_jobs cpp/include/foundation/interpolation.hpp cpp
  expect_jobs cpp/src/interpolation.cpp cpp
  expect_jobs cpp/tests/interpolation_test.cpp cpp

  # The jobs for the repository's own scripts and files.
  expect_jobs .github/rulesets/main.json rulesets
  expect_jobs .github/scripts/setup_status.sh rulesets
  expect_jobs .github/scripts/setup_status_test.sh rulesets
  expect_jobs .github/workflows/codeql.yml workflows language-listings
  expect_jobs .github/scripts/lint_workflows.sh workflows
  expect_jobs .github/scripts/lint_workflows_test.sh workflows
  expect_jobs .github/scripts/language_listings.sh language-listings
  expect_jobs .github/scripts/language_listings_test.sh language-listings
  expect_jobs .github/README.md language-listings
  expect_jobs copier.yml language-listings
  expect_jobs .github/scripts/auto_merge.sh auto-merge-script
  expect_jobs .github/scripts/auto_merge_test.sh auto-merge-script
  expect_jobs .github/scripts/owned_paths.sh auto-merge-script owned-paths-script
  expect_jobs .github/scripts/owned_paths_test.sh owned-paths-script
  expect_jobs .github/CODEOWNERS auto-merge-script owned-paths-script
  expect_jobs .github/scripts/approve_agent_prs.sh approve-agent-prs-script
  expect_jobs .github/scripts/approve_agent_prs_test.sh approve-agent-prs-script
  expect_jobs .github/rulesets/main-review.json rulesets approve-agent-prs-script
  expect_jobs .github/rulesets/main-review-auto.json rulesets approve-agent-prs-script
  expect_jobs .github/scripts/needs_human_review.sh needs-human-review-script
  expect_jobs .github/scripts/needs_human_review_test.sh needs-human-review-script
  expect_jobs .github/scripts/linear_queue.sh linear-queue-script
  expect_jobs .github/scripts/linear_queue_test.sh linear-queue-script

  # A language's job doesn't run without its manifest, whatever changes.
  expect_jobs_without_manifest pyproject.toml src/foundation/__init__.py
  expect_jobs_without_manifest Cargo.toml crates/foundation/src/lib.rs
  expect_jobs_without_manifest package.json packages/statistics/src/variance.ts
  expect_jobs_without_manifest CMakeLists.txt cpp/src/interpolation.cpp

  expect_every_job_when_the_diff_fails

  if ((failures > 0)); then
    exit 1
  fi
  echo "ci_changes.sh started the expected jobs in all $cases cases."
}

# Creates the scratch repository, whose base commit has each language's
# manifest and a copy of the script, and which the cases build on.
create_repository() {
  mkdir -p "$repo/.github/scripts"
  cp "$script_source" "$repo/.github/scripts/ci_changes.sh"
  git -C "$repo" init -q
  local manifest
  for manifest in pyproject.toml Cargo.toml package.json CMakeLists.txt LICENSE; do
    echo "base" > "$repo/$manifest"
  done
  commit "base"
  git -C "$repo" tag base
}

# Commits everything in the working tree. Argument: the commit message.
commit() {
  git -C "$repo" add --all
  git -C "$repo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m "$1"
}

# Resets the repository to the base commit.
reset_repository() {
  git -C "$repo" reset -q --hard base
  git -C "$repo" clean -fdq
}

# Changes <file> in a commit on top of the base, runs the script, and checks
# that the jobs it prints as 'true' are the expected ones, in any order.
# Arguments: the file, then the jobs expected to be 'true', if any.
expect_jobs() {
  local file=$1
  shift
  reset_repository
  mkdir -p "$repo/$(dirname "$file")"
  echo "changed" >> "$repo/$file"
  commit "change $file"
  check_jobs "changing $file" "$*" "$("$repo/.github/scripts/ci_changes.sh" base)"
}

# Removes <manifest> and adds <file> in a commit on top of the base, and
# checks that the language's job doesn't run, and no other does.
# Arguments: the manifest and a file of the same language.
expect_jobs_without_manifest() {
  local manifest=$1 file=$2
  reset_repository
  rm "$repo/$manifest"
  mkdir -p "$repo/$(dirname "$file")"
  echo "changed" >> "$repo/$file"
  commit "remove $manifest and change $file"
  check_jobs "removing $manifest and changing $file" "" "$("$repo/.github/scripts/ci_changes.sh" base)"
}

expect_every_job_when_the_diff_fails() {
  reset_repository
  check_jobs "an unknown base" "${every_job[*]}" "$("$repo/.github/scripts/ci_changes.sh" no-such-base 2> /dev/null)"
}

# Arguments: a description of the change, the expected jobs separated by
# spaces, and the script's output.
check_jobs() {
  local description=$1 expected=$2 output=$3
  local actual
  actual=$(printf '%s\n' "$output" | sed -n 's/=true$//p' | sort | tr '\n' ' ')
  expected=$(for job in $expected; do echo "$job"; done | sort | tr '\n' ' ')
  cases=$((cases + 1))
  if [[ $actual != "$expected" ]]; then
    echo "FAIL: after $description, the jobs set to true were [${actual% }], expected [${expected% }]. Output:
$output" >&2
    failures=$((failures + 1))
  fi
}

main "$@"
