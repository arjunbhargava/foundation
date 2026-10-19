---
name: plan
description: >
  Write a short plan covering the problem, the interface, the files touched,
  and the acceptance criteria, then proceed, stopping for a person's approval
  only when the change is hard to reverse. Use when a change meets decision
  D7 in `docs/template-plan.md`, before writing its code: a new module, a
  change to a public interface or data format, or a new dependency.
---

# Plan

Some changes need a written plan before any code: those that meet decision
D7 in `docs/template-plan.md`. Check a task against D7 before starting, and
again if the work grows, for example when it turns out to need a new module.
Below the threshold, write no plan. Planning pays off only for larger
changes, and a bad plan is worse than none (finding F5).

D7's last trigger, compute spend above the cost limit, is handled when a job
is launched rather than before coding: the `compute-cost` rule says when to
ask, with an estimate, in the PR.

## Write the plan

Use these headings, and keep each to a few lines:

- **Problem**: what is wrong or missing, and why it matters. Link the issue.
- **Interface**: what callers will see: public functions and types, data
  formats, and commands, with units, valid ranges, and errors. For a new
  dependency, give its name, its licence, and why nothing already installed
  covers it.
- **Files touched**: each file to be created or changed, with one line on
  what changes in it.
- **Acceptance criteria**: behaviour someone can check. Each becomes a named
  test (`testing` skill).
- **Open questions**: anything you would otherwise have to guess; omit if none.

If the work needs more than one PR, say so; the `decompose` skill splits the
plan into sub-issues.

## Post it, then proceed

Post the plan on the Linear issue the task came from, or in the PR body.
Don't commit it to the repository; plans live in Linear, not in shared files
(finding F7). Then write the code. A person can still comment on the plan or
reverse it later.

Stop and write no code until a person approves the plan only when the change
is hard to reverse: it changes a data format that existing users depend on,
changes a published interface, adds a shipped dependency whose licence isn't
clearly on the allow-list, or spends compute (`compute-cost` rule). If they
ask for changes, revise it and stop again.

The PR notes, in one line, any difference from the plan that matters
(`reviewable-prs`). A new dependency the plan doesn't name doesn't stop the
work; the PR marks it "(not in the plan)".
