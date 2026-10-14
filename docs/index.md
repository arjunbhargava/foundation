# foundation

The project's documentation. The explanation pages are written by hand. The
API reference is generated from doc comments in the source by
`docs/build.sh`, which fails on any undocumented public symbol or broken
reference.

```{toctree}
:caption: Explanation
:maxdepth: 1

agent-rules-and-skills
architecture
auto-mode
install-script
linear
orchestration
template-plan
template-updates
```

```{toctree}
:caption: API reference
:maxdepth: 1
:glob:

api/*
```
