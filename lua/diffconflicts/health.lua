local M = {}

function M.check()
  vim.health.start("diffconflicts")

  if vim.fn.has("nvim-0.10") == 0 then
    vim.health.error("Neovim 0.10+ is required")
    return
  end
  local version_output = vim.fn.execute("version")
  local version = version_output:match("NVIM v(%S+)") or "unknown"
  vim.health.ok("Neovim version " .. version)

  if vim.fn.executable("git") == 0 then
    vim.health.warn("git not found in PATH (required for git mergetool)")
  else
    local version = vim.fn.systemlist("git --version")[1] or ""
    vim.health.ok("git: " .. version)
  end
end

return M
