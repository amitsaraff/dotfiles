#!/usr/bin/env bash
# Capture selected files through scanned, private snapshots.
set -Eeuo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_HOME="$(CDPATH= cd -- "${HOME:?HOME must be set}" && pwd -P)"
readonly SCRIPT_DIR TARGET_HOME
. "$SCRIPT_DIR/lib/common.sh"
components=bash,vim,nvim,tmux
nvim_appname=nvim
dry_run=0
while (($#)); do
  case "$1" in
    --components|--nvim-appname)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      case "$1" in --components) components="$2" ;; --nvim-appname) nvim_appname="$2" ;; esac
      shift ;;
    --dry-run) dry_run=1 ;;
    -h|--help)
      printf 'Usage: ./capture.sh [--components bash,vim,nvim,tmux] [--nvim-appname NAME] [--dry-run]\n'
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
build_manifest
check_sources
for destination in "${sources[@]}"; do
  check_parents "$SCRIPT_DIR/home/$destination"
done
umask 077
stage="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-capture.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT

# Scan all selected snapshots before replacing any repository file.
for ((i=0; i<${#sources[@]}; i++)); do
  source="${targets[i]}"
  [ -f "$source" ] && [ -r "$source" ] || die "source is missing or unreadable: $source"
  cp "$source" "$stage/$i"
  scan_content "$stage/$i"
done
for ((i=0; i<${#sources[@]}; i++)); do
  destination="$SCRIPT_DIR/home/${sources[i]}"
  if cmp -s "$stage/$i" "$destination"; then
    printf 'dotfiles: unchanged home/%s\n' "${sources[i]}"
  elif ((dry_run)); then
    printf 'dotfiles: would capture home/%s\n' "${sources[i]}"
  else
    # Replace the regular repository file; never follow a destination symlink.
    [ ! -L "$destination" ] || die "repository destination became a symlink"
    mv "$stage/$i" "$destination"
    printf 'dotfiles: captured home/%s\n' "${sources[i]}"
  fi
done
