# foundation

A project in Python, Rust, TypeScript, and C and C++, created from the
[foundation](https://github.com/arjunbhargava/foundation) template. Replace
this sentence with what the project does.

## Set up a local machine

Run `bash .cursor/install.sh` from the project's root. It installs the
pinned mise to `~/.local/bin`, unless that version is already installed, then
the tools `mise.toml` pins, and runs `mise run setup`. It doesn't edit shell
files: if `mise` isn't on PATH, it ends by printing the `export PATH=` line to
add to your shell's startup file.

C and C++ also need `g++` from the OS: on Ubuntu,
`sudo apt-get install g++`; on macOS, the Xcode Command Line Tools.

- **Cursor cloud agent:** automatic. `.cursor/environment.json` runs the
  script with `MISE_INSTALL_PATH=/usr/local/bin/mise`, which is on PATH.
- **Dev container, other CI, or a VM:** run the same command on glibc
  Linux or macOS; [what it doesn't cover](docs/install-script.md).

## Commands

[`AGENTS.md`](AGENTS.md) lists every `mise run <command>`, the same for
people, agents, and CI. The ones used most:

- `mise run check`: everything CI runs; it must pass before a pull request.
- `mise run fmt`: format all code in place.
- `mise run test`: run all tests.
- `mise run docs`: build the documentation site.

## Pull template updates

In a project with no uncommitted changes, run
`mise exec -- copier update --defaults --trust`, resolve any conflicts it
marks, and run `mise run check`. [Pulling template updates](docs/template-updates.md)
has the details.

## Learn more

- [How the repository works](docs/architecture.md)
- [Agent rules and skills](docs/agent-rules-and-skills.md)
- [Orchestrating agents](docs/orchestration.md)
- [Auto mode](docs/auto-mode.md)
