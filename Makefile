format:
	prek run --all-files

docs:
	scripts/gen-config-docs.sh

# Version of lua-language-server installed by `make setup`, locally and
# in CI (which runs the same targets).
LUA_LS_VERSION := 3.18.2

# Third-party libraries referenced by .github/workflows/.luarc.json.
DEPS := nvim-lua/plenary.nvim folke/snacks.nvim \
	nvim-telescope/telescope.nvim ibhagwan/fzf-lua \
	nvim-tree/nvim-web-devicons

# The CI toolchain: nvim stable and a pinned lua-language-server,
# unpacked like CI does before typechecking. Optional, but gives
# results identical to CI on any machine.
setup:
	@test -d _neovim/share/nvim/runtime || { \
		mkdir -p _neovim; \
		case "$$(uname -s)-$$(uname -m)" in \
			Linux-x86_64) url=nvim-linux-x86_64.tar.gz ;; \
			Linux-aarch64) url=nvim-linux-arm64.tar.gz ;; \
			Darwin-arm64) url=nvim-macos-arm64.tar.gz ;; \
			Darwin-x86_64) url=nvim-macos-x86_64.tar.gz ;; \
			*) echo "unsupported platform" >&2; exit 1 ;; \
		esac; \
		curl -sL "https://github.com/neovim/neovim/releases/download/stable/$$url" \
			| tar xzf - --strip-components=1 -C _neovim; \
	}
	@test -d luals/bin || { \
		mkdir -p luals; \
		case "$$(uname -s)-$$(uname -m)" in \
			Linux-x86_64) asset=linux-x64 ;; \
			Linux-aarch64) asset=linux-arm64 ;; \
			Darwin-arm64) asset=darwin-arm64 ;; \
			Darwin-x86_64) asset=darwin-x64 ;; \
			*) echo "unsupported platform" >&2; exit 1 ;; \
		esac; \
		curl -sL "https://github.com/LuaLS/lua-language-server/releases/download/$(LUA_LS_VERSION)/lua-language-server-$(LUA_LS_VERSION)-$$asset.tar.gz" \
			| tar xzf - --directory luals; \
	}

deps:
	@mkdir -p deps
	@for dep in $(DEPS); do \
		repo=$$(echo $$dep | cut -d'/' -f2); \
		test -d "deps/$$repo" || git clone --depth 1 \
			"https://github.com/$$dep.git" "deps/$$repo" & \
	done; wait

# Bring existing shallow clones up to their default branch tip.
update-deps:
	@for dep in $(DEPS); do \
		repo=$$(echo $$dep | cut -d'/' -f2); \
		if test -d "deps/$$repo"; then \
			echo "updating $$repo"; \
			git -C "deps/$$repo" pull --ff-only --quiet & \
		else \
			git clone --depth 1 \
				"https://github.com/$$dep.git" "deps/$$repo" & \
		fi; \
	done; wait

# Prefer the pinned runtime from `make setup` when present, falling back
# to whatever the nvim on PATH provides. Paths must be absolute: the
# luarc resolves library paths relative to its own directory, and CI
# always passes an absolute path.
VIMRUNTIME ?= $(or \
	$(abspath $(wildcard _neovim/share/nvim/runtime)), \
	$(shell nvim -e -u NONE -c 'echo $$VIMRUNTIME' -c q 2>&1))
LUA_LS ?= $(or $(wildcard luals/bin/lua-language-server),lua-language-server)

check: deps
	env VIMRUNTIME="$(VIMRUNTIME)" $(LUA_LS) \
		--check=$(PWD)/lua/octo \
		--configpath=$(PWD)/.github/workflows/.luarc.json \
		--checklevel=Information
