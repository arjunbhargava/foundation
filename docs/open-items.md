# Open items

The decisions and manual steps that only a person can do, and the known gaps
in the code and docs, kept here so that no one has to remember them. Every
pull request keeps this page current: it adds each follow-up it lists and
deletes each item it resolves, as `.cursor/skills/open-items/SKILL.md` says.
Git history keeps deleted items. `mise run lint:open-items` checks the
[format](#format).

The template's own items are in `docs/template-open-items.md`, which projects
made from the template don't get, so each project's page starts empty.

```{include} template-open-items.md
```

## Format

"Needs a person" holds decisions and manual steps that only a person can do.
"Technical debt" holds known gaps, follow-ups, and stale text. Each item is
one line with these fields, in this order:

- **Id**: `OI-<n>`. The page gives the next id; the PR that adds an item uses
  it and raises it by one, so an id is never reused.
- **What**: what the item is, in one sentence.
- **Why**: why it matters: what goes wrong, or stays blocked, until it is
  done.
- **Action**: what a person does or decides, with a link where one exists.
- **Added in**: the pull request that added the item, as `[#<number>](<URL>)`.
- **Last confirmed**: the date, as YYYY-MM-DD, on which someone last checked
  that the item still holds and its text is still accurate. Each week,
  `.github/workflows/open-items.yml` lists the items not confirmed in 30 days
  in an issue titled "Open items not confirmed in 30 days".

For example:

```text
- **OI-12** Turn on GitHub Pages. **Why:** the docs site doesn't publish until it is on. **Action:** in Settings > Pages, set Source to GitHub Actions. **Added in:** [#34](https://github.com/arjunbhargava/foundation/pull/34). **Last confirmed:** 2026-10-16.
```
