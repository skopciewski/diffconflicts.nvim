local config = require("diffconflicts.config")
local util = require("diffconflicts.util")

local advance_augroup = vim.api.nvim_create_augroup("diffconflicts.nvim.advance", { clear = false })

local M = {}

function M.has_conflicts()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("^<<<<<<< ") then
      return true
    end
  end
  return false
end

local function conflicted_files()
  local current = vim.api.nvim_buf_get_name(0)
  local root = util.repo_root(current) or vim.uv.cwd() or ""
  local root_esc = vim.fn.shellescape(root)
  return util.systemlist_trim("git -C " .. root_esc .. " diff --name-only --diff-filter=U")
end

local function advance_to_next_conflicted_file(current_abs_path)
  local files = conflicted_files()
  if vim.tbl_isempty(files) then
    return false
  end

  local root = util.repo_root(current_abs_path)
  if not root then
    return false
  end

  local current_rel = nil
  if current_abs_path and current_abs_path ~= "" then
    local p = vim.fn.fnamemodify(current_abs_path, ":p")
    local r = vim.fn.fnamemodify(root, ":p")
    if p:sub(1, #r + 1) == r .. "/" then
      current_rel = p:sub(#r + 2)
    end
  end

  local next_rel = nil
  if current_rel then
    for i, f in ipairs(files) do
      if f == current_rel then
        next_rel = files[i + 1]
        break
      end
    end
  end
  next_rel = next_rel or files[1]

  local next_abs = vim.fn.fnamemodify(root .. "/" .. next_rel, ":p")
  if current_abs_path and vim.fn.fnamemodify(current_abs_path, ":p") == next_abs then
    return false
  end

  vim.cmd.edit(vim.fn.fnameescape(next_abs))

  vim.schedule(function()
    pcall(vim.cmd, "DiffConflicts")
  end)

  return true
end

local function detect_conflict_style()
  if config.values.vcs ~= "git" then
    return "diff"
  end
  local result = vim.fn.system("git config --get merge.conflictStyle")
  return result:gsub("%s$", "")
end

local function setup_right_pane(orig_buf, orig_ft)
  vim.cmd("rightb vsplit")
  vim.cmd("enew")
  local right_win = vim.api.nvim_get_current_win()
  local right_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, vim.api.nvim_buf_get_lines(orig_buf, 0, -1, false))
  vim.cmd("silent file RCONFL")
  vim.bo.filetype = orig_ft
  vim.cmd("diffthis")

  vim.cmd("silent! g/^<<<<<<< /,/^=======\\r\\?$/d")
  vim.cmd("silent! g/^>>>>>>> /d")

  vim.bo.modifiable = false
  vim.bo.readonly = true
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "delete"
  vim.bo.buflisted = false

  return right_win, right_buf
end

local function setup_left_pane(left_win, conflict_style)
  vim.api.nvim_set_current_win(left_win)
  vim.cmd("diffthis")

  if conflict_style:lower() == "diff3" or conflict_style:lower() == "zdiff3" then
    vim.cmd("silent! g/^||||||| \\?/,/^>>>>>>> /d")
  else
    vim.cmd("silent! g/^=======\\r\\?$/,/^>>>>>>> /d")
  end
  vim.cmd("silent! g/^<<<<<<< /d")

  vim.cmd("diffupdate")
end

local function register_advance_autocmd(orig_buf, left_win, right_win, right_buf)
  vim.api.nvim_clear_autocmds({ group = advance_augroup, buffer = orig_buf })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = advance_augroup,
    buffer = orig_buf,
    callback = function()
      util.close_win_if_valid(right_win)
      util.delete_buf_if_valid(right_buf)
      util.cleanup_plugin_aux_buffers(orig_buf)
      if vim.api.nvim_win_is_valid(left_win) then
        pcall(vim.api.nvim_set_current_win, left_win)
      end

      if M.has_conflicts() then
        split_conflict_markers()
        return
      end

      local current = vim.api.nvim_buf_get_name(orig_buf)
      local advanced = advance_to_next_conflicted_file(current)
      if advanced then
        return
      end

      if config.values.qol and config.values.qol.quit_on_done then
        pcall(function()
          vim.cmd("qa")
        end)
      end
    end,
  })
end

local function split_conflict_markers()
  local orig_buf = vim.api.nvim_get_current_buf()
  local orig_ft = vim.bo.filetype
  local left_win = vim.api.nvim_get_current_win()
  local conflict_style = detect_conflict_style()

  local right_win, right_buf = setup_right_pane(orig_buf, orig_ft)
  setup_left_pane(left_win, conflict_style)

  if config.values.qol and config.values.qol.advance_on_save then
    register_advance_autocmd(orig_buf, left_win, right_win, right_buf)
  end
end

function M.check_then_diff()
  if M.has_conflicts() then
    vim.cmd("redraw")
    vim.cmd("echohl WarningMsg")
    vim.cmd([[echon "Resolve conflicts leftward then save. Use :cq to abort."]])
    vim.cmd("echohl None")
    split_conflict_markers()
  else
    vim.cmd('echohl WarningMsg | echo "No conflict markers found." | echohl None')
  end
end

return M
