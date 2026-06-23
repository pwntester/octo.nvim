format:
	prek run --all-files

docs:
	scripts/gen-config-docs.sh

check:
	@lua-language-server \
		--check=lua/octo \
		--configpath=.github/workflows/.luarc.json \
		--checklevel=Information 2>&1 | \
	grep -v "Undefined global \`vim\`"
