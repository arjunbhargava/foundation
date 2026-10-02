---
name: spec
description: >
  Write a short plan covering the problem, the interface, the files touched,
  and the acceptance criteria, then stop until a person approves it. Use
  before writing code for a change that meets decision D7 in
  `docs/template-plan.md`: a new module, a change to a public interface or
  data format, a new dependency, or compute spend above the cost limit.
---

# Spec

Some changes need a plan that a person approves before any code is written:
those that meet decision D7 in `docs/template-plan.md`, where decision D8 sets
the cost limit. Check a task against D7 before starting, and again if the work
grows, for example when it turns out to need a new dependency. Below the
threshold, write no plan. Planning pays off only for larger changes, and a bad
plan is worse than none (finding F5).

## Write the plan

Use these headings, and keep each to a few lines:

- **Problem**: what is wrong or missing, and why it matters. Link the issue.
- **Interface**: what callers will see: public functions and types, data
  formats, and commands, with units, valid ranges, and errors. For a new
  dependency, name it and say why nothing already installed covers it.
- **Files touched**: each file to be created or changed, with one line on
  what changes in it.
- **Acceptance criteria**: behaviour someone can check. Each becomes a named
  test (`testing` skill).
- **Open questions**: anything you would otherwise have to guess, or None.

A plan needed because of compute spend also gives the estimated cost and how
it was estimated. If the work needs more than one PR, say so; once the plan is
approved, the `decompose` skill splits it into sub-issues.

## Stop for approval

Post the plan where the person who approves it will read it: on the Linear
issue the task came from, or in reply to whoever asked for it. Don't commit it
to the repository; plans live in Linear, not in shared files (finding F7).

Then stop. Write no code until a person approves the plan. If they ask for
changes, revise it and stop again. The PR's "Changes from the plan" section
later reports how the work differs from the approved plan.
