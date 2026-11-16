"""Actual application smoke checks with private homes and a private tmux socket."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-runtime-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        # No user tokens, shell hooks, plugin configs or existing servers.
        self.env = {
            "HOME": str(self.home),
            "PATH": "/usr/bin:/bin",
            "TERM": "xterm-256color",
            "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_DATA_HOME": str(self.home / "data"),
            "XDG_STATE_HOME": str(self.home / "state"),
            "XDG_CACHE_HOME": str(self.home / "cache"),
        }

    def tool(self, name):
        path = shutil.which(name)
        if not path:
            self.skipTest(f"{name} not installed")
        return path

    def run_tool(self, args):
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_vim_startup_local_override_and_fullscreen_guard(self):
        vim = self.tool("vim")
        (self.home / ".vimrc.local").write_text("let g:local_marker = 1\n")
        check = """
if !get(g:, 'local_marker', 0) || !&number
  cquit 1
endif
if !exists('+fullscreen') && !empty(maparg('<F1>', 'n'))
  cquit 1
endif
qa!
"""
        script = self.home / "check.vim"
        script.write_text(check)
        self.run_tool([vim, "-Nu", str(ROOT / "home/.vimrc"), "-n", "-i", "NONE", "-es", "-S", str(script)])

    def test_neovim_startup_and_cross_split_navigation(self):
        nvim = self.tool("nvim")
        directory = self.home / "config/nvim"
        directory.mkdir(parents=True)
        (directory / "init.local.lua").write_text('vim.g.local_marker = "loaded"\n')
        check = """
assert(vim.g.local_marker == "loaded")
assert(vim.opt.number:get())
vim.cmd("vsplit")
vim.cmd("wincmd l")
local navigate = vim.fn.maparg("<C-w><Left>", "n", false, true).callback
assert(type(navigate) == "function")
navigate()
assert(vim.fn.winnr() == 1)
-- No tmux command may run at the edge in standalone Neovim.
local called = false
vim.fn.system = function(args)
    called = args
    return ""
end
vim.env.TMUX = nil
navigate()
assert(called == false)
-- In tmux, the same mapping crosses the pane boundary using argument arrays.
vim.env.TMUX = "test-only"
vim.fn.executable = function() return 1 end
navigate()
assert(vim.deep_equal(called, { "tmux", "select-pane", "-L" }))
"""
        script = self.home / "check.lua"
        script.write_text(check)
        command = (
            "lua local ok, err = pcall(dofile, "
            + repr(str(script))
            + "); if not ok then print(err); vim.cmd('cquit 1') end"
        )
        self.run_tool([nvim, "--headless", "-u", str(ROOT / "home/.config/nvim/init.lua"),
                       "-i", "NONE", "-c", command, "+qa!"])

    def test_tmux_startup_local_override_and_navigation_bindings(self):
        tmux = self.tool("tmux")
        socket = str(self.home / "tmux.sock")
        (self.home / ".tmux.conf.local").write_text('set -g @test-local "loaded"\n')
        prefix = [tmux, "-S", socket]
        self.addCleanup(lambda: subprocess.run(prefix + ["kill-server"], env=self.env, capture_output=True))
        self.run_tool(prefix + ["-f", str(ROOT / "home/.tmux.conf"),
                                "new-session", "-d", "-s", "audit", "/bin/sleep 15"])
        self.assertEqual(self.run_tool(prefix + ["show-options", "-gv", "prefix"]).stdout.strip(), "C-a")
        bindings = self.run_tool(prefix + ["list-keys", "-T", "prefix", "Left"]).stdout
        self.assertIn("nvim", bindings)
        self.assertIn("select-pane -L", bindings)
        # if-shell loads local overrides asynchronously.
        for _ in range(20):
            result = subprocess.run(prefix + ["show-options", "-gv", "@test-local"],
                                    env=self.env, capture_output=True, text=True)
            if result.returncode == 0:
                break
            time.sleep(0.05)
        self.assertEqual(result.stdout.strip(), "loaded")


if __name__ == "__main__":
    unittest.main()
