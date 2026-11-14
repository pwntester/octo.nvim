.PHONY: format docs setup deps upgrade-deps check

format:
	prek run --all-files

docs:
	scripts/gen-config-docs.sh

# Version of lua-language-server installed by `make setup`, locally and
# in CI (which runs the same targets).
LUA_LS_VERSION := 3.18.2

# Third-party libraries referenced by .github/workflows/.luarc.json,
# pinned to commits so typecheck results are reproducible and upstream
# changes land as reviewed Makefile edits rather than surprise CI
# failures. Look up a dep's current HEAD with:
#	gh api repos/<owner>/<repo>/commits/HEAD --jq .sha
# or, without gh:
#	git ls-remote https://github.com/<owner>/<repo>.git HEAD
# then paste the sha below, or run `make upgrade-deps` to do it for all.
DEPS := nvim-lua/plenary.nvim@74b06c6c75e4eeb3108ec01852001636d85a932b \
	folke/snacks.nvim@882c996cf28183f4d63640de0b4c02ec886d01f2 \
	nvim-telescope/telescope.nvim@1e1bab730218eaf97fce743be3f56e51075928ac \
	ibhagwan/fzf-lua@ded1c96d3d9d74634287d722431c26690968a4bf \
	nvim-tree/nvim-web-devicons@0dc0cfb0c6858041174a53c7aa4adaf65e994b3c

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
		repo=$${dep%@*}; \
		sha=$${dep#*@}; \
		name=$${repo#*/}; \
		cur=$$(git -C "deps/$$name" rev-parse HEAD 2>/dev/null || true); \
		if test "$$cur" != "$$sha"; then \
			if test -d "deps/$$name"; then \
				git -C "deps/$$name" fetch --depth 1 origin "$$sha"; \
				git -C "deps/$$name" checkout --detach --quiet FETCH_HEAD; \
			else \
				git init --quiet "deps/$$name" && \
				git -C "deps/$$name" remote add origin \
					"https://github.com/$$repo.git" && \
				git -C "deps/$$name" fetch --quiet --depth 1 origin "$$sha" && \
				git -C "deps/$$name" checkout --quiet --detach FETCH_HEAD; \
			fi & \
		fi; \
	done; wait

# Re-pin every dep to its default branch tip, rewriting the shas in
# this Makefile. Run it deliberately, commit the result, and CI picks
# it up through the cache key.
upgrade-deps:
	@for dep in $(DEPS); do \
		repo=$${dep%@*}; \
		sha=$$(git ls-remote "https://github.com/$$repo.git" HEAD | cut -f1); \
		echo "$$repo@$$sha"; \
		sed -i.bak "s|$$dep|$$repo@$$sha|" Makefile && rm Makefile.bak; \
	done

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
