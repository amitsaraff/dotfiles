"""Sandboxed CLI regressions. Python is a test dependency, not a runtime one."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("DOTFILES_TEST_BASH", "/bin/bash")


class DotfilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "checkout with spaces"
        shutil.copytree(ROOT, self.repo, ignore=shutil.ignore_patterns(".git", "tmp", "__pycache__"))
        self.home = self.base / "home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.env = {
            "HOME": str(self.home),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "TMPDIR": str(self.base),
            "TERM": "xterm-256color",
            "DOTFILES_GIT_PROMPT": "off",
        }
        self.stub("nvim", 'printf "NVIM v0.9.5\\n"')
        self.stub("tmux", 'printf "tmux 3.2a\\n"')
        self.stub("vim", "exit 0")
        self.stub("git", "exit 1")
        self.stub("brew", "exit 0")
        self.stub("fzf", "exit 0")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def cli(self, script="install.sh", *args, success=True):
        result = subprocess.run(
            [BASH, str(self.repo / script), *args],
            env=self.env, cwd=self.repo, capture_output=True, text=True, timeout=20,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def runs(self):
        return sorted((self.home / ".dotfiles-backups").glob("*"))

    def shell(self, body):
        result = subprocess.run(
            [BASH, "--noprofile", "--norc", "-ic", body],
            env=self.env, cwd=self.home, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_fresh_install_covers_all_and_repeat_is_noop(self):
        self.cli()
        for name in [".bashrc", ".bash_profile", ".vimrc", ".tmux.conf", ".config/nvim/init.lua"]:
            target = self.home / name
            self.assertTrue(target.is_symlink(), name)
            self.assertEqual(target.resolve(), self.repo / "home" / name)
        first = self.runs()
        self.cli()
        self.assertEqual(self.runs(), first)
        self.cli("capture.sh", "--dry-run")

    def test_component_dependencies_are_scoped(self):
        self.stub("nvim", "exit 99")
        self.stub("tmux", "exit 99")
        self.cli("install.sh", "--components", "bash")
        self.assertFalse((self.home / ".tmux.conf").exists())

    def test_dependency_and_option_failures_write_nothing(self):
        for args in [
            ("--components", "typo"), ("--components", "bash,"),
            ("--components", ""), ("--conflict", "overwrite"),
            ("--components",), ("--nvim-appname", "../escape"),
            ("--components", "nvim"),
        ]:
            self.stub("nvim", 'printf "NVIM v0.8.0\\n"')
            self.cli("install.sh", *args, success=False)
            self.assertEqual(list(self.home.iterdir()), [])

    def test_missing_home_and_relative_xdg_fail_before_writes(self):
        self.env["HOME"] = str(self.base / "missing home")
        self.cli("install.sh", "--components", "bash", success=False)
        self.env["HOME"] = str(self.home)
        self.env["XDG_CONFIG_HOME"] = "relative/config"
        self.cli("install.sh", "--components", "nvim", success=False)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_dry_run_and_check_never_write(self):
        self.cli("install.sh", "--dry-run")
        self.cli("install.sh", "--check")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_conflicts_fail_before_first_write(self):
        original = self.home / ".tmux.conf"
        original.write_text("# original\n")
        self.cli(success=False)
        self.assertEqual(list(self.home.iterdir()), [original])
        self.assertEqual(original.read_text(), "# original\n")

    def test_skip_preserves_existing_file(self):
        original = self.home / ".bashrc"
        original.write_text("# original\n")
        self.cli("install.sh", "--conflict", "skip")
        self.assertEqual(original.read_text(), "# original\n")
        self.assertTrue((self.home / ".tmux.conf").is_symlink())

    def test_alternate_login_profile_is_not_silently_shadowed(self):
        (self.home / ".profile").write_text("# login setup\n")
        self.cli("install.sh", "--components", "bash", success=False)
        self.assertFalse((self.home / ".bashrc").exists())
        self.cli("install.sh", "--components", "bash", "--conflict", "skip")
        self.assertFalse((self.home / ".bash_profile").exists())

    def test_backup_and_restore_preserve_symlink_referent(self):
        external = self.base / "other manager"
        external.write_text("# owned elsewhere\n")
        (self.home / ".bashrc").symlink_to(external)
        self.cli("install.sh", "--components", "bash", "--conflict", "backup")
        run = self.runs()[0]
        self.assertTrue((run / "before/0").is_symlink())
        self.assertEqual(external.read_text(), "# owned elsewhere\n")
        self.cli("restore.sh", "--dry-run", str(run))
        self.assertEqual((self.home / ".bashrc").resolve(), self.repo / "home/.bashrc")
        self.cli("restore.sh", str(run))
        self.assertEqual((self.home / ".bashrc").resolve(), external)
        self.assertFalse((self.home / ".bash_profile").exists())
        self.cli("restore.sh", str(run))

    def test_broken_symlink_is_preserved(self):
        old = self.base / "missing"
        (self.home / ".bashrc").symlink_to(old)
        self.cli("install.sh", "--components", "bash", "--conflict", "backup")
        self.cli("restore.sh", str(self.runs()[0]))
        self.assertEqual(os.readlink(self.home / ".bashrc"), str(old))

    def test_copy_idempotency_and_unique_backups(self):
        original = self.home / ".bashrc"
        original.write_text("# first original\n")
        self.stub("date", 'printf "20000101-000000\\n"')
        self.cli("install.sh", "--components", "bash", "--copy", "--conflict", "backup")
        first = self.runs()[0]
        self.cli("install.sh", "--components", "bash", "--copy")
        self.assertEqual(len(self.runs()), 1)
        original.write_text("# later local edit\n")
        self.cli("install.sh", "--components", "bash", "--copy", "--conflict", "backup")
        second = next(run for run in self.runs() if run != first)
        self.assertEqual((first / "before/0").read_text(), "# first original\n")
        self.assertEqual((second / "before/0").read_text(), "# later local edit\n")
        self.cli("restore.sh", str(second))
        self.assertEqual(original.read_text(), "# later local edit\n")

    def test_restore_refuses_edited_targets_before_any_write(self):
        self.cli("install.sh", "--components", "bash", "--copy")
        (self.home / ".bashrc").write_text("# user edit\n")
        profile = (self.home / ".bash_profile").read_bytes()
        self.cli("restore.sh", str(self.runs()[0]), success=False)
        self.assertEqual((self.home / ".bash_profile").read_bytes(), profile)
        self.assertEqual((self.home / ".bashrc").read_text(), "# user edit\n")

    def test_failure_during_install_restores_prior_changes(self):
        (self.home / ".bashrc").write_text("# original\n")
        # Fail staging the second component, after the first has been installed.
        self.stub("ln", 'case "$3" in */installed/1) exit 7 ;; esac\nexec /bin/ln "$@"')
        self.cli("install.sh", "--components", "bash", "--conflict", "backup", success=False)
        self.assertEqual((self.home / ".bashrc").read_text(), "# original\n")
        self.assertFalse((self.home / ".bash_profile").exists())
        self.assertTrue((self.runs()[0] / "restored").exists())

    def test_xdg_and_isolated_neovim_install_and_capture(self):
        config = self.base / "xdg config"
        config.mkdir()
        self.env["XDG_CONFIG_HOME"] = str(config)
        (config / "nvim").mkdir()
        (config / "nvim/init.lua").write_text("-- unrelated config\n")
        self.cli("install.sh", "--components", "nvim", "--nvim-appname", "personal-nvim")
        target = config / "personal-nvim/init.lua"
        self.assertTrue(target.is_symlink())
        self.cli("capture.sh", "--components", "nvim", "--nvim-appname", "personal-nvim", "--dry-run")
        self.assertEqual((config / "nvim/init.lua").read_text(), "-- unrelated config\n")
        self.cli("restore.sh", str(self.runs()[0]))
        self.assertFalse(target.exists())

    def test_existing_init_vim_is_not_broken(self):
        directory = self.home / ".config/nvim"
        directory.mkdir(parents=True)
        (directory / "init.vim").write_text("set number\n")
        self.cli("install.sh", "--components", "nvim", success=False)
        self.cli("install.sh", "--components", "nvim", "--conflict", "skip")
        self.assertFalse((directory / "init.lua").exists())

    def test_parent_directory_symlinks_are_never_written_through(self):
        outside = self.base / "outside config"
        outside.mkdir()
        (self.home / ".config").symlink_to(outside, target_is_directory=True)
        self.cli("install.sh", "--components", "nvim", success=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_repository_symlink_sources_are_rejected(self):
        path = self.repo / "home/.bashrc"
        path.unlink()
        outside = self.base / "outside"
        outside.write_text("# private data\n")
        path.symlink_to(outside)
        self.cli("install.sh", "--components", "bash", success=False)
        self.cli("capture.sh", "--components", "bash", success=False)
        self.assertEqual(outside.read_text(), "# private data\n")

    def test_integration_prints_snippets_without_writes(self):
        existing = self.home / ".bashrc"
        existing.write_text("# existing\n")
        result = self.cli("install.sh", "--integrate")
        self.assertIn("NVIM_APPNAME=personal-nvim", result.stdout)
        self.assertIn("tmux -L personal", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [existing])

    def test_capture_scans_every_file_before_copying_any(self):
        before = (self.repo / "home/.bashrc").read_bytes()
        (self.home / ".bashrc").write_text("# harmless changed file\n")
        (self.home / ".bash_profile").write_text("export AWS_ACCESS_KEY_ID=" + "AKIA" + "A" * 16 + "\n")
        result = self.cli("capture.sh", "--components", "bash", success=False)
        self.assertNotIn("AKIA" + "A" * 16, result.stderr)
        self.assertEqual((self.repo / "home/.bashrc").read_bytes(), before)

    def test_capture_rejects_provider_and_machine_markers(self):
        cases = [
            "AKIA" + "A" * 16, "ASIA" + "A" * 16,
            "github_" + "pat_" + "x" * 40,
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "export SERVICE_PASSWORD=placeholder", "/Users/" + "example/private/bin",
            "/home/" + "example/private/bin", "https://user:placeholder@example.invalid",
        ]
        for text in cases:
            (self.home / ".vimrc").write_text(text + "\n")
            self.cli("capture.sh", "--components", "vim", success=False)

    def test_capture_fails_closed_on_grep_error(self):
        (self.home / ".vimrc").write_text("set number\n")
        before = (self.repo / "home/.vimrc").read_bytes()
        self.stub("grep", "exit 2")
        self.cli("capture.sh", "--components", "vim", success=False)
        self.assertEqual((self.repo / "home/.vimrc").read_bytes(), before)

    def test_private_patterns_are_external_and_fail_closed(self):
        patterns = self.base / "patterns.local"
        patterns.write_text("# private hosts\nexample-corp\n")
        self.env["DOTFILES_PRIVATE_PATTERNS_FILE"] = str(patterns)
        (self.home / ".vimrc").write_text('" example-corp\n')
        self.cli("capture.sh", "--components", "vim", success=False)
        patterns.write_text("[\n")
        self.cli("capture.sh", "--components", "vim", success=False)

    def test_capture_dry_run_and_actual_update(self):
        destination = self.repo / "home/.vimrc"
        before = destination.read_bytes()
        (self.home / ".vimrc").write_text("set number\n")
        self.cli("capture.sh", "--components", "vim", "--dry-run")
        self.assertEqual(destination.read_bytes(), before)
        self.cli("capture.sh", "--components", "vim")
        self.assertEqual(destination.read_text(), "set number\n")

    def test_prompt_branch_data_does_not_execute(self):
        body = f"""
. '{self.repo}/home/.bashrc'
_dotfiles_git_branch() {{ printf '%s' '$(printf${{IFS}}SHOULD_NOT_EXECUTE)'; }}
_dotfiles_prompt
"""
        if subprocess.check_output([BASH, "-c", 'echo "${BASH_VERSINFO[0]}"'], text=True).strip() != "3":
            output = self.shell(body + 'printf "%s\\n" "${PS1@P}"')
        else:
            # Bash 3.2 has no @P transformation. Render the prompt in a PTY.
            import pty
            master, slave = pty.openpty()
            try:
                process = subprocess.Popen(
                    [BASH, "--noprofile", "--norc", "-i"], stdin=slave,
                    stdout=slave, stderr=slave, env=self.env, cwd=self.home,
                )
                os.close(slave)
                os.write(master, (body + "\nexit\n").encode())
                chunks = []
                while True:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
                process.wait(timeout=10)
                output = b"".join(chunks).decode(errors="replace")
            finally:
                os.close(master)
            self.assertEqual(process.returncode, 0)
        self.assertIn("[$(printf${IFS}SHOULD_NOT_EXECUTE)]", output)

    def test_hooks_are_idempotent_and_arrays_preserved(self):
        source = f". '{self.repo}/home/.bashrc'"
        output = self.shell(f"PROMPT_COMMAND='true'; {source}; {source}; printf '%s\\n' \"$PROMPT_COMMAND\"")
        self.assertEqual(output.count("_dotfiles_prompt"), 1)
        self.assertEqual(output.count("_dotfiles_history_sync"), 1)
        output = self.shell(
            f"PROMPT_COMMAND=('echo FIRST' 'echo SECOND'); {source}; {source}; "
            'printf "%s\\n" "${PROMPT_COMMAND[@]}"'
        )
        self.assertEqual(output.splitlines(), [
            "_dotfiles_prompt", "echo FIRST", "echo SECOND", "_dotfiles_history_sync",
        ])

    def test_macos_detection_and_path_output(self):
        source = f". '{self.repo}/home/.bashrc'"
        output = self.shell(f"OSTYPE=darwin-test; {source}; alias ls; alias df")
        self.assertIn("ls -hG", output)
        self.assertIn("df -kh", output)
        output = self.shell(f"{source}; PATH=/a:/b; _dotfiles_print_path \"$PATH\"")
        self.assertEqual(output, "/a\n/b\n")

    def test_local_shell_overrides_are_loaded_but_not_captured(self):
        (self.home / ".bashrc.local").write_text("LOCAL_MARKER=yes\n")
        output = self.shell(f". '{self.repo}/home/.bashrc'; printf '%s' \"$LOCAL_MARKER\"")
        self.assertEqual(output, "yes")
        self.cli("install.sh", "--components", "bash")
        self.cli("capture.sh", "--components", "bash")
        self.assertFalse((self.repo / "home/.bashrc.local").exists())


if __name__ == "__main__":
    unittest.main()
