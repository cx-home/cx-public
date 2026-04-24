NVIM_SITE    := $(HOME)/.local/share/nvim/site
PARSER_DIR   := $(NVIM_SITE)/parser
QUERY_DIR    := $(NVIM_SITE)/queries/cx

.PHONY: build install-nvim

build:
	tree-sitter generate
	tree-sitter build --output /tmp/cx.so

install-nvim: build
	mkdir -p $(PARSER_DIR) $(QUERY_DIR)
	cp /tmp/cx.so $(PARSER_DIR)/cx.so
	cp queries/cx/highlights.scm $(QUERY_DIR)/highlights.scm
	cp queries/cx/injections.scm  $(QUERY_DIR)/injections.scm
	@echo "cx parser and queries installed. Restart Neovim."
