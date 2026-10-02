---
name: add-language
description: >
  Checklist for adding a programming language to a project: a documented
  module, a test, format, lint, and type checks, the docs build, a CI job, and
  a test command for the package. Use when a project adds its first code in a
  language it doesn't have yet.
---

# Add a language

These are the steps Stage 2 of `docs/template-plan.md` takes for each core
language, as a checklist for a project that adds a language later. Tasks
T6–T9 there record the tools chosen for Python, TypeScript, Rust, and C/C++.
Everything lands in one PR: the one that adds the first code in the language.

- [ ] A small module with doc comments: the project's first real code in the
      language, or an example that exists only to prove the checks work and
      is deleted when real code arrives.
- [ ] One test, following the `testing` skill.
- [ ] Format, lint, and type checks, with warnings treated as errors.
- [ ] The language's block in `docs/build.sh` and its coverage gate,
      following the `source-docs` skill.
- [ ] Its CI job, which runs only when the language's files change, added as
      the "To add a language" comment in `.github/workflows/ci.yml` says.
- [ ] Its language in the matrix in `.github/workflows/codeql.yml`, and its
      package ecosystem in `.github/dependabot.yml`.
- [ ] A `mise` task that tests only that package.
- [ ] Its tools pinned at exact versions in `mise.toml`, and its commands
      added to the `setup`, `fmt`, `lint`, and `test` tasks there.
- [ ] Its directory listed under "Where code lives" in `AGENTS.md`.
- [ ] Its build output in `.gitignore`, its lockfile marked
      `linguist-generated` in `.gitattributes`, and its manifest and lockfile
      in the `globs` of the `dependencies` rule, if they aren't there
      already. A person makes the rule change, since people edit rules.

Every check must fail when broken. The PR shows this by breaking each check
once, for example by adding an undocumented public function, then reverting.
