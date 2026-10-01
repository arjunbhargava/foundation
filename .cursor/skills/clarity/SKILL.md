---
name: clarity
description: >
  Make code, docs, diagrams, and interfaces as easy as possible for people to
  understand. Use for any work a person will read: code structure and layout,
  naming, comments, error messages, documentation, PR descriptions, commit
  messages, visual design, and colour.
---

# Clarity

Everything in a repository is read far more often than it is written. The
goal of every change is that the reader builds a correct mental model with the
least effort. The reader is a competent engineer who is new to this code.

The other rules and skills serve this goal. Ponytail minimalism means fewer
concepts for the reader to hold, not fewer characters: when the shortest code
is harder to follow than a slightly longer version, write the longer version.
`architecture-docs` applies this skill to system structure and diagrams, and
`source-docs` applies it to API reference.

## Code structure

- **Organise by what the code does, not by its kind.** Name a module
  `integrator` or `checkpoint`, not `utils`, `helpers`, `managers`, or `common`.
- **One responsibility per unit.** A function's name should describe all it
  does. If the name needs "and", split the function.
- **Read top to bottom.** Put the public entry point first and its helpers
  after, in the order they are called. The order in the file follows the data
  flow.
- **Keep related code together.** A reader should understand a behaviour from
  one file. Every hop to another file or through an interface costs the reader
  something, so each one must buy something.
- **Make data flow explicit.** Pass inputs as arguments and return results.
  Avoid hidden global state, mutation of arguments, and action at a distance.
- **Keep the main path unindented.** Handle errors and edge cases with early
  returns, so the normal case reads straight down.
- **Prefer plain constructs.** A loop the reader follows at once beats a clever
  expression that must be decoded. Use a language feature only when its
  meaning is obvious to the reader described above.

## Naming

- A name states what the thing means in the domain, not how it is stored:
  `converged_solution`, not `arr2` or `float_buf`.
- Include units in names: `timeout_ms`, `sample_rate_hz`, `size_bytes`.
- Booleans are predicates (`is_converged`, `has_checkpoint`). Functions are
  verbs (`write_checkpoint`). Values are nouns.
- One name per concept, used everywhere: code, docs, diagrams, logs, and UI.
  Renaming a concept renames it everywhere in the same PR.
- Spell words out. Use only abbreviations the reader already knows, such as
  `id`, `url`, `CPU`, and `GPU`, and define domain acronyms in the glossary.
- Name length grows with scope: `i` in a three-line loop, a full phrase for a
  module-level constant.
- Avoid names that carry no information: `data`, `info`, `item`, `obj`,
  `handle`, `process`, `manager`.

## Layout

- Run the language's standard formatter. Never format by hand.
- Separate the steps of a function with blank lines, as paragraphs separate
  ideas in prose.
- One idea per line. Split a long condition into named intermediate values.
- Put constants and configuration at the top of the file, with units and the
  source of each value.

## Comments and messages

- Comments state what the code cannot: intent, constraints, invariants, units,
  and why a simpler approach fails. Never restate what the next line does.
- Docstrings state the contract: inputs, outputs, errors, and side effects.
- Error messages say what happened, include the offending value, and say what
  to do next: `TRACKER_API_KEY is not set; add it to .env`, not `config error`.
- Log messages follow the same rule and use the same names as the code.

## Visual design and colour

These apply to diagrams, docs sites, terminal output, and user interfaces.
For diagrams, `architecture-docs/references/diagram-style.md` defines the
palette and vocabulary.

- Colour encodes meaning, one meaning per colour, the same across the repo.
  Every encoding has a legend.
- Never rely on colour alone. Pair it with shape, label, or position, so
  colour-blind readers and greyscale prints lose nothing.
- Text meets WCAG AA contrast: at least 4.5:1, or 3:1 for large text.
- Use few colours and one accent. The accent marks the single thing the
  reader should look at first.
- Group with position and whitespace before adding borders or boxes.
- Show hierarchy with size and weight, not with extra colours.

## Writing

This covers docs, docstrings, PR descriptions, commit messages, and replies.

- **Open with the claim.** The first sentence says what this is and what the
  reader can do with it. Include status (planned, stable, deprecated) when it
  isn't obvious.
- **Concrete before abstract.** Show one real example or one end-to-end trace,
  then generalise.
- **Define before use.** Introduce each term once, precisely, then use it
  consistently.
- **Progressive disclosure.** Overview, then mechanism, then edge cases. A
  reader who stops after the first section still has a correct, coarse model.
- **Explain why.** Code shows what. Writing carries intent, trade-offs,
  rejected alternatives, and when to revisit a decision.
- **Quantify.** Write "p95 under 40 ms per time step for a 512³ grid on one
  GPU", not "fast". State units and where numbers came from.
- **Plain, literal language.** Use complete sentences and ordinary words.
  Leave out slogans, catchphrases, aphorisms, jokes, rhetorical questions,
  marketing adjectives, and emoji. They cost attention and teach nothing.
- **Short, not compressed.** Say each thing once and cut whatever doesn't
  change what the reader will do. Don't shorten by dropping articles, chaining
  arrows, or inventing abbreviations; that moves the effort to the reader.
- **Link, don't duplicate.** Each fact lives in one place.

## Review checklist

Before finishing, reread the change as the new engineer described above:

1. Can they say what each changed unit does from its name and signature alone?
2. Can they follow the main path of each function without jumping files?
3. Is each concept called the same thing everywhere?
4. Does every comment say something the code cannot?
5. Does every colour, shape, and line style have one meaning, shown in a
   legend?
6. Is any sentence a slogan or a restatement? Delete it.
7. Is anything left that no reader needs? Delete it.
