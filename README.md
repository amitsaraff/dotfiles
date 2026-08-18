# Personal dotfiles

Small, portable shell, Vim, and tmux configuration for a new machine.

The repository deliberately contains only reusable configuration. Machine-specific
paths, credentials, tokens, certificates, and shell history stay outside the
repository.

## Contents

| File | Installed path | Purpose |
| --- | --- | --- |
| home/.bashrc | ~/.bashrc | Interactive Bash settings, aliases, history, and prompt |
| home/.bash_profile | ~/.bash_profile | Login-shell PATH setup and .bashrc loading |
| home/.vimrc | ~/.vimrc | Vim defaults and key mappings |
| home/.tmux.conf | ~/.tmux.conf | tmux terminal, key, pane, mouse, and status settings |

## Install on a new machine

The installer uses symlinks by default, so changes made in this checkout are
immediately active. Existing files are moved to a timestamped backup directory
under ~/.dotfiles-backups/ before anything is installed.

    git clone https://github.com/amitsaraff/dotfiles.git "$HOME/.dotfiles"
    cd "$HOME/.dotfiles"
    ./install.sh

The installer checks bash, git, vim, and tmux before making any changes.
Use ./install.sh --check to run only those checks, or ./install.sh --copy if
symlinks are not wanted. --dry-run previews the installation.

On macOS, Homebrew is recommended for missing tools:

    brew install bash git vim tmux
    brew install fzf tree             # optional shell enhancements

The configuration supports macOS Bash 3.2 and newer Bash versions. Unlimited
history is enabled automatically only on Bash 4.3+, because older Bash versions
do not safely support HISTSIZE=-1.

## Capture changes from the current machine

Capture is intentionally allowlisted to the four files above. It refuses files
containing common credential markers or private-key material before copying them
into the checkout.

    cd "$HOME/.dotfiles"
    ./capture.sh --dry-run
    ./capture.sh
    git diff -- home

Always review the diff for secrets and workstation-specific values before
committing. The scanner is a guardrail, not a guarantee.

## Local customization

Keep private or machine-specific additions in ~/.bashrc.local and/or
~/.bash_profile.local. The managed files source these files when present, and
they are never part of the repository.
