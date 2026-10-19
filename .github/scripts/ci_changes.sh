#!/usr/bin/env bash
# Decides which CI jobs a change needs, for the changes job in
# .github/workflows/ci.yml. For each job it prints a line `<job>=true` when
# the change touches that job's files and `<job>=false` when it doesn't, in
# the format GitHub Actions reads from $GITHUB_OUTPUT.
#
# Usage: .github/scripts/ci_changes.sh <base>
#
# <base> is the commit the change starts from, such as origin/main. The
# change is the diff from the merge base of <base> and HEAD to HEAD.
#
# Every job also runs when ci.yml, mise.toml, or the block_unlisted_tools
# script and its test change, or this script and its test, because they
# define or affect every job. A failed diff, for example an unknown <base>,
# counts as a change, so an error runs jobs rather than skipping them.
#
# A language's job doesn't run when its manifest, which is the first file of
# its line below, is missing, so a project without the language skips its
# job. Each such line's format is read by language_listings.sh.
#
# install-script's files include every language's mise file, because that job
# is the only one that installs the tools on Linux arm64 and macOS.
#
# Keep it working under bash 3.2, the version macOS ships.
set -euo pipefail
cd "$(dirname "$0")/../.."

base=${1:?usage: .github/scripts/ci_changes.sh <base>, for example origin/main}

# Each argument is a git pathspec.
changed() {
  if git diff --quiet "$base...HEAD" -- "$@" \
    .github/workflows/ci.yml mise.toml \
    .github/scripts/block_unlisted_tools.sh .github/scripts/block_unlisted_tools_test.sh \
    .github/scripts/ci_changes.sh .github/scripts/ci_changes_test.sh; then
    echo false
  else
    echo true
  fi
}

# The first argument is the language's manifest, which is also one of its
# files. A language's members are the directories below the root that hold a
# file with the manifest's name, such as crates/foundation for Cargo.toml, and
# all their files count too, wherever the project keeps its members. docs/ is
# not a member: it is Sphinx's own Python project, which the docs job covers.
language_changed() {
  local manifest=$1
  if [[ ! -f $manifest ]]; then
    echo false
    return
  fi

  local pathspecs=("$@") member_manifest member_directory
  while IFS= read -r member_manifest; do
    member_directory=$(dirname "$member_manifest")
    if [[ $member_directory != docs ]]; then
      pathspecs+=(":(literal)$member_directory/")
    fi
  done < <(git ls-files -- "*/$manifest")
  changed "${pathspecs[@]}"
}

echo "install-script=$(changed .cursor/install.sh .cursor/environment.json .config/mise/conf.d/)"
# The site includes README.md and AGENTS.md as pages.
echo "docs=$(changed docs/ README.md AGENTS.md)"
echo "python=$(language_changed pyproject.toml '*.py' '*/pyproject.toml' ':(exclude)docs/pyproject.toml' src/ tests/ uv.lock .python-version .config/mise/conf.d/python.toml)"
echo "rust=$(language_changed Cargo.toml '*/Cargo.toml' crates/ Cargo.lock rust-toolchain.toml deny.toml .config/mise/conf.d/rust.toml)"
echo "typescript=$(language_changed package.json '*/package.json' packages/ pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json 'tsconfig.*.json' biome.json stryker.config.json .dependency-cruiser.cjs .config/mise/conf.d/typescript.toml)"
echo "cpp=$(language_changed CMakeLists.txt '*/CMakeLists.txt' cpp/ CMakePresets.json .clang-format .clang-tidy Doxyfile .config/mise/conf.d/cpp.toml)"
echo "rulesets=$(changed .github/rulesets/ .github/scripts/setup_status.sh .github/scripts/setup_status_test.sh)"
echo "workflows=$(changed .github/workflows/ .github/scripts/lint_workflows.sh .github/scripts/lint_workflows_test.sh)"
# The files the check reads, which are those that list the languages.
echo "language-listings=$(changed .github/scripts/ci_changes.sh .github/scripts/language_listings.sh .github/scripts/language_listings_test.sh .config/mise/conf.d/ .github/workflows/ docs/build.sh docs/api/ AGENTS.md .github/README.md copier.yml)"
# The script runs owned_paths.sh, which reads .github/CODEOWNERS.
echo "auto-merge-script=$(changed .github/scripts/auto_merge.sh .github/scripts/auto_merge_test.sh .github/scripts/owned_paths.sh .github/CODEOWNERS)"
# The script reads the review rulesets' names from their files.
echo "approve-agent-prs-script=$(changed .github/scripts/approve_agent_prs.sh .github/scripts/approve_agent_prs_test.sh .github/rulesets/main-review.json .github/rulesets/main-review-auto.json)"
# The test also checks the repository's own .github/CODEOWNERS.
echo "owned-paths-script=$(changed .github/scripts/owned_paths.sh .github/scripts/owned_paths_test.sh .github/CODEOWNERS)"
echo "needs-human-review-script=$(changed .github/scripts/needs_human_review.sh .github/scripts/needs_human_review_test.sh)"
echo "linear-queue-script=$(changed .github/scripts/linear_queue.sh .github/scripts/linear_queue_test.sh)"
# This script and its test are already in every output's files.
echo "ci-changes-script=$(changed)"
