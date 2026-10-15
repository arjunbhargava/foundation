# Project name

A project in Python, Rust, TypeScript, and C and C++, created from the
[foundation](https://github.com/arjunbhargava/foundation) template. Replace
this title with the project's name, and this sentence with what it does.

## Finish setup: manual steps

GitHub copies no repository settings, and Cursor and Linear need setup of
their own. Until these steps are done, auto mode, the documentation site, and
Bugbot's review don't work. Replace `OWNER/REPO` in each link with this
repository's name, or run `mise run setup:status`, which prints each step as
`done`, `not done`, or `can't check`, with its link.

1. **Let Actions approve pull requests.**
   [Settings > Actions > General](https://github.com/OWNER/REPO/settings/actions):
   turn on "Allow GitHub Actions to create and approve pull requests".
   Unlocks: [auto mode](docs/auto-mode.md)'s approvals. Who: a repository
   admin; an organization owner first, if the organization's setting is off.
2. **Allow auto-merge** in
   [Settings > General](https://github.com/OWNER/REPO/settings). Unlocks: the
   auto-merge workflow. Who: a repository admin.
3. **Publish the documentation site.**
   [Settings > Pages](https://github.com/OWNER/REPO/settings/pages): set
   Source to GitHub Actions. Unlocks: the deploy job of `docs-site.yml`. Who:
   a repository admin; a private repository needs a paid GitHub plan.
4. **Apply the rulesets.** With `gh` logged in as a repository admin, run
   `mise exec -- .github/rulesets/apply.sh` for review mode, where a person
   approves every pull request, or add `--auto` for auto mode. It also allows
   only merge commits and turns on secret scanning. Unlocks: required checks
   and review on `main`. Who: a repository admin; private ones need a paid plan.
5. **Turn on Bugbot** in the
   [Cursor dashboard](https://www.cursor.com/dashboard/bugbot). Unlocks: the
   review that auto mode waits for. Who: a Cursor team admin, or the account
   owner.
6. **Give the Cursor GitHub app access** to this repository in
   [Installed GitHub apps](https://github.com/settings/installations), if it
   has access only to selected repositories. Unlocks: cloud agents that push
   and open pull requests. Who: the account owner, or an organization owner.
7. **Set `CURSOR_ADMIN_API_KEY` and `CURSOR_API_KEY`** (see `.env.example`)
   as Cursor cloud agent secrets in the
   [Cursor dashboard](https://www.cursor.com/dashboard), and in `.env`
   locally. Unlocks: `mise run spend`. Who: the Cursor account's manager; a
   team admin for the first. No workflow reads a GitHub Actions secret yet.
8. **Set up Linear** as [`docs/linear.md`](docs/linear.md) says. Unlocks:
   issues that agents turn into pull requests. Who: a Linear workspace admin.
9. **Optional: schedule `prune-review`** with a
   [Cursor automation](https://cursor.com/automations), as the
   [skill](.cursor/skills/prune-review/SKILL.md) says. Unlocks: regular
   removal of dead code. Who: a Cursor user; a team admin for a service
   account.

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
`mise exec -- copier update --defaults`, resolve any conflicts it marks, and
run `mise run check`. [Pulling template updates](docs/template-updates.md)
has the details.

## Learn more

- [How the repository works](docs/architecture.md)
- [Agent rules and skills](docs/agent-rules-and-skills.md)
- [Orchestrating agents](docs/orchestration.md)
- [Auto mode](docs/auto-mode.md)
