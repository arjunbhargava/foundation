#!/usr/bin/env bash
# Build the documentation site from source into docs/_build/html.
# Fails on any undocumented public symbol or docs warning, in any language.
# Each language task in docs/template-plan.md adds its block above sphinx-build.
set -euo pipefail
cd "$(dirname "$0")/.."
# Sphinx rereads only changed pages, so an incremental build would skip the
# warnings of unchanged ones. Generated pages are rebuilt each time too.
rm -rf docs/_build docs/_generated

# Python: sphinx-autoapi reads it during sphinx-build; enforce docstrings first.
uv run ruff check --quiet src

# Rust: rustdoc's HTML, published under api/rust/ and linked from
# docs/api/rust.md. -D missing_docs also covers a crate that lacks
# #![deny(missing_docs)]. Removing target/doc first drops the pages of a crate
# that no longer exists.
rm -rf target/doc
RUSTDOCFLAGS="-D warnings -D missing_docs" cargo doc --quiet --locked --no-deps
mkdir -p docs/_generated/html/api
cp -r target/doc docs/_generated/html/api/rust
for linked_page in $(grep -o 'href="rust/[^"]*"' docs/api/rust.md | cut -d '"' -f 2); do
  if [[ ! -f docs/_generated/html/api/$linked_page ]]; then
    echo "error: docs/api/rust.md links to $linked_page, which rustdoc didn't generate. Make its links match the crates in crates/." >&2
    exit 1
  fi
done

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
