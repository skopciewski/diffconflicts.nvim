local config = require("diffconflicts.config")
local diff = require("diffconflicts.diff")
local history = require("diffconflicts.history")
local match = require("diffconflicts.match")

local M = {}

M.setup = config.setup

M.show = function(opts)
  local args = (opts and opts.fargs) or {}
  local merged = args[1]
  if not merged or merged == "" then
    local argv = vim.fn.argv() or {}
    merged = argv[1]
  end
  if not merged or merged == "" then
    merged = vim.fn.getenv("MERGED")
  end
  if type(merged) == "string" and merged ~= "" then
    local cur = vim.api.nvim_buf_get_name(0)
    local merged_abs = vim.fn.fnamemodify(merged, ":p")
    local cur_abs = cur ~= "" and vim.fn.fnamemodify(cur, ":p") or ""
    if cur_abs == "" or cur_abs ~= merged_abs then
      pcall(vim.cmd.edit, vim.fn.fnameescape(merged))
    end
  end
  diff.check_then_diff()
end

M.show_history = function(opts)
  history.seed_history_bufs_from_args(opts)
  history.check_then_show_history()
end

M.show_with_history = function(opts)
  history.seed_history_bufs_from_args(opts)
  history.check_then_show_history()
  vim.cmd("1tabn")
  diff.check_then_diff()
end

return M
