# Dotfiles and development boxes

For provisioning or runtime/toolchain changes, read [docs/devbox.md](docs/devbox.md).
Keep package/authentication/repository provisioning in Ansible; keep the existing
configuration installer usable independently. Do not copy workstation credentials,
fall back silently to plaintext tokens, or reset/clean/pull existing target repos.

Run `./check.sh`, `python3 -m unittest discover -s tests -v`, and `./devbox syntax`
after relevant changes. Ansible check mode skips executable bootstrap/auth/clone
boundaries: validate authorized host changes with `./devbox verify` and a second
`./devbox apply`. Source deployment must preserve edits on the target; reconcile
conflicts instead of deleting deployment state. Authentication is attended; use
the encrypted-keyring procedure in the runbook.
