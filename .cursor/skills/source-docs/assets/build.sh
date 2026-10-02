#!/usr/bin/env bash
# Build the documentation site from source into docs/_build/html.
# Fails on any undocumented public symbol or docs warning, in any language.
# Keep one block per language in the repo; delete the others.
set -euo pipefail
cd "$(dirname "$0")/.."
# Sphinx rereads only changed pages, so an incremental build would skip the
# warnings of unchanged ones. Generated pages are rebuilt each time too.
rm -rf docs/_build docs/_generated

# Diagrams: committed SVGs must match their D2 sources.
docs/diagrams/render.sh --check

# Python: sphinx-autoapi reads it during sphinx-build; enforce docstrings first.
ruff check --quiet src

# TypeScript: TypeDoc -> Markdown, rendered inside the site.
(cd web && npx typedoc src/index.ts --plugin typedoc-plugin-markdown \
  --out ../docs/_generated/ts --entryFileName index --readme none --outputFileStrategy modules \
  --validation.notDocumented --treatWarningsAsErrors)

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

# C/C++: Doxygen XML, read by Breathe. Doxygen skips undocumented functions and
# macros in a header with no @file comment, so require one in every header.
missing_file_comment=$(grep -rL '[@\]file' include || true)
if [[ -n $missing_file_comment ]]; then
  echo "error: add a @file doc comment to: $missing_file_comment" >&2
  exit 1
fi
doxygen Doxyfile

sphinx-build -W --keep-going -q -b html docs docs/_build/html
