-- Neovim configuration

vim.cmd("filetype plugin indent on")
vim.cmd("syntax on")

local opt = vim.opt

opt.number = true
opt.ruler = true
opt.laststatus = 2
opt.showmode = true
opt.showcmd = true
opt.scrolloff = 3
opt.foldcolumn = "1"
opt.errorbells = false
opt.visualbell = false
opt.timeoutlen = 500

opt.wrap = true
opt.textwidth = 79
opt.formatoptions = "tcqrn1"
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.shiftround = false
opt.listchars = { tab = "▸ ", eol = "¬" }

opt.backspace = { "indent", "eol", "start" }
opt.matchpairs:append("<:>")
opt.hidden = true

opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.showmatch = true

opt.background = "dark"
opt.backup = false
opt.writebackup = false
opt.swapfile = false
opt.modeline = false

vim.keymap.set({ "n", "v", "o" }, "<leader>l", "<cmd>set list!<CR>")
vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")
vim.keymap.set({ "n", "v" }, "/", "/\\v")
vim.keymap.set({ "n", "v", "o" }, "<leader><space>", "<cmd>let @/ = ''<CR>")
vim.keymap.set({ "n", "v", "o" }, "<leader>q", "gqip")

-- Ctrl-A + arrow in tmux enters Neovim navigation; at the split edge, cross
-- into the adjacent tmux pane. Standalone Neovim never invokes tmux.
local directions = {
    Left = { nvim = "h", tmux = "L" },
    Down = { nvim = "j", tmux = "D" },
    Up = { nvim = "k", tmux = "U" },
    Right = { nvim = "l", tmux = "R" },
}
for key, direction in pairs(directions) do
    vim.keymap.set("n", "<C-w><" .. key .. ">", function()
        local current = vim.fn.winnr()
        local target = vim.fn.winnr(direction.nvim)
        if target > 0 and target ~= current then
            vim.cmd.wincmd(direction.nvim)
        elseif vim.env.TMUX and vim.fn.executable("tmux") == 1 then
            vim.fn.system({ "tmux", "select-pane", "-" .. direction.tmux })
        end
    end, { desc = "Navigate across Neovim splits and tmux panes" })
end

-- init.local.lua is deliberately not captured or versioned.
local local_config = vim.fn.stdpath("config") .. "/init.local.lua"
if vim.fn.filereadable(local_config) == 1 then
    dofile(local_config)
end
