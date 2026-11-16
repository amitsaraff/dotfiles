# Personal dotfiles

For full Ubuntu development-machine provisioning (packages, pinned runtimes,
Docker, encrypted authentication setup, and owned repository checkout), see
[the devbox guide](docs/devbox.md). Run `./devbox help` from the Mac controller.
The configuration-only workflow below remains available independently.

Portable Bash, Vim, Neovim and tmux preferences, plus shared Git settings.
The configuration-only installer does not install packages, change your login
shell, clone plugins, or copy credentials and application state. `devbox` handles
the full machine setup described above.

## Managed configuration

| Component | Repository file | Default destination |
| --- | --- | --- |
| bash | `home/.bashrc` | `~/.bashrc` |
| bash | `home/.bash_profile` | `~/.bash_profile` |
| vim | `home/.vimrc` | `~/.vimrc` |
| nvim | `home/.config/nvim/init.lua` | `${XDG_CONFIG_HOME:-~/.config}/nvim/init.lua` |
| tmux | `home/.tmux.conf` | `~/.tmux.conf` |

Bash supports 3.2 and newer. Selected components require Vim, Neovim >= 0.9,
and/or tmux >= 3.2. Git, fzf, tree and bash-git-prompt enhance the shell when
available; no plugin manager is needed. Unlimited Bash history is used only on
Bash >= 4.3. Your existing terminal and terminfo must support `tmux-256color`.

## New machine

Install the selected programs using your OS package manager, then clone this
repository to a permanent location:

```bash
git clone https://github.com/amitsaraff/dotfiles.git "$HOME/.dotfiles"
cd "$HOME/.dotfiles"
./install.sh --check
./install.sh --dry-run
./install.sh
```

All components are selected by default. To omit Vim or install only the shell:

```bash
./install.sh --components bash,nvim,tmux
./install.sh --components bash
```

Symlinks are the default: edits in the checkout immediately affect future loads.
Do not move/delete the checkout while links are in use. `--copy` creates regular
files instead. Repeated installs skip matching links or identical regular copies.
A copy installation does **not** own future user edits: changed files are conflicts.
Open a new Bash shell and restart/reload applications after installation. Installing
Bash settings does not make Bash your login shell if the machine currently uses zsh.

## Existing machine: choose ownership explicitly

**Default: fail on any unmanaged conflict before making changes.** `--dry-run`
and `--check` also report conflicts; neither writes configuration or backup files.

```bash
# Keep conflicting targets; install only non-conflicting files.
./install.sh --conflict skip

# Explicitly replace conflicting files, preserving their originals.
./install.sh --conflict backup --dry-run
./install.sh --conflict backup
```

Original symlinks are moved as symlinks: files owned by another manager are not
edited. Real directory targets and directory-symlink parents are not replaced or
written through. Exclude the affected component or integrate manually. With
`skip`, an existing target can be left alone even in a symlinked parent directory.

A new `.bash_profile` can shadow `.bash_login` or `.profile`. The installer refuses
this by default; `skip` leaves the login profile uninstalled. `backup` explicitly
accepts the change and warns, but leaves the alternate profile on disk. Move its
needed login setup into your local override or use integration instead.

Neovim's existing `init.vim` is never silently combined with a new `init.lua`.
Use `skip` or a separate application namespace.

### Integrate with an existing dotfiles manager

```bash
./install.sh --components bash,vim,tmux --integrate
```

This prints reviewed-path source hooks and commands, **without editing anything**.
Put those hooks in the files owned by your existing manager, not in this checkout.
Bash login integration sources your existing `.bashrc`; add the interactive hook
there. Put your own overrides after the hooks so your settings win. Do not add a
hook that sources a file back into itself (for example, in an already managed link).

Integration is composition, not semantic merging: aliases, prompt hooks, tmux
options and keybindings can conflict. Review the snippets before using them.

### Keep Neovim or tmux completely separate

```bash
./install.sh --components nvim --nvim-appname personal-nvim
NVIM_APPNAME=personal-nvim nvim

tmux -L personal -f "$HOME/.dotfiles/home/.tmux.conf" new-session
```

Neovim uses `XDG_CONFIG_HOME` when set; it must be an absolute path. The application
name must contain only letters, digits, `_` or `-`. No existing Neovim plugin/Lua
setup is auto-merged. In the separate tmux server, reload with an explicit
`tmux -L personal source-file "$HOME/.dotfiles/home/.tmux.conf"`; Ctrl-A r is the
normal `~/.tmux.conf` reload binding, intended for the default installation.

## Backups and restore

Every installation that changes targets creates a private, uniquely named run
directory under `~/.dotfiles-backups/` (or absolute `DOTFILES_BACKUP_DIR`). It holds
original files, installed snapshots and a data-only manifest. Originals are not
overwritten even when installations happen in the same second.

The installer prints the exact restore command:

```bash
./restore.sh --dry-run "$HOME/.dotfiles-backups/<run-directory>"
./restore.sh "$HOME/.dotfiles-backups/<run-directory>"
```

Restore checks **all** targets first. It refuses to overwrite files or links
changed since installation. Save/reconcile those edits yourself, then retry.
For symlinks, it checks the link destination; edits in the checkout remain there
and are never reverted by restore.
Missing installed targets can be restored. Files newly created by the installation
are removed; originals are moved back. Empty parent directories may remain.
Restore is repeatable, and backups/snapshots are retained for inspection. Restore
newer runs before older runs when their targets overlap.

Ordinary installation failures trigger a best-effort automatic restore. Process
kills, filesystem failures or concurrent edits can still require manual recovery;
keep the printed run directory. Do not run concurrent installers/restores or use
manifests from untrusted sources. Symlink snapshots can be restored even if the
checkout has been moved, by running a remaining copy of `restore.sh` and `lib/`.

## Shared Git settings

`home/.gitconfig` contains the personal author identity, aliases and default
branch captured from the workstation. Devbox provisioning includes it from
`~/.gitconfig` rather than replacing that file, preserving machine-specific
GitHub credential helpers and other includes. The configuration-only installer
does not own your Git config; integrate this file with Git `include.path` if
you use that workflow. Credentials stay outside this repository.

## Local customization and optional plugins

Keep private values and workstation settings outside this repository:

| Application | Local override, loaded last |
| --- | --- |
| interactive Bash | `~/.bashrc.local` |
| login Bash | `~/.bash_profile.local` |
| Vim | `~/.vimrc.local` |
| Neovim | `<its XDG application config directory>/init.local.lua` |
| tmux | `~/.tmux.conf.local` |

Local files are ignored and never part of the capture allowlist. For example,
corporate PATHs, certificate paths and environment settings belong in the shell
local files. Prefer a credential store to plaintext credentials even there.

Optional existing fzf and bash-git-prompt integrations execute trusted local code.
Devbox provisioning installs these dependencies, tree and Bash completion;
configuration-only use keeps them optional.
Set `DOTFILES_GIT_PROMPT=off` **before** sourcing the Bash config to use the built-in
prompt regardless of installed third-party prompts. TPM is not installed or
started automatically. If you intentionally use it, manage it yourself and add
its setup to `~/.tmux.conf.local`.

Ctrl-A + arrow keys move between tmux panes and Neovim splits. At a Neovim split
edge, navigation crosses into the adjacent tmux pane; standalone Neovim does not
invoke tmux. Vim/Neovim swap and backup files are disabled by preference; change
that in your local override if crash recovery is more important.

## Capture portable changes

```bash
./capture.sh --components bash,nvim,tmux --dry-run
./capture.sh --components bash,nvim,tmux
# Use --nvim-appname personal-nvim when capturing the isolated configuration.
git diff -- home
```

Capture uses the same manifest as install, honors XDG paths, and reads only the
selected managed files. All files are first copied to private temporary snapshots
and scanned; a missing source, flagged value, or scanner error prevents capture.
Repository source/destination symlinks are refused. Local files, histories, plugin
checkouts, caches and browser artifacts are never captured.

The built-in scanner rejects common credential markers, several provider-token
formats, embedded URL credentials and absolute workstation home paths. It is
conservative (including comments) and **cannot prove safety**. It cannot recognize
every company endpoint, arbitrary secret, or encoded value. Keep organizational
patterns in an external file, one case-insensitive extended regex per line:

```bash
DOTFILES_PRIVATE_PATTERNS_FILE="$HOME/.dotfiles-private-patterns.local" \
  ./capture.sh --components bash --dry-run
```

Blank lines and `#` comments are skipped. Missing files or invalid regexes fail
closed. Matching credential values are never printed. Scan staged changes and Git
history with a dedicated secret scanner before publishing; `.gitignore` does not
remove already tracked files or values from history. Never copy your current
shell profile wholesale without reviewing its private settings.

## Validate

```bash
./check.sh
python3 -m unittest discover -s tests -v
DOTFILES_TEST_BASH="$(command -v bash)" python3 -m unittest discover -s tests -v
```

Python 3 is only needed for the test suite. CLI tests use temporary homes/checkouts
and stub dependencies; they never install into your real home. The prompt test
also checks actual Bash 3.2 prompt rendering. Application runtime checks are
separate tests and skip unavailable programs. `check.sh` scans managed configs,
checks Bash syntax and checks diff whitespace; it is not a full history scan.
