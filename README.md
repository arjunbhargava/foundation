# foundation

A starter repository for engineers who work with Cursor agents. Agents write
most of the code and people review every change, so the template makes each
change cheap and reliable to review. It provides instructions that agents
follow, pinned tools and shared commands, example code and checks for
Python, Rust, TypeScript, and C and C++, CI, and support for agent-launched compute jobs. Status:
under construction; [`docs/template-plan.md`](docs/template-plan.md) lists
the remaining work.

## Get started with an agent

Give a Cursor agent this prompt, replacing `my-project` and `<languages>`:

> Create a new project named `my-project` from the Copier template
> `gh:arjunbhargava/foundation`, with these languages: `<languages>`. Follow
> "Get started with an agent" in
> https://github.com/arjunbhargava/foundation/blob/main/README.md: copy the
> template, run `git init`, then `bash .cursor/install.sh` and
> `mise run check`. Report anything that fails.

The agent copies the template with this command, which answers every
question, so Copier never prompts. Each language is `true` or `false`, and at
least one must be `true`:

```sh
mise exec uv@0.12.21 pipx:copier@9.18.2 -- copier copy --defaults \
  --data python=true --data rust=true --data typescript=false --data cpp=false \
  gh:arjunbhargava/foundation my-project
```

Creating and checking a project needs no secret: `.cursor/environment.json`
only runs `.cursor/install.sh`. For the agent's pull requests to merge without
a person ([auto mode](docs/auto-mode.md)), Bugbot must review the repository,
and "Allow GitHub Actions to create and approve pull requests" (Settings >
Actions > General) and "Allow auto-merge" (Settings > General) must be on.

## Get started by hand

1. **Start a project.** Run the command above, or leave out `--defaults` and
   the `--data` flags to answer one yes/no question per language: `python`,
   `rust`, `typescript`, and `cpp`. It needs [mise](https://mise.jdx.dev/) on
   your PATH.

2. **Set up a local machine and check it.** The project must be a git repository, because
   `copier update` needs one. `.cursor/install.sh` installs the pinned mise
   and tools, then runs `mise run setup`, on macOS and Linux (x86-64 or
   arm64). `mise run check` runs everything CI runs, and must pass before a
   pull request.

   ```sh
   cd my-project
   git init
   bash .cursor/install.sh
   mise run check
   ```

   C and C++ also need `g++` from the OS: on Ubuntu,
   `sudo apt-get install g++`; on macOS, the Xcode Command Line Tools.

   If the script ends by saying `~/.local/bin` isn't on your PATH, add
   `export PATH="$HOME/.local/bin:$PATH"` to your shell's startup file, such
   as `~/.zshrc`, and open a new terminal.

3. **Commit and publish.** Run `git add -A` and `git commit`, create the
   GitHub repository, and push. Then run
   [`.github/rulesets/apply.sh`](.github/rulesets/apply.sh) to apply the
   repository settings; it needs the [GitHub CLI](https://cli.github.com/),
   `gh`. Add the repository to Linear as [`docs/linear.md`](docs/linear.md)
   says.

## Learn more

- [How the repository works](docs/architecture.md)
- [Agent rules and skills](docs/agent-rules-and-skills.md)
- [Orchestrating agents](docs/orchestration.md)
- [Auto mode](docs/auto-mode.md)
- [Pulling template updates](docs/template-updates.md)
- [Commands](AGENTS.md): every `mise run <command>`, the same for people, agents, and CI
