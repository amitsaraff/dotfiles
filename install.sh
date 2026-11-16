#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_HOME="$(CDPATH= cd -- "${HOME:?HOME must be set}" && pwd -P)"
readonly SCRIPT_DIR TARGET_HOME
. "$SCRIPT_DIR/lib/common.sh"

mode=symlink
conflict=fail
components=bash,vim,nvim,tmux
nvim_appname=nvim
dry_run=0
check_only=0
integrate=0
run_dir=""

usage() {
  cat <<'HELP'
Usage: ./install.sh [options]
  --components LIST       Comma-separated bash,vim,nvim,tmux (default: all).
  --conflict POLICY       fail (default), skip, or backup.
  --copy                  Copy instead of symlink; equal regular files are skipped.
  --nvim-appname NAME     Install a separate Neovim configuration namespace.
  --integrate             Print integration snippets; never edit existing configs.
  --check                 Check selected sources, dependencies, and conflicts.
  --dry-run               Preview all actions without writing anything.
  -h, --help              Show help.
HELP
}

while (($#)); do
  case "$1" in
    --components|--conflict|--nvim-appname)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      case "$1" in
        --components) components="$2" ;;
        --conflict) conflict="$2" ;;
        --nvim-appname) nvim_appname="$2" ;;
      esac
      shift ;;
    --copy) mode=copy ;;
    --integrate) integrate=1 ;;
    --check) check_only=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
case "$conflict" in fail|skip|backup) ;; *) die "unknown conflict policy: $conflict" ;; esac
build_manifest
check_sources
check_dependencies

if ((integrate)); then
  printf '# Snippets only: review ordering and conflicting options before adding them.\n'
  if has_component bash; then
    printf '# Existing .bashrc (interactive settings):\n. %q\n' "$SCRIPT_DIR/home/.bashrc"
    printf '# Existing login profile (PATH setup; also sources your .bashrc):\n. %q\n' "$SCRIPT_DIR/home/.bash_profile"
  fi
  if has_component vim; then
    vim_path="${SCRIPT_DIR//\'/\'\'}"
    printf "# Existing .vimrc:\nexecute 'source ' . fnameescape('%s/home/.vimrc')\n" "$vim_path"
  fi
  if has_component tmux; then
    printf '# Apply on demand to the current tmux server (changes global options/bindings):\ntmux source-file %q\n' "$SCRIPT_DIR/home/.tmux.conf"
    printf '# Or start a separate server:\ntmux -L personal -f %q new-session\n' "$SCRIPT_DIR/home/.tmux.conf"
  fi
  if has_component nvim; then
    printf '# Do not auto-merge Lua/plugin setups. For an isolated configuration:\n'
    printf '# ./install.sh --components nvim --nvim-appname personal-nvim\n'
    printf 'NVIM_APPNAME=personal-nvim nvim\n'
  fi
  exit 0
fi

actions=()
for ((i=0; i<${#sources[@]}; i++)); do
  source="$SCRIPT_DIR/home/${sources[i]}"
  target="${targets[i]}"
  validate_path "$target"
  action=install
  if [ "$mode" = symlink ] && [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    action=unchanged
  elif [ "$mode" = copy ] && [ -f "$target" ] && [ ! -L "$target" ] && cmp -s "$source" "$target"; then
    action=unchanged
  elif [ -e "$target" ] || [ -L "$target" ]; then
    [ ! -d "$target" ] || [ -L "$target" ] || die "target is a directory: $target"
    case "$conflict" in
      fail) die "existing unmanaged config: $target (use --conflict skip or backup)" ;;
      skip) action=skip ;;
      backup) action=backup ;;
    esac
  fi
  if [ "${sources[i]}" = .config/nvim/init.lua ] &&
     { [ -e "$(dirname -- "$target")/init.vim" ] || [ -L "$(dirname -- "$target")/init.vim" ]; }; then
    if [ "$conflict" = skip ]; then
      action=skip
    else
      die "Neovim init.vim already exists; use --nvim-appname for isolation or --conflict skip"
    fi
  fi
  case "$action" in install|backup) check_parents "$target" ;; esac
  actions+=("$action")
done

# A new .bash_profile would silently shadow an existing alternate login profile.
if has_component bash && [ ! -e "$TARGET_HOME/.bash_profile" ] && [ ! -L "$TARGET_HOME/.bash_profile" ]; then
  if [ -e "$TARGET_HOME/.profile" ] || [ -L "$TARGET_HOME/.profile" ] ||
     [ -e "$TARGET_HOME/.bash_login" ] || [ -L "$TARGET_HOME/.bash_login" ]; then
    case "$conflict" in
      fail) die "new .bash_profile would shadow .profile/.bash_login; use --integrate or explicitly choose backup/skip" ;;
      skip) actions[1]=skip ;;
      backup) printf 'dotfiles: warning: new .bash_profile shadows .profile/.bash_login; originals remain on disk\n' >&2 ;;
    esac
  fi
fi

backup_root="${DOTFILES_BACKUP_DIR:-$TARGET_HOME/.dotfiles-backups}"
validate_path "$backup_root"
check_parents "$backup_root/run"
if ((check_only)); then
  printf 'dotfiles: selected dependency, source, and conflict checks passed\n'
  exit 0
fi

rollback() {
  local status="$?"
  trap - EXIT
  if ((status != 0)) && [ -n "$run_dir" ]; then
    printf 'dotfiles: install interrupted; attempting restore from %s\n' "$run_dir" >&2
    bash "$SCRIPT_DIR/restore.sh" "$run_dir" || printf 'dotfiles: automatic restore failed; keep the backup directory for manual recovery\n' >&2
  fi
  exit "$status"
}
trap rollback EXIT

for ((i=0; i<${#sources[@]}; i++)); do
  source="$SCRIPT_DIR/home/${sources[i]}"
  target="${targets[i]}"
  action="${actions[i]}"
  printf 'dotfiles: %s %s (%s)\n' "$action" "$target" "$mode"
  case "$action" in unchanged|skip) continue ;; esac
  (( ! dry_run )) || continue
  if [ -z "$run_dir" ]; then
    umask 077
    mkdir -p "$backup_root"
    run_dir="$(mktemp -d "$backup_root/$(date '+%Y%m%d-%H%M%S').XXXXXX")"
    mkdir "$run_dir/before" "$run_dir/installed" "$run_dir/staged"
    : > "$run_dir/manifest.tsv"
  fi
  mkdir -p "$(dirname -- "$target")"
  if [ "$mode" = symlink ]; then
    ln -s "$source" "$run_dir/installed/$i"
    ln -s "$source" "$run_dir/staged/$i"
  else
    cp "$source" "$run_dir/installed/$i"
    cp "$run_dir/installed/$i" "$run_dir/staged/$i"
  fi
  # Record before mutating the target so an interrupted install can be restored.
  printf '%s\t%s\t%s\n' "$i" "$mode" "$target" >> "$run_dir/manifest.tsv"
  if [ -e "$target" ] || [ -L "$target" ]; then
    # Preserve the original symlink itself, never its referent.
    mv "$target" "$run_dir/before/$i"
  fi
  mv "$run_dir/staged/$i" "$target"
done
if ((dry_run)); then
  printf 'dotfiles: dry-run complete; no files changed\n'
elif [ -n "$run_dir" ]; then
  printf 'dotfiles: installed; restore with:\n  %q %q\n' "$SCRIPT_DIR/restore.sh" "$run_dir"
else
  printf 'dotfiles: nothing to change\n'
fi
