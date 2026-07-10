local M = {}

function M.history_role(tail, role)
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

return M
