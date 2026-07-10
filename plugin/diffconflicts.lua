vim.api.nvim_create_user_command("DiffConflicts", function(opts)
  require("diffconflicts").show(opts)
end, { nargs = "*", complete = "file" })

vim.api.nvim_create_user_command("DiffConflictsShowHistory", function(opts)
  require("diffconflicts").show_history(opts)
end, { nargs = "*" })

vim.api.nvim_create_user_command("DiffConflictsWithHistory", function(opts)
  require("diffconflicts").show_with_history(opts)
end, { nargs = "*", complete = "file" })
