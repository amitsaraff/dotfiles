# Shared allowlist and path rules. Sourced by the command-line scripts.

die() {
  printf 'dotfiles: error: %s\n' "$*" >&2
  exit 1
}

validate_path() {
  case "$1" in
    /*) ;;
    *) die "expected an absolute path: $1" ;;
  esac
  case "$1" in
    *$'\t'*|*$'\n'*|*$'\r'*) die "tabs and newlines are not supported in paths" ;;
  esac
}

# Never write through a directory symlink owned by another configuration manager.
check_parents() {
  local parent needs_write="${2:-write}"
  parent="$(dirname -- "$1")"
  while [ "$parent" != / ]; do
    [ ! -L "$parent" ] || die "refusing to write through directory symlink: $parent"
    if [ -e "$parent" ]; then
      [ -d "$parent" ] && [ -x "$parent" ] || die "parent is not a searchable directory: $parent"
      if [ "$needs_write" = write ]; then
        [ -w "$parent" ] || die "parent is not a writable directory: $parent"
        needs_write=read
      fi
    fi
    parent="$(dirname -- "$parent")"
  done
}

has_component() {
  case ",$components," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

build_manifest() {
  local component rest="$components"
  [ -n "$rest" ] || die "components must not be empty"
  while :; do
    component="${rest%%,*}"
    case "$component" in
      bash|vim|nvim|tmux) ;;
      *) die "unknown component: $component" ;;
    esac
    [ "$rest" != "$component" ] || break
    rest="${rest#*,}"
  done
  case "$nvim_appname" in
    ""|.|..|*[!a-zA-Z0-9_-]*) die "invalid Neovim app name" ;;
  esac
  config_home="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"
  validate_path "$config_home"
  sources=()
  targets=()
  if has_component bash; then
    sources+=(".bashrc" ".bash_profile")
    targets+=("$TARGET_HOME/.bashrc" "$TARGET_HOME/.bash_profile")
  fi
  if has_component vim; then
    sources+=(".vimrc")
    targets+=("$TARGET_HOME/.vimrc")
  fi
  if has_component nvim; then
    sources+=(".config/nvim/init.lua")
    targets+=("$config_home/$nvim_appname/init.lua")
  fi
  if has_component tmux; then
    sources+=(".tmux.conf")
    targets+=("$TARGET_HOME/.tmux.conf")
  fi
}

version_at_least() {
  local actual_major actual_minor required_major required_minor
  IFS=. read -r actual_major actual_minor _ <<EOF
$1
EOF
  IFS=. read -r required_major required_minor _ <<EOF
$2
EOF
  actual_minor="${actual_minor%%[!0-9]*}"
  (( actual_major > required_major ||
     (actual_major == required_major && ${actual_minor:-0} >= required_minor) ))
}

check_dependencies() {
  local version
  version="$(bash -c 'printf "%s" "$BASH_VERSION"')"
  version_at_least "$version" 3.2 || die "Bash >= 3.2 is required"
  if has_component vim; then
    command -v vim >/dev/null 2>&1 || die "Vim is required for the vim component"
  fi
  if has_component nvim; then
    command -v nvim >/dev/null 2>&1 || die "Neovim >= 0.9 is required"
    version="$(nvim --version)"
    version="${version#NVIM v}"
    version="${version%%$'\n'*}"
    version_at_least "$version" 0.9 || die "Neovim >= 0.9 is required"
  fi
  if has_component tmux; then
    command -v tmux >/dev/null 2>&1 || die "tmux >= 3.2 is required"
    version="$(tmux -V)"
    version_at_least "${version#tmux }" 3.2 || die "tmux >= 3.2 is required"
  fi
}

check_sources() {
  local file
  for file in "${sources[@]}"; do
    [ -f "$SCRIPT_DIR/home/$file" ] && [ -r "$SCRIPT_DIR/home/$file" ] ||
      die "missing or unreadable repository file: home/$file"
    [ ! -L "$SCRIPT_DIR/home/$file" ] || die "repository source must not be a symlink: home/$file"
    check_parents "$SCRIPT_DIR/home/$file" read
  done
}

# Capture only snapshots that pass the guardrail. Never print matching content.
reject_pattern() {
  local status=0
  grep -Eiq -- "$1" "$2" || status=$?
  case "$status" in
    0) die "$2 contains $3; keep that configuration local" ;;
    1) ;;
    *) die "content scanner failed for $2 (grep exit $status)" ;;
  esac
}

scan_content() {
  reject_pattern \
    '(api[_-]?key|api[_-]?token|access[_-]?token|secret|password|passwd|private[[:space:]_-]*key|BEGIN ([A-Z]+ )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+|github_pat_|(AKIA|ASIA)[A-Z0-9]{16}|AWS_(ACCESS_KEY_ID|SESSION_TOKEN)|AIza[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]+)' \
    "$1" "a likely credential marker"
  reject_pattern \
    '(/Users/[^/[:space:]]+|/home/[^$/{[:space:]]+|[A-Z]:\\Users\\|https?://[^/@[:space:]]+:[^/@[:space:]]+@)' \
    "$1" "a machine-specific path or embedded URL credential"
  # Optional company/host patterns belong outside the repository.
  if [ -n "${DOTFILES_PRIVATE_PATTERNS_FILE:-}" ]; then
    [ -f "$DOTFILES_PRIVATE_PATTERNS_FILE" ] && [ -r "$DOTFILES_PRIVATE_PATTERNS_FILE" ] ||
      die "private patterns file is missing or unreadable"
    local pattern
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      case "$pattern" in ""|\#*) continue ;; esac
      reject_pattern "$pattern" "$1" "a private configuration marker"
    done < "$DOTFILES_PRIVATE_PATTERNS_FILE"
  fi
}
