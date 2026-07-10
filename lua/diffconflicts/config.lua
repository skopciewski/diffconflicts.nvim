local M = {}

M.defaults = {
  vcs = "git",
  qol = {
    advance_on_save = true,
    quit_on_done = true,
  },
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", M.values, opts or {})
end

return M
