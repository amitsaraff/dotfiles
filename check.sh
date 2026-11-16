#!/usr/bin/env bash
# Local configuration guardrail; not a substitute for a dedicated secret scan.
set -Eeuo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_HOME="$(CDPATH= cd -- "${HOME:?HOME must be set}" && pwd -P)"
readonly SCRIPT_DIR TARGET_HOME
. "$SCRIPT_DIR/lib/common.sh"
components=bash,vim,nvim,tmux
nvim_appname=nvim
build_manifest
check_sources
for source in "${sources[@]}"; do
  scan_content "$SCRIPT_DIR/home/$source"
done
scan_content "$SCRIPT_DIR/home/.gitconfig"
git config --file "$SCRIPT_DIR/home/.gitconfig" --list >/dev/null
for script in install.sh capture.sh restore.sh check.sh lib/common.sh home/.bashrc home/.bash_profile; do
  bash -n "$SCRIPT_DIR/$script"
done
for script in devbox scripts/devbox-keyring scripts/devbox-github-login scripts/devbox-claude-token scripts/claude-keyring; do
  bash -n "$SCRIPT_DIR/$script"
done
git -C "$SCRIPT_DIR" diff --check
printf 'dotfiles: syntax, configuration guardrail, and diff checks passed\n'
