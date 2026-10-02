# foundation

The project's documentation. The explanation pages are written by hand. The
API reference is generated from doc comments in the source by
`docs/build.sh`, which fails on any undocumented public symbol or broken
reference.

```{toctree}
:caption: Explanation
:maxdepth: 1

architecture
linear
template-plan
```

```{toctree}
:caption: API reference
:maxdepth: 1

Python <api/python/foundation/index>
api/rust
api/cpp
```
