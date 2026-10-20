# Agent instructions

## Commands

`mise.toml` defines the shared commands, and each language's file in
`.config/mise/conf.d/` defines that language's, so people, agents, and CI run
the same thing:

| Command | What it does |
|---|---|
| `mise run setup` | Install project dependencies. |
| `mise run setup-status` | Report which of README.md's manual setup steps are `done`, `not done`, or `can't check`, with a link for each, using `gh` and its API; always exits 0 and prints no secret. Arguments after `--` go to the script: `mise run setup-status -- owner/repo`. |
| `mise run fmt` | Format all code in place. `fmt:<language>` formats one language. |
| `mise run lint` | Check formatting, lint, and types without changing files. |
| `mise run lint:python` | Run only the Python checks. |
| `mise run lint:rust` | Run only the Rust checks, including cargo-deny's advisory, ban, licence, and source checks. |
| `mise run lint:typescript` | Run only the TypeScript checks. |
| `mise run lint:cpp` | Run only the C and C++ checks: clang-format, a check that no `#include` uses `../`, and a build with clang-tidy and compiler warnings as errors. |
| `mise run lint:rulesets` | Check that the ruleset files in `.github/rulesets/` are valid JSON, that none requires up-to-date branches, and that the two review rulesets differ only in name, thread resolution, and auto mode's owned-paths and needs-human-review checks. |
| `mise run lint:workflows` | Run only the GitHub Actions workflow checks: actionlint, and zizmor's offline security audits. A finding in a workflow is suppressed with a `# zizmor: ignore[<audit>]` comment. |
| `mise run lint:language-listings` | Check that each place that must list every language, such as the CI jobs and this table, lists each language in `.config/mise/conf.d/`, and name each place that lacks one. |
| `mise run test` | Run all tests. |
| `mise run test:python` | Run only the Python tests and docstring examples. Arguments after `--` go to pytest: `mise run test:python -- -k trapezoid`. |
| `mise run test:rust` | Run only the Rust tests and doc-comment examples. Arguments after `--` go to `cargo test`: `mise run test:rust -- energy`. |
| `mise run test:typescript` | Run only the TypeScript tests. Arguments after `--` go to vitest: `mise run test:typescript -- -t precision`. |
| `mise run test:cpp` | Build the C and C++ tests with AddressSanitizer and UndefinedBehaviorSanitizer, and run them. Arguments after `--` go to ctest: `mise run test:cpp -- -R chord`. |
| `mise run test:lint-workflows-script` | Check that `.github/scripts/lint_workflows.sh` fails on a finding from either actionlint or zizmor, and runs both. |
| `mise run test:ci-changes-script` | Check which CI jobs `.github/scripts/ci_changes.sh` starts for each kind of changed file, in a scratch git repository. |
| `mise run test:language-listings-script` | Check that `lint:language-listings` passes for the repository, and names each place that lacks a new language, on copies of the files it reads. |
| `mise run test:rulesets` | Check the changes `.github/rulesets/apply.sh` makes with and without `--auto`, and that `lint:rulesets` catches broken ruleset files, with a fake `gh`. |
| `mise run test:auto-merge-script` | Check when `.github/scripts/auto_merge.sh` turns auto-merge on and off, and which PRs it leaves alone, with a fake `gh`. |
| `mise run test:approve-agent-prs-script` | Check which PRs `.github/scripts/approve_agent_prs.sh` approves, in auto mode and review mode, with a fake `gh`. |
| `mise run test:needs-human-review-script` | Check that `.github/scripts/needs_human_review.sh` fails a PR with the `needs-human-review` label and passes one without. |
| `mise run test:owned-paths-script` | Check which changed paths `.github/scripts/owned_paths.sh` finds in `.github/CODEOWNERS`, and when it can't tell, with a fake `gh`. |
| `mise run test:linear-queue-script` | Check which Linear issues `.github/scripts/linear_queue.sh` lists as dispatchable, that its `create` makes one issue per title, and that it never prints the API key, with a fake `curl`. |
| `mise run test:mutate-script` | Check which files `.github/scripts/mutate.sh` mutates and what it reports, with fake mutation tools. |
| `mise run mutate` | Mutation-test the code changed since the merge base with `origin/main`, and report each mutant no test caught, or pass with one line saying that no changed file holds mutable code. `mutate:<language>` runs one language, except C and C++, which have no mutation tool yet. Only the template repository, which alone has `copier.yml`, also mutates the changed `.github/scripts/*.py`, and no tool mutates the shell scripts there. `check` doesn't run it, because it's slow. |
| `mise run docs` | Build the documentation site. |
| `mise run test:docs` | Check that `docs/conf.py` points the links in `README.md` and `AGENTS.md` at the site's pages, turns those to other repository paths into text, and still fails on a path that is missing or outside the repository, by building a small site. |
| `mise run spend` | Report tokens and cost per Cursor cloud agent run over the last 7 days, from the Cursor Admin API, with each run's task, repository, and branch and a subtotal per repository; needs `CURSOR_ADMIN_API_KEY`, and `CURSOR_API_KEY` for the labels. Arguments after `--` go to the script: `mise run spend -- --since 2026-09-26`. |
| `mise run check` | Run everything CI runs. |

Run `mise run check` before opening a PR; it must pass. It checks every
language the project has: Python, Rust, TypeScript, and C and C++.

## Where code lives

- `src/foundation/`: the Python package, tested in `tests/`. `quadrature.py`
  is the template's example, there to prove the checks work. To delete it,
  delete `src/foundation/quadrature.py` and `tests/test_quadrature.py`, and
  keep `src/foundation/__init__.py`, which `docs/api/python.md` and
  `[tool.importlinter]` in `pyproject.toml` name. `mise run check` and
  `mise run mutate` pass with a package that holds only docstrings.
- `pyproject.toml`: Python dependencies and tool settings. `uv.lock` locks
  the dependencies, and `.python-version` pins Python.
- `conftest.py`: adds the `src/` and `tests/` of each uv workspace member to
  the paths pytest runs when it is given none.
- More than one Python distribution: list each as a member in
  `[tool.uv.workspace]` in `pyproject.toml`, and give it a `pyproject.toml`,
  `src/<package>/`, and `tests/` of its own, as the root has. One `uv.lock`
  and one `.venv` then cover all of them, and the tests, `docs/build.sh`,
  `docs/conf.py`, and `mise run mutate` take their list of distributions from
  the members, and `mutate` reports each separately; a member without a
  `src/` is skipped. A new member also needs
  its package added by hand to the toctree in `docs/api/python.md` and to
  `[tool.importlinter]`, and, if it has a `lib/` directory, `source_paths =
  ["src"]` under `[tool.mutmut]` in its own `pyproject.toml`, because mutmut
  would mutate `lib/`. pytest imports test files by path, so two members may
  have a test file of the same name, and a test can't import a helper beside
  it by name.
- `crates/foundation/`: the Rust crate, tested in its `tests/`. It is the
  template's example, there to prove the checks work. To delete its code,
  delete `src/verlet.rs`, `tests/verlet.rs`, and the `pub mod verlet;` line
  in `src/lib.rs`, and keep the crate, which `Cargo.toml`, `Cargo.lock`, and
  `docs/api/rust.md` name: without it the docs build fails. Give every new
  crate `#![deny(missing_docs)]`.
- `Cargo.toml`: the Rust workspace, which lists each crate. `Cargo.lock`
  locks the dependencies, `rust-toolchain.toml` pins Rust, and `deny.toml`
  holds the licence allow-list for shipped dependencies in every language.
- `packages/`: the pnpm workspace's TypeScript packages, each tested by
  `*.test.ts` files next to its source. `statistics/src/variance.ts` is the
  template's example, there to prove the checks work. Replace it instead of
  deleting it: `docs/build.sh` runs TypeDoc on that file, and vitest fails
  when no `*.test.ts` file exists. Put the project's first documented export
  in `variance.ts` and its test in `variance.test.ts`; to rename them, also
  change the path in `docs/build.sh`.
- `package.json`: the TypeScript tools, locked in `pnpm-lock.yaml`. Their
  settings are in `tsconfig.json`, `biome.json`, and
  `.dependency-cruiser.cjs`, and `pnpm-workspace.yaml` lists the packages.
- `cpp/`: the C and C++ code, with public headers in `include/foundation/`,
  sources in `src/`, and tests in `tests/`. `interpolation` is the template's
  example, there to prove the checks work. Replace it instead of deleting it:
  `CMakeLists.txt` names `src/interpolation.cpp` and
  `tests/interpolation_test.cpp`, and `Doxyfile` reads `cpp/include`, which
  must hold a header. Put the project's first code in the three
  `interpolation` files and its test in the test file; to rename them, also
  change `add_library`, `add_executable`, and `add_test` in
  `CMakeLists.txt`. Give every public header a `@file` doc comment:
  `docs/build.sh` fails without one, because Doxygen would skip the header's
  undocumented symbols.
- `CMakeLists.txt`: the C and C++ build. `CMakePresets.json` configures it for
  `lint:cpp` and `test:cpp`, and `.clang-format`, `.clang-tidy`, and
  `Doxyfile` hold the tools' settings. There is no package manager yet: the
  first C or C++ dependency picks vcpkg or CMake `FetchContent`, and pins it
  as the `dependencies` rule says. With vcpkg, also add a `vcpkg` entry to
  `.github/dependabot.yml`; Dependabot can't update `FetchContent` pins.
- Module boundaries, which `mise run lint` checks. Add a project's own boundaries:
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
- On a project's first task, or when asked, run `mise run setup-status`
  before you rely on auto mode, Pages, or Bugbot, and tell the person each
  step it prints as `not done` or `can't check`, with its link.
- Don't change `.cursor/rules/` or `.cursor/skills/` unless the task is about
  them. People write those files (finding F2 in the plan).
- The PR body follows the `reviewable-prs` rule.
- Open each PR ready for review, not as a draft, whatever a tool's default
  is: for example, pass `draft: false` to `ManagePullRequest`. In auto mode a
  draft doesn't merge, and the owner would have to mark it ready by hand.
  Auto-merge still waits for Bugbot's review of the latest push and for every
  review thread to be resolved (`docs/auto-mode.md`).
- File a problem outside your issue with `.github/scripts/linear_queue.sh
  create`, as the `linear-queue` skill says, instead of fixing it.
- Before asking a person to review a PR, fix each finding in Bugbot's review
  of the latest push (the `Cursor Bugbot` check), or reply saying why it is
  wrong. If Bugbot doesn't run, say so under "Verified".
- Add the `needs-human-review` label to your PR when a person asks to
  review it, in a Linear issue, in Cursor, or in chat, and pass the request
  on to any agent you launch for that work. Also add it whenever the PR body
  lists anything under "Needs a person", such as a change to the safety
  boundary (a path in `.github/CODEOWNERS`, a ruleset, a permission, how
  secrets are read, or how spend is limited), spend above budget, or a
  dependency whose licence isn't on the allow-list: auto mode doesn't read
  the PR body, so the label is what holds the PR. An important feature or
  an architectural decision is yours to make: record it under "What and
  why", and a person can reverse it later. This is the one label you may add
  without being asked, whatever a tool's description says. Don't remove it; the
  owner does. `docs/auto-mode.md` says what it does.

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `.cursor/install.sh` when the machine is
  set up. It installs the pinned mise to `/usr/local/bin`, which is on every
  agent shell's PATH, then runs `mise install` and `mise run setup`. If
  `mise` or a tool is missing, rerun
  `MISE_INSTALL_PATH=/usr/local/bin/mise bash .cursor/install.sh`.
