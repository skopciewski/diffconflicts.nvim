local dc = require("diffconflicts")
local match = require("diffconflicts.match")
local config = require("diffconflicts.config")
local diff = require("diffconflicts.diff")

describe("config", function()
  before_each(function()
    config.values = vim.deepcopy(config.defaults)
  end)

  it("merges user options over defaults", function()
    config.setup({ vcs = "hg", qol = { advance_on_save = false } })
    assert.are.equal("hg", config.values.vcs)
    assert.is_false(config.values.qol.advance_on_save)
    assert.is_true(config.values.qol.quit_on_done)
  end)

  it("partial merge preserves unspecified defaults", function()
    config.setup({ qol = {} })
    assert.is_true(config.values.qol.advance_on_save)
    assert.is_true(config.values.qol.quit_on_done)
  end)

  it("empty opts does not change defaults", function()
    config.setup({})
    assert.are.equal("git", config.values.vcs)
  end)
end)

describe("match_history_role", function()
  it("matches delimiter-delimited history buffer names", function()
    local true_cases = {
      { "BASE", "BASE" },
      { "BASE_11614.txt", "BASE" },
      { "BASE.poem", "BASE" },
      { "BASE-poem", "BASE" },
      { "poem_BASE", "BASE" },
      { "poem.BASE", "BASE" },
      { "poem-BASE", "BASE" },
      { "poem_BASE_11614.txt", "BASE" },
      { "poem.BASE.11614", "BASE" },
      { "base", "BASE" },
      { "Base_11614", "BASE" },
      { "poem_local_11614", "LOCAL" },
      { "poem_remote_11614", "REMOTE" },
    }
    for _, c in ipairs(true_cases) do
      assert.is_true(
        match.history_role(c[1], c[2]),
        string.format("expected true: %q matches %q", c[1], c[2])
      )
    end
  end)

  it("rejects names without delimiter-separated role", function()
    local false_cases = {
      { "REBASE", "BASE" },
      { "BASELINE", "BASE" },
      { "DATABASES", "BASE" },
      { "main", "BASE" },
      { "origin", "BASE" },
      { "HEAD", "REMOTE" },
      { nil, "BASE" },
      { "", "BASE" },
      { "base", "REMOTE" },
    }
    for _, c in ipairs(false_cases) do
      assert.is_false(
        match.history_role(c[1], c[2]),
        string.format("expected false: %q should not match %q", c[1], c[2])
      )
    end
  end)
end)

describe("has_conflicts", function()
  before_each(function()
    dc.setup({ vcs = "hg", qol = { advance_on_save = false, quit_on_done = false } })
  end)

  it("returns true when buffer contains conflict markers", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours content",
      "=======",
      "theirs content",
      ">>>>>>> branch",
    })
    vim.api.nvim_set_current_buf(buf)
    assert.is_true(diff.has_conflicts())
  end)

  it("returns true for diff3 conflict markers", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "||||||| base",
      "common ancestor",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    vim.api.nvim_set_current_buf(buf)
    assert.is_true(diff.has_conflicts())
  end)

  it("returns false for buffer without conflict markers", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "normal content" })
    vim.api.nvim_set_current_buf(buf)
    assert.is_false(diff.has_conflicts())
  end)

  it("returns false for empty buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    assert.is_false(diff.has_conflicts())
  end)

  it("requires markers at start of line", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " <<<<<<< HEAD" })
    vim.api.nvim_set_current_buf(buf)
    assert.is_false(diff.has_conflicts())
  end)
end)

describe("diff_confl — two-way split", function()
  before_each(function()
    -- Close windows left by previous groups
    while #vim.api.nvim_list_wins() > 1 do
      pcall(vim.api.nvim_win_close, vim.api.nvim_list_wins()[2], true)
    end
    -- Close tabs from previous groups
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tabs = vim.api.nvim_list_tabpages()
    for i = #tabs, 2, -1 do
      pcall(vim.api.nvim_set_current_tabpage, tabs[i])
      pcall(vim.cmd, "tabclose!")
    end
    pcall(vim.api.nvim_set_current_tabpage, cur_tab)
    -- Clear globals
    vim.g.diffconflicts_history_bufs = nil
    vim.api.nvim_clear_autocmds({ group = "diffconflicts.nvim.advance" })

    dc.setup({ vcs = "hg", qol = { advance_on_save = false, quit_on_done = false } })
  end)

  it("splits conflict markers into left-ours and right-theirs panes", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "unrelated line",
      "<<<<<<< HEAD",
      "ours only",
      "=======",
      "theirs only",
      ">>>>>>> branch",
      "trailing line",
    })
    vim.bo[buf].filetype = "lua"
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins = vim.api.nvim_list_wins()
    assert.are.equal(2, #wins)

    local left_buf = vim.api.nvim_win_get_buf(wins[1])
    local left_lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)
    local left_text = table.concat(left_lines, "\n")

    assert.is_not_nil(left_text:find("unrelated line", 1, true))
    assert.is_not_nil(left_text:find("ours only", 1, true))
    assert.is_nil(left_text:find("<<<<<<<", 1, true))
    assert.is_nil(left_text:find("=======", 1, true))
    assert.is_nil(left_text:find("theirs only", 1, true))
    assert.is_nil(left_text:find(">>>>>>>", 1, true))
    assert.is_not_nil(left_text:find("trailing line", 1, true))

    local right_buf = vim.api.nvim_win_get_buf(wins[2])
    local right_lines = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)
    local right_text = table.concat(right_lines, "\n")

    assert.is_not_nil(right_text:find("unrelated line", 1, true))
    assert.is_nil(right_text:find("ours only", 1, true))
    assert.is_nil(right_text:find("<<<<<<<", 1, true))
    assert.is_nil(right_text:find("=======", 1, true))
    assert.is_not_nil(right_text:find("theirs only", 1, true))
    assert.is_nil(right_text:find(">>>>>>>", 1, true))
    assert.is_not_nil(right_text:find("trailing line", 1, true))
  end)

  it("right pane is readonly with RCONFL name", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins = vim.api.nvim_list_wins()
    local right_buf = vim.api.nvim_win_get_buf(wins[2])
    assert.is_true(vim.bo[right_buf].readonly)
    assert.is_false(vim.bo[right_buf].modifiable)
    assert.are.equal("nofile", vim.bo[right_buf].buftype)
    local bufname = vim.api.nvim_buf_get_name(right_buf)
    assert.are.equal("RCONFL", vim.fn.fnamemodify(bufname, ":t"))
  end)

  it("preserves filetype on right pane", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    vim.bo[buf].filetype = "python"
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins = vim.api.nvim_list_wins()
    local right_buf = vim.api.nvim_win_get_buf(wins[2])
    assert.are.equal("python", vim.bo[right_buf].filetype)
  end)

  it("both panes are in diff mode", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins = vim.api.nvim_list_wins()
    assert.is_true(vim.wo[wins[1]].diff)
    assert.is_true(vim.wo[wins[2]].diff)
  end)
end)

describe("advance_on_save", function()
  before_each(function()
    -- Close windows left by previous groups
    while #vim.api.nvim_list_wins() > 1 do
      pcall(vim.api.nvim_win_close, vim.api.nvim_list_wins()[2], true)
    end
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tabs = vim.api.nvim_list_tabpages()
    for i = #tabs, 2, -1 do
      pcall(vim.api.nvim_set_current_tabpage, tabs[i])
      pcall(vim.cmd, "tabclose!")
    end
    pcall(vim.api.nvim_set_current_tabpage, cur_tab)
    vim.g.diffconflicts_history_bufs = nil
    vim.api.nvim_clear_autocmds({ group = "diffconflicts.nvim.advance" })
  end)

  it("registers BufWritePost autocmd on the left buffer", function()
    dc.setup({ vcs = "hg", qol = { advance_on_save = true, quit_on_done = false } })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins = vim.api.nvim_list_wins()
    local left_buf = vim.api.nvim_win_get_buf(wins[1])

    local acmds = vim.api.nvim_get_autocmds({
      group = "diffconflicts.nvim.advance",
      buffer = left_buf,
      event = "BufWritePost",
    })
    assert.are.equal(1, #acmds)
  end)

  it("cleans up right pane after resolving conflict and saving", function()
    dc.setup({ vcs = "hg", qol = { advance_on_save = true, quit_on_done = false } })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<<<<<<< HEAD",
      "ours",
      "=======",
      "theirs",
      ">>>>>>> branch",
    })
    local tmpname = os.tmpname()
    vim.api.nvim_buf_set_name(buf, tmpname)
    vim.bo[buf].filetype = "text"
    vim.api.nvim_set_current_buf(buf)

    dc.show()

    local wins_before = vim.api.nvim_list_wins()
    assert.are.equal(2, #wins_before)

    local left_buf = vim.api.nvim_win_get_buf(wins_before[1])
    vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "resolved content" })

    vim.api.nvim_set_current_win(wins_before[1])
    vim.cmd("write!")

    local wins_after = vim.api.nvim_list_wins()
    assert.are.equal(1, #wins_after, "right window should close after save")

    os.remove(tmpname)
  end)
end)

describe("show_history", function()
  before_each(function()
    while #vim.api.nvim_list_wins() > 1 do
      pcall(vim.api.nvim_win_close, vim.api.nvim_list_wins()[2], true)
    end
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tabs = vim.api.nvim_list_tabpages()
    for i = #tabs, 2, -1 do
      pcall(vim.api.nvim_set_current_tabpage, tabs[i])
      pcall(vim.cmd, "tabclose!")
    end
    pcall(vim.api.nvim_set_current_tabpage, cur_tab)
    vim.g.diffconflicts_history_bufs = nil
    vim.api.nvim_clear_autocmds({ group = "diffconflicts.nvim.advance" })

    dc.setup({ vcs = "git", qol = { advance_on_save = false, quit_on_done = false } })
  end)

  it("opens three-pane diff view from seeded history buffers", function()
    local function create_history_buf(name, content)
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { content })
      vim.api.nvim_buf_set_name(b, name)
      return b
    end

    vim.g.diffconflicts_history_bufs = {
      base = create_history_buf("BASE", "base content"),
      ["local"] = create_history_buf("LOCAL", "local content"),
      remote = create_history_buf("REMOTE", "remote content"),
    }

    local tabs_before = #vim.api.nvim_list_tabpages()
    dc.show_history()
    local tabs_after = #vim.api.nvim_list_tabpages()

    assert.are.equal(tabs_before + 1, tabs_after, "should open a new tab")
  end)

  it("warns when history buffers are missing", function()
    vim.g.diffconflicts_history_bufs = nil

    local ok = pcall(dc.show_history)
    assert.is_true(ok, "show_history should not crash without buffers")
  end)

  it("warns when history buffers table is incomplete", function()
    vim.g.diffconflicts_history_bufs = { base = nil, ["local"] = nil, remote = nil }

    local ok = pcall(dc.show_history)
    assert.is_true(ok, "show_history should not crash with incomplete buffers")
  end)
end)
