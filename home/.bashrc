# Interactive Bash configuration.
# Keep credentials and machine-specific settings in ~/.bashrc.local.

case $- in
  *i*) ;;
  *) return ;;
esac

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
  "/opt/homebrew/opt/bash-git-prompt/share/gitprompt.sh" \
  "/usr/local/opt/bash-git-prompt/share/gitprompt.sh"; do
  if [ -n "$_dotfiles_git_prompt" ] && [ -r "$_dotfiles_git_prompt" ]; then
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
    local branch
    branch="$(_dotfiles_git_branch)"
    if [ -n "$branch" ]; then
      PS1="\\u@\\h:\\w [$branch]\\$ "
    else
      PS1="\\u@\\h:\\w\\$ "
    fi
    return "$exit_status"
  }

  PROMPT_COMMAND="_dotfiles_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
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
alias path='printf "%s\\n" "${PATH//:/\\n}"'
alias libpath='printf "%s\\n" "${LD_LIBRARY_PATH//:/\\n}"'
alias du='du -kh'

if [ "${OSTYPE:-}" = darwin* ]; then
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
case ";${PROMPT_COMMAND:-};" in
  *";_dotfiles_history_sync;"*) ;;
  *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_dotfiles_history_sync" ;;
esac

# A local file is the supported escape hatch for credentials and per-machine
# settings. It is intentionally not part of this repository.
if [ -r "$HOME/.bashrc.local" ]; then
  . "$HOME/.bashrc.local"
fi
