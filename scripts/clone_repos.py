#!/usr/bin/env python3
"""Clone all owned repositories; never fetch/reset/clean an existing checkout."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def repository_identity(url):
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?", url)
    return tuple(s.lower() for s in match.groups()) if match else None


def run(args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def clone_one(repo, root, clone=None):
    owner, name = repo["owner"]["login"], repo["name"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in {".", ".."}:
        raise RuntimeError("Invalid repository name")
    target = root / name
    if target.is_symlink():
        raise RuntimeError(f"Symlink collision: {name}")
    if target.exists():
        if not (target / ".git").exists():
            raise RuntimeError(f"Non-repository collision: {name}")
        # A nested path must not accidentally resolve to a containing repository.
        top = Path(run(["git", "-C", str(target), "rev-parse", "--show-toplevel"])).resolve()
        if top != target.resolve():
            raise RuntimeError(f"Invalid working copy: {name}")
        origin = run(["git", "-C", str(target), "remote", "get-url", "origin"])
        if repository_identity(origin) != (owner.lower(), name.lower()):
            raise RuntimeError(f"Origin mismatch, left untouched: {name}")
        return "existing"
    # git clone only into a missing path; failed clones are retained/reported.
    (clone or (lambda url, dest: subprocess.run(
        ["git", "clone", "--", url, str(dest)], check=True, capture_output=True, text=True
    )))(repo["clone_url"], target)
    return "cloned"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--root", type=Path, default=Path.home() / "src")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+", args.owner):
        parser.error("Invalid owner")
    if args.root.is_symlink():
        sys.exit("Source root must not be a symlink")
    # Do not let environment credentials silently substitute for machine login.
    if os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"):
        sys.exit("Use attended machine authentication, not an environment token")
    auth = subprocess.run(["gh", "auth", "status", "--hostname", "github.com"], capture_output=True, text=True)
    if auth.returncode or "(keyring)" not in auth.stdout + auth.stderr:
        sys.exit("Unlock the keyring and complete devbox-github-login before cloning")
    identity = run(["gh", "api", "--hostname", "github.com", "user", "--jq", ".login"])
    if identity.lower() != args.owner.lower():
        sys.exit("Authenticated GitHub identity does not match requested owner")
    # One JSON record per line works with Ubuntu's older gh as well as new gh;
    # --paginate follows every page without requiring the newer --slurp flag.
    records = run(["gh", "api", "--hostname", "github.com", "--paginate", "--jq", ".[] | @json", "/user/repos?affiliation=owner&per_page=100"])
    repos = [json.loads(line) for line in records.splitlines() if line.strip()]
    repos = [r for r in repos if r["owner"]["login"].lower() == args.owner.lower()]
    args.root.mkdir(parents=True, exist_ok=True)
    summary = {"eligible": len(repos), "existing": 0, "cloned": 0, "failed": 0}
    for repo in repos:
        try:
            summary[clone_one(repo, args.root)] += 1
        except (RuntimeError, OSError, subprocess.SubprocessError) as error:
            summary["failed"] += 1
            # Never print clone stderr: URLs/credential helper diagnostics may leak.
            print(f"Repository {repo['name']} failed: {error if isinstance(error, RuntimeError) else type(error).__name__}", file=sys.stderr)
    print(json.dumps(summary, sort_keys=True))
    return bool(summary["failed"])


if __name__ == "__main__":
    sys.exit(main())
