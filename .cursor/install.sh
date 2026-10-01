#!/usr/bin/env bash
# Install step for cloud agent machines, run by environment.json. Installs the
# pinned mise if it is missing, then the tools and dependencies that mise.toml
# lists, so the machine matches CI. Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")/.."

# Cloud agent machines are x86-64 Linux. To bump, take the sha256 of
# mise-v<version>-linux-x64 from the release's SHASUMS256.txt.
mise_version=2026.9.18
mise_sha256=d24fe0bf7e613824ad99f7b8dac3f2b381a37b9f75f84dd250855217095a8de4

if [[ $(mise --version 2>/dev/null) != "$mise_version "* ]]; then
  download=$(mktemp)
  curl -fsSL -o "$download" \
    "https://github.com/jdx/mise/releases/download/v$mise_version/mise-v$mise_version-linux-x64"
  echo "$mise_sha256  $download" | sha256sum --check --quiet
  sudo install -m 755 "$download" /usr/local/bin/mise
  rm "$download"
fi

mise install
mise run setup
