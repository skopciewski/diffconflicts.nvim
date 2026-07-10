local config = require("diffconflicts.config")
local match = require("diffconflicts.match")
local util = require("diffconflicts.util")

local M = {}

function M.seed_history_bufs_from_args(opts)
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
          type(base_path) == "string"
          and base_path ~= ""
          and type(local_path) == "string"
          and local_path ~= ""
          and type(remote_path) == "string"
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

  local root = util.repo_root_from_marker(".git", merged_abs)
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
      if not base_p and match.history_role(t, "BASE") then
        base_p = p
      elseif not local_p and match.history_role(t, "LOCAL") then
        local_p = p
      elseif not remote_p and match.history_role(t, "REMOTE") then
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
        if not found.base and match.history_role(t, "BASE") then
          found.base = bufnr
        elseif not found["local"] and match.history_role(t, "LOCAL") then
          found["local"] = bufnr
        elseif not found.remote and match.history_role(t, "REMOTE") then
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

function M.check_then_show_history()
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

return M
