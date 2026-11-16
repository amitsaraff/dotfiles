# Interactive Bash configuration.
# Keep credentials and machine-specific settings in ~/.bashrc.local.

case $- in
  *i*) ;;
  *) return ;;
esac

# Append/prepend hooks without flattening a modern Bash PROMPT_COMMAND array.
_dotfiles_add_prompt_hook() {
  local hook="$1" position="$2" existing
  case "$(declare -p PROMPT_COMMAND 2>/dev/null)" in
    "declare -a"*)
      for existing in "${PROMPT_COMMAND[@]}"; do
        [ "$existing" != "$hook" ] || return 0
      done
      if [ "$position" = first ]; then
        PROMPT_COMMAND=("$hook" "${PROMPT_COMMAND[@]}")
      else
        PROMPT_COMMAND+=("$hook")
      fi
      ;;
    *)
      case ";${PROMPT_COMMAND:-};" in
        *";$hook;"*|*"; $hook;"*) return 0 ;;
      esac
      if [ "$position" = first ]; then
        PROMPT_COMMAND="$hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
      else
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }$hook"
      fi
      ;;
  esac
}

# fzf shell integration is useful but optional.
if command -v fzf >/dev/null 2>&1; then
  _dotfiles_fzf_init="$(fzf --bash 2>/dev/null || true)"
  if [ -n "$_dotfiles_fzf_init" ]; then
    eval "$_dotfiles_fzf_init"
  fi
  unset _dotfiles_fzf_init
fi

# Prefer the richer bash-git-prompt when it is already installed. The fallback
# below keeps the prompt useful on a clean machine without another dependency.
_dotfiles_git_prompt_loaded=0
for _dotfiles_git_prompt in \
  "${BASH_GIT_PROMPT_FILE:-}" \
  "$HOME/.bash-git-prompt/share/gitprompt.sh" \
  "$HOME/.bash-git-prompt/gitprompt.sh" \
  "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/opt/bash-git-prompt/share/gitprompt.sh}" \
  "/opt/homebrew/opt/bash-git-prompt/share/gitprompt.sh" \
  "/usr/local/opt/bash-git-prompt/share/gitprompt.sh"; do
  if [ "${DOTFILES_GIT_PROMPT:-auto}" != off ] &&
     [ -n "$_dotfiles_git_prompt" ] && [ -r "$_dotfiles_git_prompt" ]; then
    GIT_PROMPT_FETCH_REMOTE_STATUS="${GIT_PROMPT_FETCH_REMOTE_STATUS:-0}"
    # shellcheck disable=SC1090
    . "$_dotfiles_git_prompt"
    _dotfiles_git_prompt_loaded=1
    break
  fi
done
unset _dotfiles_git_prompt

if [ "$_dotfiles_git_prompt_loaded" -eq 0 ]; then
  _dotfiles_git_branch() {
    command git symbolic-ref --short HEAD 2>/dev/null || \
      command git rev-parse --short HEAD 2>/dev/null || true
  }

  _dotfiles_prompt() {
    local exit_status="$?"
    _dotfiles_branch="$(_dotfiles_git_branch)"
    # Expand branch data as a variable, not as fresh prompt syntax.
    # Substitutions inside the variable value are not evaluated recursively.
    PS1='\u@\h:\w${_dotfiles_branch:+ [${_dotfiles_branch}]}\$ '
    return "$exit_status"
  }

  _dotfiles_add_prompt_hook _dotfiles_prompt first
fi

# fzf and tree remain optional; the aliases only exist when their commands do.
if command -v tree >/dev/null 2>&1; then
  alias tree='tree -Csuh'
fi

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'
alias ..='cd ..'

alias h='history'
alias j='jobs -l'
alias which='type -a'
_dotfiles_print_path() {
  local rest="$1"
  while :; do
    printf '%s\n' "${rest%%:*}"
    [ "$rest" != "${rest#*:}" ] || break
    rest="${rest#*:}"
  done
}
alias path='_dotfiles_print_path "${PATH:-}"'
alias libpath='_dotfiles_print_path "${LD_LIBRARY_PATH:-}"'
alias du='du -kh'

if [[ "${OSTYPE:-}" = darwin* ]]; then
  alias df='df -kh'
  alias ls='ls -hG'
else
  alias df='df -kTh'
  if ls --color=auto -d . >/dev/null 2>&1; then
    alias ls='ls -h --color=auto'
  else
    alias ls='ls -h'
  fi
fi
alias ll='ls -lv'
alias la='ll -A'
alias lm='ll | more'
alias lr='ll -R'
alias lk='ls -lSr'
alias lt='ls -ltr'
alias lx='ls -lXB'
alias lc='ls -ltcr'
alias lu='ls -ltur'

# Unlimited history is safe on Bash 4.3+. Keep bounded, useful defaults on
# macOS's system Bash 3.2 rather than using HISTSIZE=-1 there.
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || \
   { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 3 ]; }; then
  HISTSIZE=-1
  HISTFILESIZE=-1
else
  HISTSIZE=10000
  HISTFILESIZE=20000
fi
export HISTFILE="${HISTFILE:-$HOME/.bash_history}"
export HISTSIZE HISTFILESIZE
export HISTTIMEFORMAT='[%F %T] '
export HISTCONTROL=ignoredups
shopt -s histappend

_dotfiles_history_sync() {
  history -a
  history -n
}
_dotfiles_add_prompt_hook _dotfiles_history_sync last

# A local file is the supported escape hatch for credentials and per-machine
# settings. It is intentionally not part of this repository.
if [ -r "$HOME/.bashrc.local" ]; then
  . "$HOME/.bashrc.local"
fi
