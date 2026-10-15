# foundation

A starter repository for engineers who work with Cursor agents. Agents write
most of the code and people review every change, so the template makes each
change cheap and reliable to review. It provides instructions that agents
follow, pinned tools and shared commands, example code and checks for
Python, Rust, TypeScript, and C and C++, CI, and support for agent-launched
compute jobs. Most of it is built; [the plan](../docs/template-plan.md) lists
what remains: T16 (compute job support), T17 (Linear setup), T19 (measuring
the instructions), T22 (collecting follow-ups, which waits for T17), and
T23's PR 4 (the branch-update workflow).

This file is the template's README, and GitHub shows it in place of the
root `README.md`. `_exclude` in [`copier.yml`](../copier.yml) leaves it out of
a project, with the other files that only describe the template, such as
`docs/template-plan.md`. The root `README.md` is the project's own, rendered
from [`README.md.jinja`](../README.md.jinja).

## Get started with an agent

Give a Cursor agent this prompt, replacing `<folder>` with a new folder's
name, or with `.` to use the repository the agent is working in, and
`<languages>`:

> Create a project in `<folder>` from the Copier template
> `gh:arjunbhargava/foundation`, with these languages: `<languages>`. Follow
> "Get started by hand" in
> https://github.com/arjunbhargava/foundation/blob/main/.github/README.md,
> in order: install the pinned mise first, add `--overwrite` to the copy if
> the folder already has files such as a README.md, skip `git init` if the
> folder is already a repository, then run `mise run check`. Report anything
> that fails.

## Get started by hand

1. **Install the pinned mise.** The copy in step 2 runs through mise, but the
   script that installs mise, `.cursor/install.sh`, is one of the files the
   copy creates. So run the template's copy of the script, which is the one
   place the mise version is pinned. The temporary folder has no `mise.toml`,
   so it installs mise and no other tool; setting `MISE_ENABLE_TOOLS` makes it
   skip `mise run setup`, which would fail there, and its value is
   immaterial. A later run of `.cursor/install.sh` in the project finds this
   mise and downloads nothing.

   ```sh
   bootstrap=$(mktemp -d)
   mkdir "$bootstrap/.cursor"
   curl -fsSL -o "$bootstrap/.cursor/install.sh" \
     https://raw.githubusercontent.com/arjunbhargava/foundation/main/.cursor/install.sh
   MISE_ENABLE_TOOLS=uv,pipx:copier bash "$bootstrap/.cursor/install.sh"
   rm -rf "$bootstrap"
   ```

   If it ends by printing an `export PATH=` line, run that line, because
   `mise` isn't on PATH yet. The script doesn't edit shell files.

2. **Copy the template.** This command answers every question, so Copier
   never prompts. Each language is `true` or `false`, and at least one must be
   `true`. Or leave out `--defaults` and the `--data` flags to answer
   one yes/no question per language: `python`, `rust`, `typescript`, and `cpp`.

   ```sh
   mise exec uv@0.12.21 pipx:copier@9.18.2 -- copier copy --defaults \
     --data python=true --data rust=true --data typescript=false --data cpp=false \
     gh:arjunbhargava/foundation my-project
   ```

   **In an existing repository**, run the command from its root, give `.`
   in place of `my-project`, and add `--overwrite` after `--defaults`. Without
   it, Copier stops at the first file the template also has, such as
   `README.md`, with "Interactive session required", after writing part of
   the project and without `.copier-answers.yml`. With it, each such file is
   replaced by the template's, and `README.md` becomes the project's
   [README](../README.md.jinja). Keep the old README's text by committing it
   first, or copying it elsewhere.

3. **Set up, check, and commit.** Skip `git init` if the folder already is a
   repository, because `copier update` needs one.

   ```sh
   cd my-project  # skip in an existing repository
   [ -e .git ] || git init
   bash .cursor/install.sh
   mise run check  # everything CI runs; must pass before a pull request
   git add -A && git commit -m "Create the project from the foundation template"
   ```

4. **Open the first pull request with an oversize description.** The
   commit holds the whole template, far over the 500 changed lines that the
   [`pr-size`](workflows/pr-size.yml) check allows, so the check fails unless
   the PR description starts with `Oversize:`. It looks at the start of the
   description only, after any whitespace and HTML comments, so Cursor's
   comment at the top of an agent's description is fine. Start the first
   line with the category and the reason, as the
   [`large-changes` skill](../.cursor/skills/large-changes/SKILL.md) asks,
   and say what to read closely:

   ```text
   Oversize: Mechanical — the first commit is the unedited output of
   `<the copier copy command>`, so it can't be split without a state that has
   no checks. Skim commit 1; read closely the commits after it.
   ```

   Files that `.gitattributes` marks `linguist-generated`, such as lockfiles,
   don't count toward the 500.

5. **Set what a copy can't.** GitHub doesn't copy repository settings, so
   after creating the repository and pushing:

   - Settings > Pages > Build and deployment > Source: **GitHub Actions**.
     Until then the deploy job of `docs-site.yml` fails.
   - Settings > Actions > General: turn on "Allow GitHub Actions to create
     and approve pull requests".
   - Settings > General: turn on "Allow auto-merge".
   - Rulesets: run `mise exec -- .github/rulesets/apply.sh` (needs `gh`
     logged in as an admin) for review mode, where a person approves every
     PR, or add `--auto` for [auto mode](../docs/auto-mode.md). Rerun it
     without `--auto` to leave auto mode.
   - Turn Bugbot on for the repository in the
     [Cursor dashboard](https://www.cursor.com/dashboard/bugbot). Auto mode
     waits for its review.
   - Give the Cursor GitHub app access to the repository, if the app has
     access only to selected repositories, so that cloud agents can push to it
     and open PRs.

   Then add the repository to Linear as [`docs/linear.md`](../docs/linear.md)
   says.

Creating and checking a project needs no secret.

## Learn more

- [How the repository works](../docs/architecture.md)
- [Agent rules and skills](../docs/agent-rules-and-skills.md)
- [Orchestrating agents](../docs/orchestration.md)
- [Auto mode](../docs/auto-mode.md)
- [Pulling template updates](../docs/template-updates.md)
- [Commands](../AGENTS.md): every `mise run <command>`, the same for people, agents, and CI
