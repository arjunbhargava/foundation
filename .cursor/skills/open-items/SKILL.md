---
name: open-items
description: >
  Keep docs/open-items.md, the list of what a person must do or decide and of
  known technical debt, current in every PR: add each follow-up and each
  decision the PR leaves to a person, delete each item it resolves, and
  number and date items. Use in every PR, and when asked what is open.
---

# Open items

`docs/open-items.md` is the one list of open items that people read,
usually on a phone, so that nothing depends on an agent's memory or a chat.
The page defines each field. In the template repository, its own items are in
`docs/template-open-items.md`, which the page includes; edit that file there.

## In every PR

- **Add** an item for each line the PR body lists under "Follow-ups" or
  "Needs a person", in the same PR. A decision or manual step only a person
  can do goes under "Needs a person"; a known gap, follow-up, or stale text
  goes under "Technical debt". A decision this PR's review settles, such as
  approving it, is not an item.
- **Delete** each item the PR resolves, in the same PR. Don't mark it done;
  git history keeps it.
- **Confirm** each item the PR's work checked: if it still holds, set its
  "Last confirmed" date to today's date, as YYYY-MM-DD, and correct its text.
- Write "Added in" as the PR's own number and link. Open the PR first if it
  has no number yet, then push the items.

## Numbering

Take the id from the line "The next item's id is OI-<n>.", then raise that
line by one in the same commit. Never reuse an id, even a deleted one's. If
two open PRs take the same id, the second to merge gets a conflict on that
line; take the next id after `main`'s.

## Staleness

"Last confirmed" is the last date on which someone checked that the item
still holds and its text is accurate, not the date it was added or edited.
Each Monday, `.github/workflows/open-items.yml` lists the items not confirmed
in 30 days in one issue. `mise run lint:open-items` checks the format; no
check requires a PR to touch the page.
