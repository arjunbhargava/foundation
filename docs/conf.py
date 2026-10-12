"""Sphinx configuration for the documentation site, which docs/build.sh builds.

Each language's block applies only when the language's manifest exists, as
its block in docs/build.sh does, so a project without the language leaves out
its extensions and settings.
"""

from pathlib import Path

project = "foundation"
repository_root = Path(__file__).resolve().parent.parent

extensions = ["myst_parser"]

# Python: parsed from source without importing it.
if (repository_root / "pyproject.toml").is_file():
    extensions += ["autoapi.extension", "sphinx.ext.intersphinx", "sphinx.ext.napoleon"]
    autoapi_dirs = ["../src"]
    autoapi_root = "api/python"
    autoapi_options = [
        "members",
        "show-inheritance",
        "show-module-summary",
        "imported-members",
    ]
    autoapi_add_toctree_entry = False
    # Links standard-library names in signatures, such as
    # collections.abc.Sequence, to the Python docs. nitpicky fails the build on
    # any it can't resolve. Each build downloads this inventory, so it needs
    # network access.
    intersphinx_mapping = {"python": ("https://docs.python.org/3", None)}

# Rust: docs/build.sh copies rustdoc's HTML into _generated/html, and Sphinx
# publishes it unchanged, without reading it as sources.
if (repository_root / "Cargo.toml").is_file():
    html_extra_path = ["_generated/html"]

# C and C++: docs/build.sh runs Doxygen, whose XML Breathe reads.
if (repository_root / "CMakeLists.txt").is_file():
    extensions.append("breathe")
    breathe_projects = {"foundation": "_generated/doxygen"}
    breathe_default_project = "foundation"

nitpicky = True
myst_heading_anchors = 3

html_theme = "furo"
html_title = project
# NOTICE holds the copyright line; without this the footer shows an empty one.
html_show_copyright = False
html_theme_options = {
    "light_css_variables": {
        "color-brand-primary": "#b4532f",
        "color-brand-content": "#b4532f",
    },
    "dark_css_variables": {
        "color-brand-primary": "#d97757",
        "color-brand-content": "#d97757",
    },
}
# .venv is the environment of the docs build's own uv project, docs/pyproject.toml.
exclude_patterns = ["_build", ".venv"]
