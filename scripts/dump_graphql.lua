-- Dump every stored GraphQL document (queries and mutations) as JSON on stdout.
-- Run from the repository root: nvim --headless -l scripts/dump_graphql.lua <out.json>
--
-- The document strings are collected after setup(), so fragment concatenation
-- and the github.com/GHES field substitution are already applied and each
-- document is self-contained and ready to validate.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require "octo.config"
local fragments = require "octo.gh.fragments"
local queries = require "octo.gh.queries"
local mutations = require "octo.gh.mutations"

config.setup {}
_G.octo_pv2_fragment = ""
fragments.setup()
queries.setup()
mutations.setup()

local docs = {}
for name, value in pairs(queries) do
  if type(value) == "string" then
    docs["queries." .. name] = value
  end
end
for name, value in pairs(mutations) do
  if type(value) == "string" then
    docs["mutations." .. name] = value
  end
end

local out_path = _G.arg and _G.arg[1] or "graphql-docs.json"
vim.fn.writefile({ vim.json.encode(docs) }, out_path)
print("wrote " .. out_path)
