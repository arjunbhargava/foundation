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
| `mise run lint:cpp` | Run only the C and C++ checks: clang-format, and a build with clang-tidy and compiler warnings as errors. |
| `mise run test` | Run all tests. |
| `mise run test:python` | Run only the Python tests and docstring examples. Arguments after `--` go to pytest: `mise run test:python -- -k trapezoid`. |
| `mise run test:cpp` | Build the C and C++ tests with AddressSanitizer and UndefinedBehaviorSanitizer, and run them. Arguments after `--` go to ctest: `mise run test:cpp -- -R chord`. |
| `mise run docs` | Build the documentation site. |
| `mise run check` | Run everything CI runs. |

Run `mise run check` before opening a PR; it must pass. Python and C++ are
the only languages so far; the other language tasks in
`docs/template-plan.md` add theirs.

## Where code lives

- `src/foundation/`: the Python package, tested in `tests/`. `quadrature.py`
  is the template's example, there to prove the checks work; delete it when
  the first real Python code arrives.
- `pyproject.toml`: Python dependencies and tool settings. `uv.lock` locks
  the dependencies, and `.python-version` pins Python.
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
- `docs/`: hand-written pages. `docs/build.sh` adds the API reference,
  generated from doc comments.

Each language task adds its directory and lists it here.

## Requirements

- Pin every tool in `mise.toml`, at an exact version. Don't install tools
  another way. Python packages, including ruff and pyright, are the
  exception: add them with `mise exec -- uv add --dev <package>`, which pins
  them in `uv.lock`. The C and C++ compiler is another: it comes from the OS,
  because mise has no maintained compiler toolchain. The presets name `g++`,
  which is GCC on Linux and Apple Clang on macOS, because the cloud agent
  image's default `c++` is a Clang that lacks the C++ standard library and
  sanitizer runtimes it needs.
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
