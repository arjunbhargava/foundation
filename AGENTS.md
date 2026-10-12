# Agent instructions

## Commands

`mise.toml` defines the shared commands, and each language's file in
`.config/mise/conf.d/` defines that language's, so people, agents, and CI run
the same thing:

| Command | What it does |
|---|---|
| `mise run setup` | Install project dependencies. |
| `mise run fmt` | Format all code in place. `fmt:<language>` formats one language. |
| `mise run lint` | Check formatting, lint, and types without changing files. |
| `mise run lint:python` | Run only the Python checks. |
| `mise run lint:rust` | Run only the Rust checks, including cargo-deny's advisory, ban, licence, and source checks. |
| `mise run lint:typescript` | Run only the TypeScript checks. |
| `mise run lint:cpp` | Run only the C and C++ checks: clang-format, a check that no `#include` uses `../`, and a build with clang-tidy and compiler warnings as errors. |
| `mise run lint:rulesets` | Check that the ruleset files in `.github/rulesets/` are valid JSON and that the two review rulesets differ only in name, approval count, and thread resolution. |
| `mise run test` | Run all tests. |
| `mise run test:python` | Run only the Python tests and docstring examples. Arguments after `--` go to pytest: `mise run test:python -- -k trapezoid`. |
| `mise run test:rust` | Run only the Rust tests and doc-comment examples. Arguments after `--` go to `cargo test`: `mise run test:rust -- energy`. |
| `mise run test:typescript` | Run only the TypeScript tests. Arguments after `--` go to vitest: `mise run test:typescript -- -t precision`. |
| `mise run test:cpp` | Build the C and C++ tests with AddressSanitizer and UndefinedBehaviorSanitizer, and run them. Arguments after `--` go to ctest: `mise run test:cpp -- -R chord`. |
| `mise run test:rulesets` | Check the changes `.github/rulesets/apply.sh` makes with and without `--auto`, and that `lint:rulesets` catches broken ruleset files, with a fake `gh`. |
| `mise run test:auto-merge-script` | Check when `.github/scripts/auto_merge.sh` turns auto-merge on and off, and which PRs it leaves alone, with a fake `gh`. |
| `mise run test:mutate-script` | Check which files `.github/scripts/mutate.sh` mutates and what it reports, with fake mutation tools. |
| `mise run mutate` | Mutation-test the code changed since the merge base with `origin/main`, and report each mutant no test caught. `mutate:<language>` runs one language, except C and C++, which have no mutation tool yet. `check` doesn't run it, because it's slow. |
| `mise run docs` | Build the documentation site. |
| `mise run spend` | Report tokens and cost per Cursor cloud agent run over the last 7 days, from the Cursor Admin API; needs `CURSOR_ADMIN_API_KEY`. Arguments after `--` go to the script: `mise run spend -- --since 2026-09-26`. |
| `mise run check` | Run everything CI runs. |

Run `mise run check` before opening a PR; it must pass. It checks every
language the project has: Python, Rust, TypeScript, and C and C++.

## Where code lives

- `src/foundation/`: the Python package, tested in `tests/`. `quadrature.py`
  is the template's example, there to prove the checks work; delete it when
  the first real Python code arrives.
- `pyproject.toml`: Python dependencies and tool settings. `uv.lock` locks
  the dependencies, and `.python-version` pins Python.
- `crates/foundation/`: the Rust crate, tested in its `tests/`. It is the
  template's example, there to prove the checks work; delete it when the
  first real Rust crate arrives, and give that crate `#![deny(missing_docs)]`.
- `Cargo.toml`: the Rust workspace, which lists each crate. `Cargo.lock`
  locks the dependencies, `rust-toolchain.toml` pins Rust, and `deny.toml`
  holds the licence allow-list for shipped dependencies in every language.
- `packages/`: the pnpm workspace's TypeScript packages, each tested by
  `*.test.ts` files next to its source. `statistics/src/variance.ts` is the
  template's example, there to prove the checks work; delete it when the
  first real TypeScript code arrives.
- `package.json`: the TypeScript tools, locked in `pnpm-lock.yaml`. Their
  settings are in `tsconfig.json`, `biome.json`, and
  `.dependency-cruiser.cjs`, and `pnpm-workspace.yaml` lists the packages.
- `cpp/`: the C and C++ code, with public headers in `include/foundation/`,
  sources in `src/`, and tests in `tests/`. `interpolation` is the template's
  example, there to prove the checks work; delete it when the first real C or
  C++ code arrives. Give every public header a `@file` doc comment:
  `docs/build.sh` fails without one, because Doxygen would skip the header's
  undocumented symbols.
- `CMakeLists.txt`: the C and C++ build. `CMakePresets.json` configures it for
  `lint:cpp` and `test:cpp`, and `.clang-format`, `.clang-tidy`, and
  `Doxyfile` hold the tools' settings. There is no package manager yet: the
  first C or C++ dependency picks vcpkg or CMake `FetchContent`, and pins it
  as the `dependencies` rule says. With vcpkg, also add a `vcpkg` entry to
  `.github/dependabot.yml`; Dependabot can't update `FetchContent` pins.
- Module boundaries, which `mise run lint` checks. Add a project's own:
  - Python: a contract under `[tool.importlinter]` in `pyproject.toml`.
  - TypeScript: a rule under `forbidden` in `.dependency-cruiser.cjs`.
  - Rust: a `deny` entry with `wrappers` under `[bans]` in `deny.toml`.
  - C and C++: in `CMakeLists.txt`, make a target's include directories and
    links `PRIVATE` unless its public headers need them.
- `.github/scripts/`: the repository's own tooling, which people, agents, and
  CI run through `mise run`, such as `mutate.sh` and `agent_spend.py`. Each
  script is tested by the `_test` file next to it.
- `docs/`: hand-written pages. `docs/build.sh` adds the API reference,
  generated from doc comments. Sphinx and its extensions are a uv project of
  their own, `docs/pyproject.toml`, locked in `docs/uv.lock`, so that Sphinx
  doesn't depend on the Python package.
- `docs/orchestration.md`: how an orchestrator agent launches workers, limits
  cost, and hands off to a fresh orchestrator. Before you launch or message
  any other agent, read it and the `orchestrate` skill.

Each language task adds its directory and lists it here.

## Requirements

- Pin every tool at an exact version: in its language's
  `.config/mise/conf.d/<language>.toml`, or in `mise.toml` if more than one
  language, or the docs build, runs it. Don't install tools another way,
  except these:
  - Add a Python package, such as ruff or pyright, with
    `mise exec -- uv add --dev <package>`, which pins it in `uv.lock`.
  - Add a docs build tool with
    `mise exec -- uv add --project docs --dev <package>`, which pins it in
    `docs/uv.lock`.
  - Add a TypeScript package, such as typescript (tsc), Biome, or vitest,
    with `mise exec -- pnpm add -D -w --save-exact <package>`, which pins it
    in `package.json` and `pnpm-lock.yaml`.
  - The Rust toolchain is pinned in `rust-toolchain.toml`, so that Dependabot
    can update it, and mise installs it from there.
  - The C and C++ compiler comes from the OS, because mise has no maintained
    compiler toolchain. The presets name `g++`, which is GCC on Linux and
    Apple Clang on macOS, because the cloud agent image's default `c++` is a
    Clang that lacks the C++ standard library and sanitizer runtimes it
    needs.
- Don't change `.cursor/rules/` or `.cursor/skills/` unless the task is about
  them. People write those files (finding F2 in the plan).
- The PR body follows the `reviewable-prs` rule.
- Before asking a person to review a PR, fix each finding in Bugbot's review
  of the latest push (the `Cursor Bugbot` check), or reply saying why it is
  wrong. If Bugbot doesn't run, say so under "Verified".

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `.cursor/install.sh` when the machine is
  set up. It installs the pinned mise to `/usr/local/bin`, which is on every
  agent shell's PATH, then runs `mise install` and `mise run setup`. If
  `mise` or a tool is missing, rerun
  `MISE_INSTALL_PATH=/usr/local/bin/mise bash .cursor/install.sh`.
