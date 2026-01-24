-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--
local group = vim.api.nvim_create_augroup("MatugenTransparency", { clear = true })

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  pattern = "matugen",
  callback = function()
    local set = vim.api.nvim_set_hl
    local groups = {
      "Normal",
      "NormalNC",
      "NormalFloat",
      "FloatBorder",
      "FloatTitle",
      "SignColumn",
      "EndOfBuffer",
      "LineNr",
      "CursorLineNr",
      "WinSeparator",
    }
    for _, g in ipairs(groups) do
      set(0, g, { bg = "none" })
    end
  end,
})
