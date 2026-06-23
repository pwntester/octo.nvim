---
name: execute-lua
description: >
  Use this skill when you need to execute, test, or debug Lua code inside Neovim's runtime
  environment without opening the editor UI. Applies when: inspecting plugin modules (e.g.
  `require "octo.gh"`), verifying API behaviour, reproducing bugs, running one-off scripts
  against plugin code, or checking what functions/tables a module exposes.   Supports four
  modes: fully isolated (no config, simulates a fresh install), dependency-controlled (no
  config but explicit runtimepath), full user environment (real init.lua + lazy.nvim),
  and Plenary Busted test runner (relative paths, no filesystem assumptions).
  Prefer this over plain `lua` or `luajit` when the code uses `vim.*` APIs or depends on
  Neovim's plugin runtimepath.
---

When you need to exercise Lua code in the exact Neovim environment that the user has installed, shell out to `nvim` with the `-es` headless flags and pass a temporary Lua script via `-l`.

There are four distinct execution modes depending on the goal.

---

## Finding the key paths

Before running any mode, resolve these paths and store them in shell variables. Run this once to discover them:

```bash
# Neovim config dir (where init.lua lives)
NVIM_CONFIG=$(nvim -es -u NONE -l <(echo 'print(vim.fn.stdpath("config"))'))
echo "Config: $NVIM_CONFIG"

# Plugin manager data dir (where lazy.nvim stores plugins)
PLUGIN_DATA=$(nvim -es -u NONE -l <(echo 'print(vim.fn.stdpath("data") .. "/lazy")'))
echo "Plugin data: $PLUGIN_DATA"

# Plugin root dir (run from the cloned repo)
PLUGIN_DIR=$(pwd)
echo "Plugin dir: $PLUGIN_DIR"

# Specific dep (e.g. plenary.nvim)
PLENARY_DIR="$PLUGIN_DATA/plenary.nvim"
echo "Plenary dir: $PLENARY_DIR"
```

The examples below use these variables. Substitute the actual paths if not using shell variables.

---

## Mode 1: Isolated / Fresh-install simulation

No user config, no plugin manager. Only octo.nvim is added to `runtimepath` via `--cmd`.
Use this to test the plugin in isolation, as if it were a fresh install.

```bash
cat <<'EOF' > /tmp/snippet.lua
local ok, gh = pcall(require, "octo.gh")
if ok then
  print(vim.inspect(gh))
else
  print("FAIL: " .. gh)
end
EOF

nvim -es -u NONE --cmd "set rtp+=$PLUGIN_DIR" -l /tmp/snippet.lua
```

- `-u NONE` — skips all user config
- `--cmd "set rtp+=$PLUGIN_DIR"` — injects the plugin dir before init, making its Lua modules findable
- `$PLUGIN_DIR` comes from the discovery step above; replace with the actual path if not using shell variables

---

## Mode 2: Script-controlled runtimepath

Same isolation as Mode 1 but the runtimepath is set from within the Lua script.
Useful when you need multiple dependencies (e.g. plenary.nvim).

```bash
cat <<'EOF' > /tmp/snippet.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

local ok, gh = pcall(require, "octo.gh")
if ok then
  print(vim.inspect(gh))
else
  print("FAIL: " .. gh)
end
EOF

nvim -es -u NONE -l /tmp/snippet.lua
```

- `vim.fn.getcwd()` resolves to the plugin root if you run from within the repo
- Dep paths use `vim.fn.stdpath("data")` — resolves to the correct location on any machine
- List installed lazy plugins: `ls ~/.local/share/nvim/lazy/`

---

## Mode 3: Full user environment

Loads the user's real `init.lua` (including lazy.nvim and all installed plugins).
Use this to simulate exactly how the plugin behaves in the live setup.

```bash
cat <<'EOF' > /tmp/snippet.lua
local ok, gh = pcall(require, "octo.gh")
if ok then
  print(vim.inspect(gh))
else
  print("FAIL: " .. gh)
end
EOF

nvim -es -u "$NVIM_CONFIG/init.lua" -l /tmp/snippet.lua
```

- Omit `-u NONE` and pass the real config path explicitly
- `$NVIM_CONFIG` comes from the discovery step above; alternatively use `$(nvim -es -u NONE -l <(echo 'print(vim.fn.stdpath("config"))'))`
- lazy.nvim runs during init, adding all plugins to runtimepath before the script executes
- Note: lazy-loaded plugins (`lazy = true`) may not be available unless triggered with
  `require("lazy").load({ plugins = { "plugin-name" } })` inside the script

---

## Mode 4: Running Plenary Busted tests

Run the project's existing Plenary Busted test suite. All paths are relative to the plugin root (pwd), so no filesystem-specific configuration is needed.

```bash
# Run a single test file
nvim --headless -c "PlenaryBustedFile lua/tests/plenary/gh_graphql_spec.lua {minimal_init = 'lua/tests/minimal_init.vim'}"

# Run all tests in the directory
nvim --headless -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"
```

- Requires plenary.nvim to be on the runtimepath — the project's `lua/tests/minimal_init.vim` handles this via relative `rtp` entries (change those if plenary lives elsewhere).
- `PlenaryBustedFile` and `PlenaryBustedDirectory` are commands provided by `plugin/plenary.vim`.
- The `minimal_init.vim` path is relative and resolves from the cwd (plugin root).

---

## Best Practices

- Always wrap `require` in `pcall` for readable failure messages.
- Use `vim.print(x)` instead of `print(vim.inspect(x))` — it calls `vim.inspect` automatically.
- Report: the exact command run, snippet path, exit code (`echo "exit: $?"`), and full stdout/stderr.
- The working directory is wherever `nvim` is invoked; verify with `print(vim.fn.getcwd())`.
