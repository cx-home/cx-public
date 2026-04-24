-- CX language support for Neovim 0.11+
--
-- SETUP (one time, or after grammar changes):
--   cd tooling/tree-sitter-cx && make install-nvim
--
-- Then drop this file into your plugin directory.
-- LazyVim / lazy.nvim: place at lua/plugins/cx.lua
-- Plain init.lua: require() it directly
--
-- Requires: Neovim 0.11+, Node.js >= 18 (for LSP)

vim.filetype.add({ extension = { cx = "cx" } })
vim.treesitter.language.register("cx", "cx")

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.cx_ls = {
        cmd = { "node", vim.fn.expand("~/.local/share/cx-lsp/out/server.js"), "--stdio" },
        filetypes = { "cx" },
        root_markers = { "v.mod", ".git" },
        single_file_support = true,
        mason = false,
      }
    end,
  },
}
