local M = {}

function M.close_win_if_valid(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

function M.delete_buf_if_valid(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

function M.is_plugin_aux_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr) or ""
  local tail = vim.fn.fnamemodify(name, ":t")
  if tail == "RCONFL" then
    return true
  end
  if tail == "BASE" or tail == "LOCAL" or tail == "REMOTE" then
    return true
  end
  return false
end

function M.cleanup_plugin_aux_buffers(keep_buf)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= keep_buf and vim.api.nvim_buf_is_valid(b) and M.is_plugin_aux_buffer(b) then
      M.delete_buf_if_valid(b)
    end
  end
end

function M.systemlist_trim(cmd)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return vim.tbl_filter(function(s)
    return s and s ~= ""
  end, out)
end

function M.repo_root_from_marker(marker, path)
  if not path or path == "" then
    return nil
  end
  local start = vim.fn.fnamemodify(path, ":p:h")
  local found = vim.fs.find(marker, { upward = true, path = start })
  if not found or #found == 0 then
    return nil
  end
  local marker_path = vim.fn.fnamemodify(found[1], ":p"):gsub("/+$", "")
  return vim.fn.fnamemodify(marker_path, ":h")
end

function M.repo_root(path)
  return M.repo_root_from_marker(".git", path)
end

function M.open_file_safe(path)
  if path and path ~= "" then
    return pcall(vim.cmd.edit, vim.fn.fnameescape(path))
  end
  return false
end

return M
