"""Exercise work-preservation boundaries using real isolated Git repositories."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


clone = module("clone_repos")
deploy = module("deploy_source")
source_archive = module("source_archive")


class DevboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = {"name": "project", "owner": {"login": "owner"}, "clone_url": "https://github.com/owner/project.git"}

    def git(self, directory, *args):
        return subprocess.check_output(["git", "-C", str(directory), *args], stderr=subprocess.PIPE, text=True).strip()

    def init(self, directory):
        directory.mkdir(parents=True)
        self.git(directory, "init", "-q")
        self.git(directory, "config", "user.email", "test@example.invalid")
        self.git(directory, "config", "user.name", "Test")

    def test_existing_dirty_checkout_untouched_and_ssh_origin_accepted(self):
        path = self.root / "project"
        self.init(path)
        self.git(path, "remote", "add", "origin", "git@github.com:owner/project.git")
        (path / "work").write_text("uncommitted work")
        before = self.git(path, "status", "--porcelain")
        self.assertEqual(clone.clone_one(self.repo, self.root), "existing")
        self.assertEqual(self.git(path, "status", "--porcelain"), before)
        self.assertEqual((path / "work").read_text(), "uncommitted work")

    def test_origin_and_directory_collisions_preserved(self):
        path = self.root / "project"
        self.init(path)
        self.git(path, "remote", "add", "origin", "https://github.com/other/project.git")
        with self.assertRaisesRegex(RuntimeError, "Origin mismatch"):
            clone.clone_one(self.repo, self.root)
        self.assertIn("other", self.git(path, "remote", "get-url", "origin"))

    def test_missing_repo_is_full_clone_from_real_local_fixture(self):
        upstream = self.root / "upstream"
        self.init(upstream)
        (upstream / "work").write_text("one")
        self.git(upstream, "add", "work")
        self.git(upstream, "commit", "-qm", "first")
        (upstream / "work").write_text("two")
        self.git(upstream, "commit", "-qam", "second")
        fixture = lambda url, dest: subprocess.run(["git", "clone", "--no-local", str(upstream), str(dest)], check=True, capture_output=True)
        self.assertEqual(clone.clone_one(self.repo, self.root, fixture), "cloned")
        self.assertEqual(self.git(self.root / "project", "rev-list", "--count", "HEAD"), "2")

    def test_clone_symlink_collision_rejected(self):
        (self.root / "project").symlink_to(self.root / "elsewhere")
        with self.assertRaisesRegex(RuntimeError, "Symlink"):
            clone.clone_one(self.repo, self.root)

    def prepare_deployment(self):
        source, target, state = self.root / "source", self.root / "target", self.root / "state.json"
        source.mkdir()
        self.init(target)
        (target / "config").write_text("original")
        self.git(target, "add", ".")
        self.git(target, "commit", "-qm", "original")
        (source / "config").write_text("managed")
        return source, target, state

    def test_deployment_converges_and_preserves_later_remote_edits(self):
        source, target, state = self.prepare_deployment()
        self.assertEqual(deploy.deploy(source, target, state), 1)
        self.assertEqual(deploy.deploy(source, target, state), 0)
        (target / "config").write_text("remote work")
        (source / "new").write_text("must not be deployed before preflight")
        with self.assertRaisesRegex(RuntimeError, "Remote edits"):
            deploy.deploy(source, target, state)
        self.assertFalse((target / "new").exists())
        self.assertEqual((target / "config").read_text(), "remote work")

    def test_first_deployment_refuses_uncommitted_target_edits(self):
        source, target, state = self.prepare_deployment()
        (target / "config").write_text("existing local work")
        with self.assertRaisesRegex(RuntimeError, "Remote edits"):
            deploy.deploy(source, target, state)
        self.assertFalse(state.exists())

    def test_destination_symlink_parent_cannot_escape(self):
        source, target, state = self.prepare_deployment()
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        (target / "nested").symlink_to(elsewhere)
        (source / "nested").mkdir()
        (source / "nested/secret").write_text("no escape")
        with self.assertRaisesRegex(RuntimeError, "Symlink"):
            deploy.deploy(source, target, state)
        self.assertFalse((elsewhere / "secret").exists())

    def test_deploy_check_does_not_write(self):
        source, target, state = self.prepare_deployment()
        self.assertEqual(deploy.deploy(source, target, state, check=True), 1)
        self.assertEqual((target / "config").read_text(), "original")
        self.assertFalse(state.exists())

    def test_source_archive_includes_new_code_but_excludes_private_state(self):
        repo = self.root / "controller"
        self.init(repo)
        (repo / ".gitignore").write_text(".env\n*.local\n")
        (repo / "README.md").write_text("source")
        (repo / "scripts").mkdir()
        (repo / "scripts/new.py").write_text("print('uncommitted implementation')")
        (repo / ".env").write_text("private fixture")
        (repo / "scripts/private.local").write_text("private fixture")
        archive = self.root / "source.tar.gz"
        source_archive.archive_source(repo, archive)
        with tarfile.open(archive) as stream:
            names = set(stream.getnames())
        self.assertIn("scripts/new.py", names)
        self.assertNotIn(".env", names)
        self.assertNotIn("scripts/private.local", names)
        self.assertFalse(any(name.startswith(".git/") for name in names))

    def test_owner_pagination_and_partial_failure_with_real_clone(self):
        upstream = self.root / "upstream"
        self.init(upstream)
        (upstream / "work").write_text("fixture")
        self.git(upstream, "add", ".")
        self.git(upstream, "commit", "-qm", "fixture")
        src = self.root / "src"
        self.init(src / "collision")
        self.git(src / "collision", "remote", "add", "origin", "https://github.com/other/collision.git")
        repos = [
            [{"name": "collision", "owner": {"login": "owner"}, "clone_url": str(upstream)},
             {"name": "excluded", "owner": {"login": "organization"}, "clone_url": str(upstream)}],
            [{"name": "private-fork", "owner": {"login": "owner"}, "clone_url": str(upstream), "private": True, "fork": True, "archived": True}],
        ]
        fakebin = self.root / "bin"
        fakebin.mkdir()
        gh = fakebin / "gh"
        gh.write_text("#!/usr/bin/env python3\nimport json,sys\n"
                      "if 'auth' in sys.argv: print('github.com (keyring)')\n"
                      "elif 'user' in sys.argv: print('owner')\n"
                      "else:\n assert '--paginate' in sys.argv and '--jq' in sys.argv\n"
                      f" for page in {repos!r}:\n  for repo in page: print(json.dumps(repo))\n")
        gh.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = str(fakebin) + os.pathsep + env["PATH"]
        env.pop("GH_TOKEN", None)
        env.pop("GITHUB_TOKEN", None)
        result = subprocess.run([sys.executable, str(ROOT / "scripts/clone_repos.py"),
                                 "--owner", "owner", "--root", str(src)],
                                env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout), {"eligible": 2, "existing": 0, "cloned": 1, "failed": 1})
        self.assertFalse((src / "excluded").exists())
        self.assertEqual((src / "private-fork/work").read_text(), "fixture")
        self.assertIn("other", self.git(src / "collision", "remote", "get-url", "origin"))

    def test_plaintext_authentication_is_rejected_before_repository_mutation(self):
        fakebin = self.root / "bin"
        fakebin.mkdir()
        gh = fakebin / "gh"
        gh.write_text("#!/bin/sh\nprintf '%s\\n' 'Logged in (configuration file)'\n")
        gh.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = str(fakebin) + os.pathsep + env["PATH"]
        env.pop("GH_TOKEN", None)
        env.pop("GITHUB_TOKEN", None)
        src = self.root / "src"
        result = subprocess.run([sys.executable, str(ROOT / "scripts/clone_repos.py"),
                                 "--owner", "owner", "--root", str(src)],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("keyring", result.stderr)
        self.assertFalse(src.exists())

    def test_shared_git_config_preserves_machine_helper_and_sets_new_branch(self):
        home = self.root / "git-home"
        home.mkdir()
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["XDG_CONFIG_HOME"] = str(home / ".config")
        env.pop("GIT_CONFIG_GLOBAL", None)
        env.pop("GIT_CONFIG_SYSTEM", None)
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        def git(*args):
            return subprocess.check_output(["git", *args], env=env, text=True, stderr=subprocess.PIPE).strip()
        git("config", "--global", "credential.https://github.com.helper", "machine-helper")
        git("config", "--global", "--add", "include.path", str(ROOT / "home/.gitconfig"))
        self.assertEqual(git("config", "--global", "--get", "credential.https://github.com.helper"), "machine-helper")
        self.assertEqual(git("config", "--global", "--includes", "--get", "alias.co"), "!echo 'git checkout' && git checkout")
        work = home / "work"
        git("init", "-q", str(work))
        self.assertEqual(git("-C", str(work), "symbolic-ref", "--short", "HEAD"), "main")


if __name__ == "__main__":
    unittest.main()
