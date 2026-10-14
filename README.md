# foundation

A starter repository for engineers who work with Cursor agents. Agents write
most of the code and people review every change, so the template makes each
change cheap and reliable to review. It provides instructions that agents
follow, pinned tools and shared commands, example code and checks for
Python, Rust, TypeScript, and C and C++, CI, and support for agent-launched compute jobs. Status:
under construction; [`docs/template-plan.md`](docs/template-plan.md) lists
the remaining work.

## Get started

1. **Start a project from the template.** With [mise](https://mise.jdx.dev/)
   on your PATH, run this, with the uv and copier versions that `mise.toml`
   pins:

   ```sh
   mise exec uv@0.12.21 pipx:copier@9.18.2 -- copier copy gh:arjunbhargava/foundation my-project
   ```

   [Copier](https://copier.readthedocs.io/) asks one yes/no question per
   language: `python`, `rust`, `typescript`, and `cpp`. The project gets the
   files of each language you answer yes to, and Copier refuses to create one
   with none. To answer without prompts, pass `--defaults` and a `--data`
   option per language, such as `--data python=true`.

2. **Set up a local machine.** Make the project a git repository, because
   `copier update` needs one. The setup script installs the pinned mise to
   `~/.local/bin` without sudo and the tools it pins, then runs
   `mise run setup`. It supports macOS and Linux on x86-64 or arm64.

   ```sh
   cd my-project
   git init
   bash .cursor/install.sh
   ```

   C and C++ also need `g++` from the OS: on Ubuntu,
   `sudo apt-get install g++`; on macOS, the Xcode Command Line Tools, which
   git already needs.

   If the script ends by saying `~/.local/bin` isn't on your PATH, add
   `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc` for zsh,
   `~/.bashrc` for bash on Linux, or `~/.bash_profile` for bash on macOS,
   then open a new terminal.

3. **Run the checks.** This runs everything CI runs, and must pass before you
   open a pull request:

   ```sh
   mise run check
   ```

4. **Commit and publish.** Commit the project:

   ```sh
   git add -A
   git commit -m "Create the project from the foundation template"
   ```

   Then create its GitHub repository and push. Run
   [`.github/rulesets/apply.sh`](.github/rulesets/apply.sh) to apply the
   repository settings; it needs the [GitHub CLI](https://cli.github.com/),
   `gh`, which the setup script doesn't install. Add the repository to Linear
   as [`docs/linear.md`](docs/linear.md) says.

## Commands

Every command is `mise run <command>`, so people, agents, and CI run the same
tools at the same versions. [`AGENTS.md`](AGENTS.md) has the table of
commands.

## Learn more

- [How the repository works](docs/architecture.md)
- [Agent rules and skills](docs/agent-rules-and-skills.md)
- [Orchestrating agents](docs/orchestration.md)
- [Auto mode](docs/auto-mode.md)
- [Pulling template updates](docs/template-updates.md)
