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

# TypeScript: TypeDoc writes Markdown, which MyST renders inside the site.
pnpm exec typedoc packages/statistics/src/variance.ts --plugin typedoc-plugin-markdown \
  --out docs/_generated/ts --entryFileName index --readme none --outputFileStrategy modules \
  --hidePageHeader --validation.notDocumented --treatWarningsAsErrors

uv run sphinx-build -W --keep-going -q -b html docs docs/_build/html
