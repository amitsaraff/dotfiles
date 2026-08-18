#!/usr/bin/env bash
# Install the managed files into the current user's home directory.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly TARGET_HOME="${HOME:?HOME must be set to install dotfiles}"
readonly BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$TARGET_HOME/.dotfiles-backups}"

mode="symlink"
dry_run=0
check_only=0

managed_files=(
  ".bashrc"
  ".bash_profile"
  ".vimrc"
  ".tmux.conf"
)

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Install the repository's managed files into $HOME.

Options:
  --check       Validate dependencies and source files without installing.
  --copy        Copy files instead of creating symlinks.
  --dry-run     Show what would happen without changing files.
  -h, --help    Show this help.
EOF
}

die() {
  printf 'install.sh: error: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

version_at_least() {
  # Compare two dotted numeric versions without relying on sort -V.
  local actual="$1" required="$2"
  local actual_major actual_minor required_major required_minor
  IFS=. read -r actual_major actual_minor _ <<EOF
$actual
EOF
  IFS=. read -r required_major required_minor _ <<EOF
$required
EOF
  actual_major=${actual_major:-0}
  actual_minor=${actual_minor:-0}
  required_major=${required_major:-0}
  required_minor=${required_minor:-0}

  if (( actual_major > required_major )); then
    return 0
  fi
  if (( actual_major == required_major && actual_minor >= required_minor )); then
    return 0
  fi
  return 1
}

check_bash() {
  local bash_path bash_version
  bash_path="$(command -v bash || true)"
  [ -n "$bash_path" ] || die "bash is required; install Bash 3.2 or newer"
  bash_version="$("$bash_path" -c 'printf "%s\n" "$BASH_VERSION"')"
  version_at_least "$bash_version" "3.2" || die "bash >= 3.2 is required (found $bash_version)"
}

check_command_dependencies() {
  local missing=()
  local command_name
  for command_name in git vim tmux; do
    if ! command_exists "$command_name"; then
      missing+=("$command_name")
    fi
  done
  if ((${#missing[@]} > 0)); then
    die "missing required command(s): ${missing[*]}; install them and run ./install.sh again"
  fi
}

check_source_files() {
  local file
  for file in "${managed_files[@]}"; do
    [ -r "$SCRIPT_DIR/home/$file" ] || die "repository file is missing or unreadable: home/$file"
  done
}

check_target_home() {
  [ -d "$TARGET_HOME" ] || die "target home directory does not exist: $TARGET_HOME"
  [ -w "$TARGET_HOME" ] || die "target home directory is not writable: $TARGET_HOME"
}

show_optional_dependencies() {
  local optional=()
  command_exists fzf || optional+=("fzf")
  command_exists tree || optional+=("tree")
  if ((${#optional[@]} > 0)); then
    printf 'install.sh: note: optional command(s) not found: %s\n' "${optional[*]}"
  fi
}

run_checks() {
  check_bash
  check_command_dependencies
  check_source_files
  check_target_home
  show_optional_dependencies
  printf 'install.sh: dependency and source checks passed\n'
}

print_action() {
  if ((dry_run)); then
    printf 'dry-run: %s\n' "$*"
  fi
}

install_file() {
  local file="$1"
  local source="$SCRIPT_DIR/home/$file"
  local target="$TARGET_HOME/$file"

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    print_action "leave $target (already linked)"
    return 0
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    print_action "move $target to $backup_dir/$file"
    if (( ! dry_run )); then
      mkdir -p "$backup_dir"
      mv "$target" "$backup_dir/$file"
    fi
  fi

  if [ "$mode" = "symlink" ]; then
    print_action "link $target -> $source"
    if (( ! dry_run )); then
      ln -s "$source" "$target"
    fi
  else
    print_action "copy $source -> $target"
    if (( ! dry_run )); then
      cp "$source" "$target"
    fi
  fi
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --check)
        check_only=1
        ;;
      --copy)
        mode="copy"
        ;;
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
run_checks

if ((check_only)); then
  exit 0
fi

timestamp="$(date '+%Y%m%d-%H%M%S')"
backup_dir="$BACKUP_ROOT/$timestamp"
for managed_file in "${managed_files[@]}"; do
  install_file "$managed_file"
done

if ((dry_run)); then
  printf 'install.sh: dry-run complete\n'
elif [ -d "$backup_dir" ]; then
  printf 'install.sh: installed %d file(s); backups: %s\n' "${#managed_files[@]}" "$backup_dir"
else
  printf 'install.sh: installed %d file(s); no existing files needed backup\n' "${#managed_files[@]}"
fi
