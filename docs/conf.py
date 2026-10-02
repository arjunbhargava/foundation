"""Sphinx configuration for the documentation site, which docs/build.sh builds."""

project = "foundation"

extensions = [
    "myst_parser",
    "autoapi.extension",
    "sphinx.ext.intersphinx",
    "sphinx.ext.napoleon",
]

# Python: parsed from source without importing it.
autoapi_dirs = ["../src"]
autoapi_root = "api/python"
autoapi_options = [
    "members",
    "show-inheritance",
    "show-module-summary",
    "imported-members",
]
autoapi_add_toctree_entry = False

# Rust: docs/build.sh copies rustdoc's HTML into _generated/html, and Sphinx
# publishes it unchanged, without reading it as sources.
html_extra_path = ["_generated/html"]

# Links standard-library names in signatures, such as collections.abc.Sequence,
# to the Python docs. nitpicky fails the build on any it can't resolve. Each
# build downloads this inventory, so it needs network access.
intersphinx_mapping = {"python": ("https://docs.python.org/3", None)}

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
exclude_patterns = ["_build"]
