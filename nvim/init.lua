vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"

vim.schedule(function()
  require "mappings"
end)


-- Restore cursor to last known position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Restore cursor position",
  callback = function(event)
    -- Skip certain filetypes (e.g., commit messages)
    local ignore = { "gitcommit", "gitrebase", "svn", "hgcommit" }
    if vim.tbl_contains(ignore, vim.bo[event.buf].filetype) then
      return
    end

    -- Get the '"' mark (last cursor position)
    local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(event.buf)

    if mark[1] > 0 and mark[1] <= lcount then
      -- pcall to avoid errors in weird buffers
      pcall(vim.api.nvim_win_set_cursor, 0, { mark[1], mark[2] })
    end
  end,
})

