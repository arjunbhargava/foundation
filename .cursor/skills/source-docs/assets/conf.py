"""Sphinx hub for docs built from source. Copy to docs/conf.py and edit the marked lines."""

project = "PROJECT"  # edit

extensions = [
    "myst_parser",
    # Python sources (remove if none):
    "autoapi.extension",
    "sphinx.ext.napoleon",
    # C/C++ sources via Doxygen XML (add if any): "breathe",
]

# Python: parsed from source without importing it.
autoapi_dirs = ["../src"]  # edit
autoapi_root = "api/python"
autoapi_options = ["members", "show-inheritance", "show-module-summary", "imported-members"]
autoapi_add_toctree_entry = False

nitpicky = True
myst_heading_anchors = 3

html_theme = "furo"
html_title = project
html_theme_options = {
    "light_css_variables": {"color-brand-primary": "#b4532f", "color-brand-content": "#b4532f"},
    "dark_css_variables": {"color-brand-primary": "#d97757", "color-brand-content": "#d97757"},
}
html_extra_path = ["_generated/html"]
exclude_patterns = ["_build", "_generated/html", "_generated/*-target"]
