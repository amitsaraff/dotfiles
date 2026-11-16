# Login-shell setup. Keep credentials and machine-specific values in
# ~/.bash_profile.local.

# Load Homebrew's environment when it exists, regardless of the platform's
# installation prefix. It is optional.
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
else
  for _dotfiles_brew in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.local/bin/brew" "$HOME/.linuxbrew/bin/brew"; do
    if [ -x "$_dotfiles_brew" ]; then
      eval "$("$_dotfiles_brew" shellenv)"
      break
    fi
  done
fi
unset _dotfiles_brew

_dotfiles_prepend_path() {
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

_dotfiles_prepend_path "$HOME/.local/bin"
_dotfiles_prepend_path "$HOME/go/bin"
if [ -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin" ]; then
  _dotfiles_prepend_path "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
fi
export PATH
unset -f _dotfiles_prepend_path

if [ -r "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
if [ -r "$HOME/.bash_profile.local" ]; then
  . "$HOME/.bash_profile.local"
fi
