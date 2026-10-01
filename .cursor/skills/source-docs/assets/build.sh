#!/usr/bin/env bash
# Build the documentation site from source into docs/_build/html.
# Fails on any undocumented public symbol or docs warning, in any language.
# Keep one block per language in the repo; delete the others.
set -euo pipefail
cd "$(dirname "$0")/.."
gen=docs/_generated
rm -rf "$gen" docs/_build
mkdir -p "$gen/html/api"

# Diagrams: committed SVGs must match their D2 sources.
docs/diagrams/render.sh --check

# Python: sphinx-autoapi reads it during sphinx-build; enforce docstrings first.
ruff check --quiet src

# TypeScript: TypeDoc -> Markdown, rendered inside the site.
(cd web && npx typedoc src/index.ts --plugin typedoc-plugin-markdown \
  --out "../$gen/ts" --entryFileName index --readme none --outputFileStrategy modules \
  --validation.notDocumented --treatWarningsAsErrors)

# Rust: rustdoc HTML, embedded under api/rust/ (needs #![deny(missing_docs)]).
RUSTDOCFLAGS="-D warnings" cargo doc --quiet --no-deps --target-dir "$gen/rust-target"
cp -r "$gen/rust-target/doc" "$gen/html/api/rust"

# Go: gomarkdoc -> Markdown, rendered inside the site.
# gomarkdoc --output "$gen/go/{{.Dir}}.md" ./...

# C/C++: Doxygen XML, read by Breathe (Doxyfile: GENERATE_XML=YES, WARN_AS_ERROR=YES).
# doxygen Doxyfile

sphinx-build -W --keep-going -q -b html docs docs/_build/html
