local plenary_dir = vim.fn.getcwd() .. "/.deps/plenary.nvim"

vim.opt.rtp:prepend(plenary_dir)
vim.opt.rtp:prepend(vim.fn.getcwd())

vim.opt.swapfile = false
vim.opt.shada = ""

vim.cmd("runtime! plugin/plenary.vim")
