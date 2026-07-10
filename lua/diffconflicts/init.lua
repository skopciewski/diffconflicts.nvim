local M = {}

local config = {
  vcs = "git",
  commands = {
    diff_conflicts = "DiffConflicts",
    show_history = "DiffConflictsShowHistory",
    with_history = "DiffConflictsWithHistory",
  },
  qol = {
    advance_on_save = true,
    quit_on_done = true,
  },
}

local advance_augroup = vim.api.nvim_create_augroup("diffconflicts.nvim.advance", { clear = false })

local function close_win_if_valid(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

local function delete_buf_if_valid(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

local function is_plugin_aux_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr) or ""
  local tail = vim.fn.fnamemodify(name, ":t")
  if tail == "RCONFL" then
    return true
  end
  if tail == "BASE" or tail == "LOCAL" or tail == "REMOTE" then
    return true
  end
  if tail:find("^~base%.$") or tail:find("^~local%.$") or tail:find("^~other%.$") then
    return true
  end
  return false
end

local function cleanup_plugin_aux_buffers(keep_buf)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= keep_buf and vim.api.nvim_buf_is_valid(b) and is_plugin_aux_buffer(b) then
      delete_buf_if_valid(b)
    end
  end
end

local function match_history_role(tail, role)
  local tu = (tail or ""):upper()
  local ru = (role or ""):upper()
  if tu == ru then
    return true
  end
  local delim = "[%._%-_]"
  if tu:match("^" .. ru .. delim) then
    return true
  end
  if tu:match(delim .. ru .. "$") then
    return true
  end
  if tu:match(delim .. ru .. delim) then
    return true
  end
  return false
end

local function systemlist_trim(cmd)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return vim.tbl_filter(function(s)
    return s and s ~= ""
  end, out)
end

local function repo_root_from_marker(marker, path)
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

local function repo_root(path)
  local marker = config.vcs == "hg" and ".hg" or ".git"
  return repo_root_from_marker(marker, path)
end

local function conflicted_files()
  local current = vim.api.nvim_buf_get_name(0)
  local root = repo_root(current) or vim.uv.cwd() or ""
  local root_esc = vim.fn.shellescape(root)
  return systemlist_trim("git -C " .. root_esc .. " diff --name-only --diff-filter=U")
end

local function advance_to_next_conflicted_file(current_abs_path)
  local files = conflicted_files()
  if vim.tbl_isempty(files) then
    return false
  end

  local root = repo_root(current_abs_path)
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
    if config.commands and config.commands.diff_conflicts then
      pcall(function()
        vim.cmd(config.commands.diff_conflicts)
      end)
    else
      pcall(function()
        vim.cmd("DiffConflicts")
      end)
    end
  end)

  return true
end

local function has_conflicts()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("^<<<<<<< ") then
      return true
    end
  end
  return false
end

local function diff_confl()
  local orig_buf = vim.api.nvim_get_current_buf()
  local orig_ft = vim.bo.filetype
  local left_win = vim.api.nvim_get_current_win()

  local conflict_style
  if config.vcs == "git" then
    local result = vim.fn.system("git config --get merge.conflictStyle")
    conflict_style = result:gsub("%s$", "")
  else
    conflict_style = "diff"
  end

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

  vim.api.nvim_set_current_win(left_win)
  vim.cmd("diffthis")

  if conflict_style:lower() == "diff3" or conflict_style:lower() == "zdiff3" then
    vim.cmd("silent! g/^||||||| \\?/,/^>>>>>>> /d")
  else
    vim.cmd("silent! g/^=======\\r\\?$/,/^>>>>>>> /d")
  end
  vim.cmd("silent! g/^<<<<<<< /d")

  vim.cmd("diffupdate")

  if config.qol and config.qol.advance_on_save then
    vim.api.nvim_clear_autocmds({ group = advance_augroup, buffer = orig_buf })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = advance_augroup,
      buffer = orig_buf,
      callback = function()
        close_win_if_valid(right_win)
        delete_buf_if_valid(right_buf)
        cleanup_plugin_aux_buffers(orig_buf)
        if vim.api.nvim_win_is_valid(left_win) then
          pcall(vim.api.nvim_set_current_win, left_win)
        end

        if has_conflicts() then
          diff_confl()
          return
        end

        local current = vim.api.nvim_buf_get_name(orig_buf)
        local advanced = advance_to_next_conflicted_file(current)
        if advanced then
          return
        end

        if config.qol and config.qol.quit_on_done then
          pcall(function()
            vim.cmd("qa")
          end)
        end
      end,
    })
  end
end

local function seed_history_bufs_from_args(opts)
  local args = (opts and opts.fargs) or {}
  local merged_path, base_path, local_path, remote_path

  if #args >= 4 then
    merged_path, base_path, local_path, remote_path = args[1], args[2], args[3], args[4]
  else
    local argv = vim.fn.argv() or {}
    if #argv >= 4 then
      merged_path, base_path, local_path, remote_path = argv[1], argv[2], argv[3], argv[4]
    else
      merged_path = vim.fn.getenv("MERGED")
      base_path = vim.fn.getenv("BASE")
      local_path = vim.fn.getenv("LOCAL")
      remote_path = vim.fn.getenv("REMOTE")
      if
        not (
          base_path
          and base_path ~= ""
          and local_path
          and local_path ~= ""
          and remote_path
          and remote_path ~= ""
        )
      then
        return false
      end
    end
  end

  local function resolve_path(p, base_dir)
    if type(p) ~= "string" or p == "" then
      return nil
    end
    local abs = vim.fn.fnamemodify(p, ":p")
    if vim.fn.filereadable(abs) == 1 then
      return abs
    end
    if base_dir and base_dir ~= "" then
      local cleaned = p:gsub("^%./", "")
      local candidate = vim.fn.fnamemodify(base_dir .. "/" .. cleaned, ":p")
      if vim.fn.filereadable(candidate) == 1 then
        return candidate
      end
    end
    return abs
  end

  local base_dir = nil
  if merged_path and merged_path ~= "" then
    local merged_abs = resolve_path(merged_path, nil)
    if merged_abs then
      base_dir = vim.fn.fnamemodify(merged_abs, ":p:h")
    end
  end
  if not base_dir or base_dir == "" then
    local cur = vim.api.nvim_buf_get_name(0)
    base_dir = cur ~= "" and vim.fn.fnamemodify(cur, ":p:h") or vim.uv.cwd()
  end

  local function ensure_buf_for_path(p)
    local abs = resolve_path(p, base_dir)
    if not abs or abs == "" then
      return nil
    end
    local existing = vim.fn.bufnr(abs, false)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      pcall(vim.fn.bufload, existing)
      return existing
    end
    local cur_win = vim.api.nvim_get_current_win()
    local cur_buf = vim.api.nvim_get_current_buf()
    local ok = pcall(vim.cmd.edit, vim.fn.fnameescape(abs))
    local b = ok and vim.api.nvim_get_current_buf() or nil
    if cur_win and vim.api.nvim_win_is_valid(cur_win) then
      pcall(vim.api.nvim_set_current_win, cur_win)
    end
    if cur_buf and vim.api.nvim_buf_is_valid(cur_buf) then
      pcall(vim.api.nvim_set_current_buf, cur_buf)
    end
    return (b and vim.api.nvim_buf_is_valid(b)) and b or nil
  end

  local bufs = {
    base = ensure_buf_for_path(base_path),
    ["local"] = ensure_buf_for_path(local_path),
    remote = ensure_buf_for_path(remote_path),
  }

  if bufs.base and bufs["local"] and bufs.remote then
    vim.g.diffconflicts_history_bufs = bufs
    return true
  end
  return false
end

local function generate_git_stage_history_buffers()
  local merged_abs = vim.api.nvim_buf_get_name(0)
  if not merged_abs or merged_abs == "" then
    return false
  end

  local root = repo_root_from_marker(".git", merged_abs)
  if not root or root == "" then
    return false
  end

  local merged_p = vim.fn.fnamemodify(merged_abs, ":p")
  local root_p = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
  if merged_p:sub(1, #root_p + 1) ~= root_p .. "/" then
    return false
  end
  local rel = merged_p:sub(#root_p + 2)

  local function git_show_stage(stage)
    local spec = ":" .. stage .. ":" .. rel
    local cmd = "git -C "
      .. vim.fn.shellescape(root_p)
      .. " --no-pager show "
      .. vim.fn.shellescape(spec)
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      return nil
    end
    return out
  end

  local base_lines = git_show_stage("1")
  local local_lines = git_show_stage("2")
  local remote_lines = git_show_stage("3")
  if not (base_lines and local_lines and remote_lines) then
    return false
  end

  local original_ft = vim.bo.filetype

  local function make_stage_buf(lines, name)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.api.nvim_buf_set_name(b, name)
    vim.bo[b].modifiable = false
    vim.bo[b].readonly = true
    vim.bo[b].buftype = "nofile"
    vim.bo[b].bufhidden = "delete"
    vim.bo[b].swapfile = false
    vim.bo[b].filetype = original_ft
    return b
  end

  vim.g.diffconflicts_history_bufs = {
    base = make_stage_buf(base_lines, "BASE"),
    ["local"] = make_stage_buf(local_lines, "LOCAL"),
    remote = make_stage_buf(remote_lines, "REMOTE"),
  }
  return true
end

local function try_open_history_files_from_disk()
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")
  if not dir or dir == "" then
    return
  end

  local cur_tail = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
  local cur_stem = vim.fn.fnamemodify(cur_tail, ":r")
  local cur_ext = vim.fn.fnamemodify(cur_tail, ":e")

  local function glob_first(pattern)
    local matches = vim.fn.globpath(dir, pattern, false, true) or {}
    return matches[1]
  end

  local base_p, local_p, remote_p
  if cur_stem and cur_stem ~= "" then
    local suffix = (cur_ext and cur_ext ~= "") and ("." .. cur_ext) or ""
    base_p = glob_first(cur_stem .. "_BASE_*" .. suffix) or glob_first(cur_stem .. ".*BASE*")
    local_p = glob_first(cur_stem .. "_LOCAL_*" .. suffix) or glob_first(cur_stem .. ".*LOCAL*")
    remote_p = glob_first(cur_stem .. "_REMOTE_*" .. suffix) or glob_first(cur_stem .. ".*REMOTE*")
  end

  if not (base_p and local_p and remote_p) then
    local paths = vim.fn.globpath(dir, "*", false, true) or {}
    for _, p in ipairs(paths) do
      local t = vim.fn.fnamemodify(p, ":t")
      if not base_p and match_history_role(t, "BASE") then
        base_p = p
      elseif not local_p and match_history_role(t, "LOCAL") then
        local_p = p
      elseif not remote_p and match_history_role(t, "REMOTE") then
        remote_p = p
      end
    end
  end

  for _, p in ipairs({ local_p, base_p, remote_p }) do
    if p and p ~= "" then
      pcall(vim.cmd.edit, vim.fn.fnameescape(p))
    end
  end
end

local function find_history_bufs()
  local found = { base = nil, ["local"] = nil, remote = nil }
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name and name ~= "" then
        local t = vim.fn.fnamemodify(name, ":t")
        if not found.base and match_history_role(t, "BASE") then
          found.base = bufnr
        elseif not found["local"] and match_history_role(t, "LOCAL") then
          found["local"] = bufnr
        elseif not found.remote and match_history_role(t, "REMOTE") then
          found.remote = bufnr
        end
      end
    end
  end
  return found
end

local function show_history()
  local bufs = vim.g.diffconflicts_history_bufs
  if type(bufs) ~= "table" or not (bufs.base and bufs["local"] and bufs.remote) then
    vim.cmd("echohl WarningMsg")
    vim.cmd([[echon "Missing BASE/LOCAL/REMOTE buffers. Was Neovim invoked by a Git mergetool?"]])
    vim.cmd("echohl None")
    return
  end

  vim.cmd("tabnew")
  vim.cmd("vsplit")
  vim.cmd("vsplit")
  vim.cmd("wincmd h")
  vim.cmd("wincmd h")

  local function load_history_buf(bufnr, name)
    vim.cmd("buffer " .. tostring(bufnr))
    vim.cmd("setlocal noswapfile")
    vim.cmd("silent! file " .. name)
    vim.cmd([[setlocal statusline=%t]])
    vim.bo.modifiable = false
    vim.bo.readonly = true
    vim.cmd("diffthis")
  end

  load_history_buf(bufs["local"], "LOCAL")
  vim.cmd("wincmd l")
  load_history_buf(bufs.base, "BASE")
  vim.cmd("wincmd l")
  load_history_buf(bufs.remote, "REMOTE")
  vim.cmd("wincmd h")
end

local function check_then_show_history()
  local bufs = vim.g.diffconflicts_history_bufs
  if type(bufs) == "table" and bufs.base and bufs["local"] and bufs.remote then
    show_history()
    return 0
  end

  local found = find_history_bufs()
  if found.base and found["local"] and found.remote then
    vim.g.diffconflicts_history_bufs = found
    show_history()
    return 0
  end

  if generate_git_stage_history_buffers() then
    show_history()
    return 0
  end

  try_open_history_files_from_disk()
  found = find_history_bufs()
  if found.base and found["local"] and found.remote then
    vim.g.diffconflicts_history_bufs = found
    show_history()
    return 0
  end

  vim.cmd("echohl WarningMsg")
  vim.cmd([[echon "Missing one or more of BASE, LOCAL, REMOTE. Was Neovim invoked by a Git mergetool?"]])
  vim.cmd("echohl None")
  return 1
end

local function check_then_diff()
  if has_conflicts() then
    vim.cmd("redraw")
    vim.cmd("echohl WarningMsg")
    vim.cmd([[echon "Resolve conflicts leftward then save. Use :cq to abort."]])
    vim.cmd("echohl None")
    diff_confl()
  else
    vim.cmd('echohl WarningMsg | echo "No conflict markers found." | echohl None')
  end
end

M.show = check_then_diff
M.show_history = check_then_show_history
M.show_with_history = function()
  check_then_show_history()
  vim.cmd("1tabn")
  check_then_diff()
end

local function command_diff_conflicts(opts)
  local args = (opts and opts.fargs) or {}
  local merged = args[1]
  if not merged or merged == "" then
    local argv = vim.fn.argv() or {}
    merged = argv[1]
  end
  if not merged or merged == "" then
    merged = vim.fn.getenv("MERGED")
  end
  if merged and merged ~= "" then
    local cur = vim.api.nvim_buf_get_name(0)
    local merged_abs = vim.fn.fnamemodify(merged, ":p")
    local cur_abs = cur ~= "" and vim.fn.fnamemodify(cur, ":p") or ""
    if cur_abs == "" or cur_abs ~= merged_abs then
      pcall(vim.cmd.edit, vim.fn.fnameescape(merged))
    end
  end
  check_then_diff()
end

local function command_show_history(opts)
  seed_history_bufs_from_args(opts)
  check_then_show_history()
end

local function command_with_history(opts)
  seed_history_bufs_from_args(opts)
  M.show_with_history()
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", config, opts)

  if config.commands.diff_conflicts then
    vim.api.nvim_create_user_command(
      config.commands.diff_conflicts,
      command_diff_conflicts,
      { bang = false, nargs = "*", complete = "file" }
    )
  end
  if config.commands.show_history then
    vim.api.nvim_create_user_command(
      config.commands.show_history,
      command_show_history,
      { bang = false, nargs = "*" }
    )
  end
  if config.commands.with_history then
    vim.api.nvim_create_user_command(
      config.commands.with_history,
      command_with_history,
      { bang = false, nargs = "*", complete = "file" }
    )
  end
end

M._has_conflicts = has_conflicts
M._match_history_role = match_history_role

return M
