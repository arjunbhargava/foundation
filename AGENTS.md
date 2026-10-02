# Agent instructions

## Commands

`mise.toml` defines every command, so people, agents, and CI run the same
thing:

| Command | What it does |
|---|---|
| `mise run setup` | Install project dependencies. |
| `mise run fmt` | Format all code in place. |
| `mise run lint` | Check formatting, lint, and types without changing files. |
| `mise run lint:python` | Run only the Python checks. |
| `mise run lint:rust` | Run only the Rust checks, including cargo-deny's advisory and licence checks. |
| `mise run test` | Run all tests. |
| `mise run test:python` | Run only the Python tests and docstring examples. Arguments after `--` go to pytest: `mise run test:python -- -k trapezoid`. |
| `mise run test:rust` | Run only the Rust tests and doc-comment examples. Arguments after `--` go to `cargo test`: `mise run test:rust -- energy`. |
| `mise run docs` | Build the documentation site. |
| `mise run check` | Run everything CI runs. |

Run `mise run check` before opening a PR; it must pass. Python and Rust are
the only languages so far; the other language tasks in
`docs/template-plan.md` add theirs.

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
- `docs/`: hand-written pages. `docs/build.sh` adds the API reference,
  generated from doc comments.

Each language task adds its directory and lists it here.

## Requirements

- Pin every tool in `mise.toml`, at an exact version. Don't install tools
  another way. Python packages, including ruff and pyright, are the
  exception: add them with `mise exec -- uv add --dev <package>`, which pins
  them in `uv.lock`. The Rust toolchain is the other: `rust-toolchain.toml`
  pins it, so that Dependabot can update it, and mise installs it from there.
- Don't change `.cursor/rules/` or `.cursor/skills/` unless the task is about
  them. People write those files (finding F2 in the plan).
- The PR body follows the `reviewable-prs` rule.
- Before asking a person to review a PR, fix each finding in Bugbot's review
  of the latest push (the `Cursor Bugbot` check), or reply saying why it is
  wrong. If Bugbot doesn't run, say so under "What was not verified".

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `.cursor/install.sh` when the machine is
  set up. It installs the pinned mise to `/usr/local/bin`, which is on every
  agent shell's PATH, then runs `mise install` and `mise run setup`. If
  `mise` or a tool is missing, rerun
  `MISE_INSTALL_PATH=/usr/local/bin/mise bash .cursor/install.sh`.
