#!/usr/bin/env bash
# Restore only targets that still match their recorded installation.
set -Eeuo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/lib/common.sh"
dry_run=0
if [ "${1:-}" = --dry-run ]; then dry_run=1; shift; fi
[ "$#" = 1 ] || die "usage: ./restore.sh [--dry-run] ABSOLUTE_INSTALL_DIRECTORY"
run_dir="$1"
validate_path "$run_dir"
[ -d "$run_dir" ] && [ ! -L "$run_dir" ] || die "installation directory missing or symlinked"
check_parents "$run_dir/manifest.tsv"
[ -f "$run_dir/manifest.tsv" ] && [ ! -L "$run_dir/manifest.tsv" ] || die "missing regular manifest"
if [ -f "$run_dir/restored" ]; then printf 'dotfiles: already restored\n'; exit 0; fi

slots=()
targets=()
# Treat the manifest as data, not executable shell.
while IFS=$'\t' read -r slot mode target extra; do
  case "$slot" in ""|*[!0-9]*) die "invalid manifest slot" ;; esac
  case "$mode" in copy|symlink) ;; *) die "invalid manifest mode" ;; esac
  [ -z "$extra" ] || die "invalid manifest columns"
  validate_path "$target"
  check_parents "$target"
  for previous in "${slots[@]+"${slots[@]}"}"; do
    [ "$previous" != "$slot" ] || die "duplicate manifest slot"
  done
  for previous in "${targets[@]+"${targets[@]}"}"; do
    [ "$previous" != "$target" ] || die "duplicate manifest target"
  done
  snapshot="$run_dir/installed/$slot"
  [ -f "$snapshot" ] || [ -L "$snapshot" ] || die "installation snapshot missing"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$mode" = symlink ]; then
      [ -L "$target" ] && [ -L "$snapshot" ] &&
        [ "$(readlink "$target")" = "$(readlink "$snapshot")" ] ||
        die "target changed since install: $target"
    else
      [ -f "$target" ] && [ ! -L "$target" ] && [ ! -L "$snapshot" ] &&
        cmp -s "$target" "$snapshot" || die "target changed since install: $target"
    fi
  fi
  slots+=("$slot")
  targets+=("$target")
done < "$run_dir/manifest.tsv"

# Preflight above covers every target before the first write.
for ((i=${#slots[@]}-1; i>=0; i--)); do
  slot="${slots[i]}"
  target="${targets[i]}"
  printf 'dotfiles: restore %s\n' "$target"
  (( ! dry_run )) || continue
  rm -f -- "$target"
  if [ -e "$run_dir/before/$slot" ] || [ -L "$run_dir/before/$slot" ]; then
    mv "$run_dir/before/$slot" "$target"
  fi
done
if (( ! dry_run )); then : > "$run_dir/restored"; fi
