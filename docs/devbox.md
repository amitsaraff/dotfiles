# Ubuntu development box

Version one targets Ubuntu 26.04 on x86-64, provisioned over your existing SSH
configuration. It does not change SSH, Tailscale, your login shell, or system
Python. The current inventory is `aks-hertzner`; review inventory and release
hashes before adding another host. The controller needs Git, Python 3, and
[uv](https://docs.astral.sh/uv/getting-started/installation/).

## Provision from your Mac

From this checkout:

```bash
./devbox syntax
./devbox check
./devbox apply
./devbox verify
```

The wrapper runs a pinned Ansible Core in a uv-managed environment, without
installing Ansible into system Python. It transfers reviewed source, including
uncommitted implementation files, without `.git`, credentials, histories,
ignored files, or local overrides. The target's permanent checkout is
`~/src/dotfiles`. Initial public cloning needs no GitHub login.

`check` previews supported package/configuration tasks. Downloads, runtime/tool
commands, source deployment, authentication, and repository cloning are skipped
in check mode: a clean preview is not evidence that these boundaries work.
`verify` exercises the actual installed applications. Use Ansible options such
as `--limit aks-hertzner` or `--tags dotfiles` after the action name.
Transient source staging/cleanup tasks do not count as configuration changes;
the deployment task reports the number of actual source updates. A second
unchanged `apply` should report `changed=0`.

## What is installed

System packages include Bash/completion, Git, gh, Neovim, tmux/terminfo, fzf,
bat/fd/ripgrep/jq/tree, build tools, archives, ShellCheck, ImageMagick, Poppler,
Tesseract, and Chromium-oriented browser OS libraries/Xvfb. `fd` and `bat` have
conventional executable names in `~/.local/bin`, pointing to Ubuntu's binaries.

Homebrew is installed at its supported Linux prefix, with a user-bin launcher
for portable Bash discovery. It installs `bash-git-prompt`; existing apt tools
are not duplicated. Routine provisioning disables Homebrew auto-update and
does not upgrade installed formulae. The official bootstrap script is pinned
by revision and SHA256.

User tools include checksum-pinned mise, uv and Pixi; pinned Node LTS and Go;
user Python 3.13/3.14 and isolated PDM; Codex, Claude Code and Playwright CLI.
Docker Engine and Compose come from Docker's signed Ubuntu repository. Run
Docker with `sudo`; the playbook does not grant membership in the root-equivalent
Docker group. No Docker remote TCP API or development service ports are opened.
Publishing a container port later is a separate operation you control.

Exact versions and artifact checksums live in
`ansible/inventory/group_vars/devboxes.yml`. OS packages use `state: present`:
reapply does not perform a system upgrade. Change pins deliberately, run syntax
and check, apply, verify, then reapply. Claude auto-updates are disabled in the
managed shell setup to retain the chosen version.

Neovim keeps the existing plugin-free configuration. The existing installer
owns Bash/tmux/Neovim symlinks and configuration backups. The standard Ubuntu
`.profile` was reviewed on the initial host; its `~/bin`/`~/.local/bin` PATH
behavior is retained. On another existing machine review custom `.profile`
behavior before applying. Managed blocks in `.bashrc.local` and
`.bash_profile.local` add mise, completions, and the Secret Service session bus.
Other local overrides remain yours. `home/.gitconfig` supplies your author,
aliases and default branch through a Git include; the box’s credential helper
and other global settings remain outside the shared file. Bash loads the
Homebrew prompt and disables remote-status fetching by default;
`DOTFILES_GIT_PROMPT=off` still selects the standalone fallback.

## Attended encrypted authentication

The playbook installs GNOME Keyring and libsecret tools. It does not select a
password, unlock the keyring, copy workstation credentials, or authenticate
accounts. In your own SSH terminal:

```bash
ssh aks-hertzner
bash -l
devbox-keyring
devbox-github-login
```

Choose a nonempty keyring password on first use, then use it to unlock the
encrypted keyring on later sessions. Enter it only at the hidden terminal
prompt. The unlock helper tests Secret Service storage with a nonsecret probe
and removes that probe. Keep the SSH session open during attended setup; if the
user session ends or the machine restarts, unlock again. Do not run these
commands with shell tracing or session recording.

The GitHub helper checks storage before starting device/browser login and
requires `gh auth status` to confirm keyring storage before configuring the
HTTPS Git helper. It never accepts `--insecure-storage`. If storage fails, fix
or unlock the keyring before trying authentication again. Never paste tokens
or keyring passwords into chat or Ansible variables.

Codex configuration explicitly requires keyring storage rather than the
plaintext/automatic fallback:

```bash
codex login --device-auth
codex login status
```

Claude's Linux subscription login uses a plaintext `.credentials.json`, so the
installed `claude` wrapper uses a newly generated subscription token retrieved
from Secret Service at process startup instead:

```bash
claude setup-token
devbox-claude-token
claude auth status
```

Generate the token on this machine and paste it only into the hidden
`devbox-claude-token` prompt. `setup-token` displays the token in your terminal;
do not record/share its output. Do not use `claude auth login` or `/login` with
this storage policy. The wrapper rejects the former; entering `/login` inside
Claude is an explicit change to this policy and can persist plaintext. It
allows version/help/setup-token commands without authentication and otherwise
fails if the keyring token is unavailable. Existing environment API keys or
provider configuration can override the subscription token; keep those unset
when verifying subscription authentication.

No plaintext credentials file is needed for these workflows. A keyring failure
pauses authentication; it is not permission to use a plaintext fallback.

## Clone and reconcile owned repositories

After GitHub login and while its keyring is unlocked, from the controller:

```bash
./devbox repos
./devbox repos  # expect existing=eligible, cloned=0, failed=0
```

The script checks the authenticated identity, follows every API page, filters
the exact owner, and includes private/public, forked, and archived repositories.
It creates full working clones under `~/src/<repo>`. It never pulls, resets,
cleans, deletes, or renames existing working copies. Existing directories must
be real repositories with matching GitHub origins; SSH and HTTPS spellings of
the same repository are equivalent. Collisions fail visibly and preserve work.
Partial failures do not prevent attempts on remaining repositories. Aggregate
counts are printed; private repository names are not committed to inventory.

Ansible suppresses repository command output because names may be private. If
it fails, run `python3 ~/src/dotfiles/scripts/clone_repos.py --owner amitsaraff`
in your own remote terminal to see per-repository diagnostics without exposing
them to public logs. A failed clone is retained for inspection; reconcile its
directory explicitly before retrying.

## Personal agent skills and CDP CLI

The `skills` role installs the personal skills from `~/src/skills` using that
repository's conflict-safe installer. One editable copy is shared through
`~/.agents/skills`, `~/.codex/skills`, `~/.claude/skills`, and `~/.copilot/skills`.
Existing system/plugin skills are preserved. Start a new agent session to
discover newly installed skills. App/plugin skills from the Mac are not copied.

```bash
./devbox skills
```

On a new box, `./devbox apply` prepares the tools first. After attended GitHub
login, `./devbox repos` clones the owned repositories and then installs these
skills automatically. If the skills checkout is absent, the normal apply reports
the required next step rather than trying to authenticate unattended.

Skills installation requires the reviewed revision in
`ansible/inventory/group_vars/devboxes.yml` and a clean source checkout. It runs
the local safety scanner before linking, and the repository's full check after
linking. The initial revision has no blockers and three reviewed warnings: two
flag explicit prohibitions on transferring test fixture data, and one flags
browser artifact guidance that already uses a temporary output directory.
Review new scan results before changing the pin; the role never pulls or resets
local edits. Skill code and settings stay in their own repository.

The role also builds and installs `cdp` and its guide from the reviewed
`~/src/cdp-cli` revision using `mise exec -- make install`, then verifies the
installed build identity and `--browser-mode` support. Reapply skips the build
when that revision is already installed. The install leaves browser attachment
state, services and scheduled jobs alone.

Google Chrome Stable is installed by the `browser` role from Google's signed
APT repository. `./devbox apply` includes both browser and skill roles;
`./devbox verify` checks Chrome, CDP and the installed skill links. Browser
profiles, headed sessions, provider logins and project-specific Playwright
browser bundles are separate from package installation. Initial headless
readiness is checked explicitly with CDP's managed-headless setup commands.

## Optional project tools

```bash
./devbox notebooks
```

This installs isolated JupyterLab. ML packages, Mojo, model downloads, project browser
bundles and repository dependency environments remain on demand. Use each
project's manifests (`uv sync`, `pdm sync`, `pixi install`, `npm ci`, etc.) rather
than globally installing its dependencies. Use a project's pinned Playwright
to install browser binaries and additional WebKit/Firefox dependencies when
needed; browser downloads are not part of baseline provisioning.

## Recovery and revocation

The dotfiles installer prints its backup directory and exact restore command.
Use `restore.sh --dry-run` first; restore refuses to overwrite subsequent edits.
Provisioning does not automatically uninstall OS packages or roll back runtime
versions. Prior downloaded runtime artifacts are retained.

Source deployment records hashes outside the checkout under
`~/.local/state/devbox/source.json`. It preflights every destination and refuses
to overwrite edits since its previous deployment (or since Git HEAD on first
deployment). Reconcile target edits back into the controller intentionally;
do not delete its state to force an overwrite. No target source files are
automatically deleted when removed from the controller.

For a retired/lost host, revoke its GitHub CLI authorization at GitHub, its
ChatGPT/Codex sessions through your account controls, and its Claude token via
Anthropic account controls. Local removal alone does not revoke remote access.
On an accessible box use `gh auth logout --hostname github.com`, `codex logout`,
and `secret-tool clear application devbox service claude-oauth` while the
keyring is unlocked, followed by the provider-side revocation as appropriate.

## Implementation references

- [Docker Ubuntu installation](https://docs.docker.com/engine/install/ubuntu/)
- [mise official installation](https://mise.jdx.dev/installing-mise.html) and [shell activation](https://mise.jdx.dev/shell-setup.html)
- [uv Python management](https://docs.astral.sh/uv/guides/install-python/)
- [GitHub CLI login and storage behavior](https://cli.github.com/manual/gh_auth_login)
- [Codex authentication/storage](https://learn.chatgpt.com/docs/auth)
- [Claude authentication/storage and setup-token](https://code.claude.com/docs/en/authentication)
- [GNOME Keyring daemon](https://wiki.gnome.org/Projects/GnomeKeyring/RunningDaemon)

- [Homebrew Linux installation](https://docs.brew.sh/Homebrew-on-Linux)
- [Homebrew bash-git-prompt formula](https://formulae.brew.sh/formula/bash-git-prompt)
