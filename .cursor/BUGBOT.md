# Review instructions for Bugbot

You review every PR in this repository before a person does. Agents write most
of the code here. Agent PRs that pass their tests are still often not
mergeable, for three reasons: they don't really fix the problem, they break
other code, or the code is poor (finding F3 in `docs/template-plan.md`). Look
for those first. Don't report what CI checks: formatting, lint, types, the docs
build, and failing tests.

These files set the standard. Bugbot doesn't load `.cursor/rules/` on its own,
so each file is linked here:

- [AGENTS.md](../AGENTS.md)
- [.cursor/rules/clarity.mdc](rules/clarity.mdc)
- [.cursor/rules/docs-from-source.mdc](rules/docs-from-source.mdc)
- [.cursor/rules/ponytail.mdc](rules/ponytail.mdc)
- [.cursor/rules/reviewable-prs.mdc](rules/reviewable-prs.mdc)
- [.github/pull_request_template.md](../.github/pull_request_template.md)

In each finding, name the acceptance criterion, or the file and rule, that the
PR breaks.

## Does it fix the problem?

- Take the acceptance criteria from the PR body, and from the linked issue
  when you can read it. If the PR drops or weakens a criterion from the issue,
  flag it unless "Changes from the plan" explains why.
- Check that the diff meets each criterion as it will be merged. Work the PR
  promises for later doesn't count. If the PR states no criteria, say so, and
  check the diff against what "What changes and why" claims.
- A bug fix removes the root cause in the shared code, not only the symptom
  on the path the report names (`ponytail.mdc`).

## Does it break other code?

- Find every caller, import, config file, doc, and diagram that depends on a
  changed name, signature, data format, or behaviour, including those outside
  the diff, and check that each still works.

## Do the tests prove it?

- Each acceptance criterion has a named test, listed under "How it was
  verified", that asserts concrete expected behaviour: given these inputs,
  this output or error (finding F4).
- Flag a test that would still pass with the change reverted, or that only
  checks the code runs without error.

## Is the code good?

- Judge it by `clarity.mdc`, `ponytail.mdc`, and `docs-from-source.mdc`.

## Can a person review it in one sitting?

Check against `reviewable-prs.mdc` and the PR template:

- One logical change within the line budget, or an `Oversize:` first line
  whose category and reason the rule allows.
- No refactor mixed with a behaviour change, and no drive-by edits. Problems
  outside the task are reported as issues, not fixed in the PR.
- The body has every section of the template, in order.
- The Diagrams section matches the diff: a change to components, data flow,
  state, or external dependencies updates `docs/architecture.md`.

## Keeping this file current

A PR that adds, renames, or removes a file in `.cursor/rules/`, or moves a
requirement out of a file linked above, updates these links in the same PR.
