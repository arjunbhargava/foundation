#!/usr/bin/env bash
# Checks the GitHub Actions workflows in a directory with actionlint, which
# finds syntax and type errors and, through shellcheck, errors in run:
# scripts, and with zizmor, which finds security problems. Both tools always
# run, so one failure doesn't hide the other's findings; the script exits 1 if
# either reports a finding.
#
# zizmor runs with --offline, which skips its audits that query GitHub, so
# the result doesn't depend on a token or the network.
#
# Usage: mise run lint:workflows
# The optional argument is the directory to check, default .github/workflows,
# which the test of this script changes.
set -uo pipefail

workflows_dir=${1:-.github/workflows}
status=0

actionlint "$workflows_dir"/*.yml || status=1
zizmor --offline --no-progress "$workflows_dir"/*.yml || status=1

exit "$status"
