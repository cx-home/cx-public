-- DEPRECATED: use `make install-nvim` instead.
--
-- The old runtimepath / get_parser_configs() approach is no longer compatible
-- with nvim-treesitter (main branch) or Neovim 0.11+.
--
-- Install once:
--   cd tooling/tree-sitter-cx
--   make install-nvim
--
-- Then copy tooling/neovim/cx.lua to your Neovim plugin directory.
-- See tooling/neovim/README.md for full instructions.

error("nvim_setup.lua is deprecated. Run `make install-nvim` instead.")
