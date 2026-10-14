"""Sphinx configuration for the documentation site, which docs/build.sh builds.

Each language's block applies only when the language's manifest exists, as
its block in docs/build.sh does, so a project without the language leaves out
its extensions and settings.
"""

from pathlib import Path
from typing import Any

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


# The parameters are Sphinx and docutils objects, typed Any because the root
# environment, whose pyright checks this file, doesn't have Sphinx.
def setup(app: Any) -> None:
    """Connect this file's event handlers to Sphinx.

    Args:
        app: The Sphinx application.
    """
    app.connect("doctree-read", _unlink_repository_paths)


def _unlink_repository_paths(app: Any, doctree: Any) -> None:
    """Turn links from root files, such as README.md, to paths outside docs/ into text.

    README.md and AGENTS.md, which project-readme.md and agent-instructions.md
    include, are written for GitHub, where a link to a repository file or
    directory opens it. The site has no page for one, so the strict build would
    fail on each such link. Their links into docs/ already work, through the
    include's relative-docs option: a link to a page leads to it, and a link
    to another file downloads it. A link to a path that doesn't exist is left
    alone, so it still fails the build.
    """
    for node in list(doctree.findall()):
        is_unresolved_link = (
            node.tagname == "pending_xref"
            and node["reftype"] == "myst"
            and node["refdomain"] is None
        )
        if not is_unresolved_link:
            continue
        is_in_root_file = Path(node.source).resolve().parent == repository_root
        if is_in_root_file and (repository_root / node["reftarget"]).exists():
            node.replace_self(node.children)
