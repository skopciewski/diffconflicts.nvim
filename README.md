# diffconflicts.nvim

A Neovim plugin for resolving Git merge conflicts via two-way diff.

Make resolving merge conflicts in Neovim a breeze.

## Origins

This is a fork of [mistweaverco/diffconflicts.nvim](https://github.com/mistweaverco/diffconflicts.nvim)
by Marco Kellershoff, which is itself a Lua rewrite of the original
[vim-diffconflicts](https://github.com/whiteinge/diffconflicts) by
[Nathaniel Whiteinge](https://www.eseth.org/).

The core idea — **conflict markers are a two-way diff** — comes from Nathaniel's
original README:

> Rather than editing the conflict markers directly, it is better to perform a
> two-way diff on *only* the "left" and "right" sides of the conflict markers
> by splitting them apart.

Three-way diffs (LOCAL / BASE / REMOTE) are visually noisy. Editing raw
`<<<<<<<` / `=======` / `>>>>>>>` markers is error-prone — the human eye can't
spot subtle differences. A two-way diff highlights only the relevant conflicting
changes, side by side.

### How this fork differs from upstream

- **No Jujutsu (`jj`) support** — Git-only, simpler codebase.
- **No keymaps** — relies on built-in Vim diff mappings (`do`, `dp`, `]c`, `[c`).
- **`setup()` is config-only** — commands live in `plugin/`, following
  [`:help lua-plugin`](https://neovim.io/doc/user/lua-plugin.html) best practices
  (decoupled configuration and initialization).
- **Modular structure** — split into `config`, `diff`, `history`, `match`, `util`
  submodules instead of a single 600+ line file.
- **Tests** — 19 integration tests via `plenary.nvim`.

## Requirements

- Neovim 0.10+
- Git 2.25+ (for `git mergetool` support)

## Installation

Use your favorite plugin manager.

With [Lazy](https://github.com/folke/lazy.nvim):

```lua
{
  "skopciewski/diffconflicts.nvim",
  opts = {
    qol = {
      advance_on_save = true,   -- auto-advance to next conflict on :w
      quit_on_done = true,      -- auto-quit when all conflicts resolved
    },
  },
}
```

All options are optional — the plugin works out of the box with defaults.

Configure Git to use it as a merge-tool:

```sh
git config --global merge.tool diffconflicts
git config --global mergetool.diffconflicts.cmd \
  'nvim -c DiffConflicts "$MERGED" "$BASE" "$LOCAL" "$REMOTE"'
git config --global mergetool.diffconflicts.trustExitCode true
git config --global mergetool.keepBackup false
```

## Usage

```sh
git mergetool
```

Or manually in Neovim:

```vim
:DiffConflicts
```

The left pane shows the resolution (ours), editable. The right pane shows the
conflicting changes (theirs), read-only. Edit the left side to resolve, then
`:w`. Use `:cq` to abort.

### Commands

| Command | Action |
|---------|--------|
| `:DiffConflicts [file]` | Open two-way diff view on current buffer or [file] |
| `:DiffConflictsShowHistory` | Open a new tab with LOCAL, BASE, REMOTE panes |
| `:DiffConflictsWithHistory [file]` | Open both diff view and history tab |

### Lua API

```lua
require("diffconflicts").show()             -- open diff view
require("diffconflicts").show_history()     -- open history tab
require("diffconflicts").show_with_history() -- both
```

### Configuration

```lua
require("diffconflicts").setup({
  qol = {
    advance_on_save = true,
    quit_on_done = true,
  },
})
```

### Health check

```vim
:checkhealth diffconflicts
```

## Project structure

```
lua/diffconflicts/
  init.lua       — public API (setup, show, show_history, show_with_history)
  config.lua     — defaults and config merging (pure, unit-testable)
  match.lua      — history buffer name matching (pure, unit-testable)
  diff.lua       — conflict marker splitting, two-way diff, advance logic
  history.lua    — history view (LOCAL/BASE/REMOTE), buffer discovery
  util.lua       — shared helpers (window/buffer guards, repo root, file open)
  health.lua     — :checkhealth integration
plugin/
  diffconflicts.lua — user commands, lazy require (loaded at startup)
doc/
  diffconflicts.txt — vimdoc (:help diffconflicts)
tests/
  diffconflicts_spec.lua — 19 integration tests (plenary.nvim)
  minimal_init.lua       — test bootstrap
scripts/
  make-conflicts.sh — creates a sample repo with merge conflicts for manual testing
```

### Key design decisions

- **`plugin/` owns commands, `lua/` owns logic.** Commands are created at
  startup without eagerly loading any module. The first command invocation
  triggers `require("diffconflicts")`.
- **`setup()` only merges config.** No side effects — follows the
  [decoupled config + smart init](https://mrcjkb.dev/posts/2023-08-22-setup.html)
  pattern. Commands work without calling `setup()`.
- **No comments.** Express intent through names and structure (see Conventions).
- **Two test seams only:** `match.lua` and `config.lua` are pure modules,
  directly importable by tests without going through `init.lua`.

## Development

```sh
make test          # clone plenary (first run) + run all tests
```

To manually test with a sample conflicted repo:

```sh
./scripts/make-conflicts.sh
cd tmp/testrepo
git mergetool
```

## Conventions

Conventions for contributing to this repo:

- **Comments:** none unless explicitly requested. Express intent through names
  and structure. `why`/intent comments are subject to the **same** restriction —
  explaining *why* rather than *what* does **not** exempt a comment from it.
- **Docstrings:** follow existing practice in `lua/` — contract only (params,
  returns, raises, non-obvious side effects). Not affected by the comment rule.
- **Regression / security tests:** encode the incident in the test *name*
  (e.g. `test_crafted_id_leaves_other_rows_intact`), not a comment.
