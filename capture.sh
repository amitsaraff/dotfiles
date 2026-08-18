#!/usr/bin/env bash
# Capture the allowlisted dotfiles from $HOME into this checkout.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_HOME="${HOME:?HOME must be set to capture dotfiles}"

dry_run=0
managed_files=(
  ".bashrc"
  ".bash_profile"
  ".vimrc"
  ".tmux.conf"
)

usage() {
  cat <<'EOF'
Usage: ./capture.sh [--dry-run]

Copy the allowlisted files from $HOME into this checkout after a basic
credential and machine-specific-content check.
EOF
}

die() {
  printf 'capture.sh: error: %s\n' "$*" >&2
  exit 1
}

scan_for_sensitive_content() {
  local source="$1"
  # This catches common mistakes while keeping the check intentionally simple.
  # Review every diff manually; no secret scanner can prove a file is safe.
  if grep -nEiq \
    '(api[_-]?key|api[_-]?token|access[_-]?token|secret|password|passwd|private[[:space:]_-]*key|BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+)' \
    "$source"; then
    die "$source contains a likely credential or private-key marker; remove it or keep it local"
  fi
  if grep -nEiq '(/Users/|/home/[^$/{[:space:]]+|danskebank|danskenet|Zscaler|artifactory)' "$source"; then
    die "$source contains a likely workstation or company-specific path/value; keep it local"
  fi
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown option: $1"
        ;;
    esac
    shift
  done
}

parse_args "$@"

for managed_file in "${managed_files[@]}"; do
  source_file="$SOURCE_HOME/$managed_file"
  destination="$SCRIPT_DIR/home/$managed_file"
  [ -r "$source_file" ] || die "source file is missing or unreadable: $source_file"
  [ -d "$(dirname "$destination")" ] || die "repository home directory is missing"
  scan_for_sensitive_content "$source_file"
done

for managed_file in "${managed_files[@]}"; do
  source_file="$SOURCE_HOME/$managed_file"
  destination="$SCRIPT_DIR/home/$managed_file"
  if [ "$source_file" -ef "$destination" ]; then
    printf 'capture.sh: unchanged %s\n' "$managed_file"
  elif ((dry_run)); then
    printf 'capture.sh: would copy %s -> home/%s\n' "$source_file" "$managed_file"
  else
    cp "$source_file" "$destination"
    printf 'capture.sh: copied %s\n' "$managed_file"
  fi
done
