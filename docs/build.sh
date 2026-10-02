#!/usr/bin/env bash
# Build the documentation site from source into docs/_build/html.
# Fails on any undocumented public symbol or docs warning, in any language.
# Each language task in docs/template-plan.md adds its block above sphinx-build.
set -euo pipefail
cd "$(dirname "$0")/.."
# Sphinx rereads only changed pages, so an incremental build would skip the
# warnings of unchanged ones.
rm -rf docs/_build

# Python: sphinx-autoapi reads it during sphinx-build; enforce docstrings first.
uv run ruff check --quiet src

# C and C++: Doxygen writes XML, which Breathe reads during sphinx-build.
# Doxygen skips undocumented functions and macros in a header that has no
# @file comment, so the build requires one in every header. Removing the old
# XML first drops symbols that no longer exist.
headers_without_file_comment=$(grep -rL '[@\]file' cpp/include || true)
if [[ -n $headers_without_file_comment ]]; then
  echo "error: add a @file doc comment to these headers, so that Doxygen reports their undocumented symbols:" >&2
  echo "$headers_without_file_comment" >&2
  exit 1
fi
rm -rf docs/_generated/doxygen
doxygen Doxyfile

uv run sphinx-build -W --keep-going -q -b html docs docs/_build/html
