vim.keymap.set("n", " ", "<Nop>", { silent = true, remap = false })
vim.g.mapleader = ' '

vim.wo.number = true
vim.wo.relativenumber = true

vim.keymap.set("n", "<C-Left>", ":tabprevious<Enter>", { silent = true, remap = false })
vim.keymap.set("n", "<C-Right>", ":tabNext<Enter>", { silent = true, remap = false })
