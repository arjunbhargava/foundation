#!/usr/bin/env bash
# Prints one `<output>=true` or `<output>=false` line for each output of the
# changes job in .github/workflows/ci.yml, which decides which CI jobs run.
# An output is true when the pull request changes a file its job depends on,
# so that a job runs only when something it checks has changed. The diff step
# of the changes job appends the lines to $GITHUB_OUTPUT.
#
# Usage: .github/scripts/ci_changes.sh <base>
#
# <base> is the commit or ref to compare with, such as origin/main. Run it
# from the repository root. It compares <base>...HEAD, the changes on this
# branch since it left <base>. Its test is ci_changes_test.sh, run by
# `mise run test:ci-changes-script`.
#
# Each output's files are git pathspecs: a trailing / matches a directory, *
# matches any characters including /, and :(exclude) removes files from the
# match. Every output is also true when ci.yml, mise.toml, or the
# block_unlisted_tools script and its test change, because they define or
# affect every job. A failed diff, such as an unknown <base>, makes every
# output true, so an error runs jobs rather than skipping them.
set -euo pipefail

base=${1:?give the commit or ref to compare with, such as origin/main}

main() {
  echo "install-script=$(changed .cursor/install.sh .cursor/environment.json .config/mise/conf.d/)"
  # The site includes README.md and AGENTS.md as pages.
  echo "docs=$(changed docs/ README.md AGENTS.md)"
  echo "python=$(language_changed pyproject.toml '*.py' '*/pyproject.toml' ':(exclude)docs/pyproject.toml' src/ tests/ '*/src/*' '*/tests/*' ':(exclude)crates/*/src/*' ':(exclude)crates/*/tests/*' ':(exclude)packages/*/src/*' ':(exclude)packages/*/tests/*' ':(exclude)cpp/src/*' ':(exclude)cpp/tests/*' uv.lock .python-version .config/mise/conf.d/python.toml)"
  echo "rust=$(language_changed Cargo.toml crates/ Cargo.lock rust-toolchain.toml deny.toml .config/mise/conf.d/rust.toml)"
  echo "typescript=$(language_changed package.json packages/ pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json biome.json .dependency-cruiser.cjs .config/mise/conf.d/typescript.toml)"
  echo "cpp=$(language_changed CMakeLists.txt cpp/ CMakePresets.json .clang-format .clang-tidy Doxyfile .config/mise/conf.d/cpp.toml)"
  echo "rulesets=$(changed .github/rulesets/ .github/scripts/setup_status.sh .github/scripts/setup_status_test.sh)"
  echo "workflows=$(changed .github/workflows/ .github/scripts/lint_workflows.sh .github/scripts/lint_workflows_test.sh)"
  # The files the check reads, which are those that list the languages.
  echo "language-listings=$(changed .github/scripts/language_listings.sh .github/scripts/language_listings_test.sh .github/scripts/ci_changes.sh .config/mise/conf.d/ .github/workflows/ docs/build.sh docs/api/ AGENTS.md .github/README.md copier.yml)"
  echo "open-items=$(changed .github/scripts/open_items.sh .github/scripts/open_items_test.sh docs/open-items.md docs/template-open-items.md)"
  echo "ci-changes-script=$(changed .github/scripts/ci_changes.sh .github/scripts/ci_changes_test.sh)"
  # The script runs owned_paths.sh, which reads .github/CODEOWNERS.
  echo "auto-merge-script=$(changed .github/scripts/auto_merge.sh .github/scripts/auto_merge_test.sh .github/scripts/owned_paths.sh .github/CODEOWNERS)"
  # The script reads the review rulesets' names from their files.
  echo "approve-agent-prs-script=$(changed .github/scripts/approve_agent_prs.sh .github/scripts/approve_agent_prs_test.sh .github/rulesets/main-review.json .github/rulesets/main-review-auto.json)"
  # The test also checks the repository's own .github/CODEOWNERS.
  echo "owned-paths-script=$(changed .github/scripts/owned_paths.sh .github/scripts/owned_paths_test.sh .github/CODEOWNERS)"
  echo "needs-human-review-script=$(changed .github/scripts/needs_human_review.sh .github/scripts/needs_human_review_test.sh)"
  echo "linear-queue-script=$(changed .github/scripts/linear_queue.sh .github/scripts/linear_queue_test.sh)"
}

# Prints true if a file matching any pathspec argument, or a file that
# affects every job, changed since the base, and false if none did.
changed() {
  if git diff --quiet "$base...HEAD" -- "$@" .github/workflows/ci.yml mise.toml .github/scripts/block_unlisted_tools.sh .github/scripts/block_unlisted_tools_test.sh; then
    echo false
  else
    echo true
  fi
}

# Like changed, but prints false when the first argument, the language's
# manifest, is missing, so a project without the language skips its job. The
# manifest is also one of the language's files. language_listings.sh reads
# each language's manifest from its line in main.
language_changed() {
  if [[ -f $1 ]]; then
    changed "$@"
  else
    echo false
  fi
}

main
