#!/usr/bin/env python3
"""Overlay reviewed controller source while refusing to overwrite remote edits.

Each path must match the previous deployment, or (on first deployment) its
committed Git version. Preflight every path before writing any. Never delete.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def deploy(source, target, state_file, check=False):
    if target.is_symlink():
        raise RuntimeError("Dotfiles checkout must not be a symlink")
    previous = json.loads(state_file.read_text()) if state_file.exists() else {}
    updates, current = [], {}
    for path in sorted(source.rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Source symlinks are not supported")
        if not path.is_file():
            continue
        name = path.relative_to(source).as_posix()
        if ".git" in Path(name).parts:
            raise RuntimeError("Source must not contain .git")
        dest = target / name
        for parent in [dest, *dest.parents]:
            if parent == target.parent:
                break
            if parent.is_symlink():
                raise RuntimeError(f"Symlink in destination: {name}")
        new = path.read_bytes()
        current[name] = digest(new)
        if dest.exists():
            if not dest.is_file():
                raise RuntimeError(f"Destination type conflict: {name}")
            old = dest.read_bytes()
            # Even a coincidentally identical local edit is safe: no overwrite.
            if old == new and (dest.stat().st_mode & 0o111) == (path.stat().st_mode & 0o111):
                continue
            if name in previous:
                expected = previous[name]
            else:
                result = subprocess.run(["git", "-C", str(target), "show", f"HEAD:{name}"], capture_output=True)
                expected = digest(result.stdout) if result.returncode == 0 else None
            if digest(old) != expected:
                raise RuntimeError(f"Remote edits preserved; reconcile before deployment: {name}")
        elif name in previous:
            raise RuntimeError(f"Previously managed file removed remotely; reconcile: {name}")
        updates.append((path, dest))
    if check:
        return len(updates)
    for source_path, dest in updates:
        dest.parent.mkdir(parents=True, exist_ok=True)
        # Atomic replace avoids half-written linked configuration on interruption.
        fd, staging = tempfile.mkstemp(dir=dest.parent, prefix=".devbox-")
        os.close(fd)
        try:
            shutil.copy2(source_path, staging)
            os.replace(staging, dest)
        finally:
            if os.path.exists(staging):
                os.unlink(staging)
    if current != previous:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        fd, staging = tempfile.mkstemp(dir=state_file.parent, prefix=".deploy-state-")
        with os.fdopen(fd, "w") as stream:
            json.dump(current, stream, sort_keys=True)
        os.chmod(staging, 0o600)
        os.replace(staging, state_file)
    return len(updates)


if __name__ == "__main__":
    try:
        count = deploy(*(Path(x).absolute() for x in sys.argv[1:4]), check="--check" in sys.argv[4:])
        print(json.dumps({"changed_files": count}))
    except (RuntimeError, OSError, ValueError) as error:
        sys.exit(str(error))
