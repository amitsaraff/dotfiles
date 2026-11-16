#!/usr/bin/env python3
"""Archive reviewed source only, including current uncommitted implementation."""
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT_FILES = {"README.md", "AGENTS.md", ".gitignore", "install.sh", "restore.sh", "capture.sh", "check.sh", "devbox"}
SOURCE_DIRS = {"home", "lib", "scripts", "ansible", "docs", "tests"}


def archive_source(root, output):
    names = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    ).decode().split("\0")
    with tarfile.open(output, "w:gz") as tar:
        for name in sorted(set(filter(None, names))):
            rel = Path(name)
            if name not in ROOT_FILES and rel.parts[0] not in SOURCE_DIRS:
                continue
            if any(part in {".git", "__pycache__", ".venv", "node_modules"} for part in rel.parts):
                continue
            path = root / rel
            if path.is_symlink():
                raise RuntimeError(f"Refusing source symlink: {name}")
            if path.is_file():
                tar.add(path, arcname=name, recursive=False)


if __name__ == "__main__":
    archive_source(Path(sys.argv[1]).resolve(), sys.argv[2])
