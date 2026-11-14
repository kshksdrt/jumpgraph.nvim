-- Treesitter: the named container (function/method/class/impl/…) enclosing
-- the cursor. Node identity in treesitter mode is (file, symbol), so many
-- cursor moves inside one function collapse to one graph node.
local M = {}

-- Node types that count as a container, across common grammars.
M.CONTAINERS = {
  function_declaration = true,
  function_definition = true,
  function_item = true,
  local_function = true,
  method_declaration = true,
  method_definition = true,
  constructor_declaration = true,
  class_declaration = true,
  class_definition = true,
  struct_item = true,
  enum_item = true,
  impl_item = true,
  mod_item = true,
  trait_item = true,
  interface_declaration = true,
  type_declaration = true,
  namespace_definition = true,
}

-- Raw node type → canonical kind (drives the UI icon). Order matters:
-- "method" before "function", etc.
local KIND_RULES = {
  { "method", "Method" },
  { "constructor", "Constructor" },
  { "function", "Function" },
  { "class", "Class" },
  { "struct", "Struct" },
  { "impl", "Impl" },
  { "trait", "Trait" },
  { "interface", "Interface" },
  { "enum", "Enum" },
  { "namespace", "Module" },
  { "mod", "Module" },
  { "type", "Type" },
}

---@param ts_type string
---@return string
function M.canonical_kind(ts_type)
  for _, rule in ipairs(KIND_RULES) do
    if ts_type:find(rule[1], 1, true) then
      return rule[2]
    end
  end
  return "Symbol"
end

--- Name of a container node: its `name` field, first line only.
local function node_name(node, buf)
  local nf = node:field("name")[1]
  if not nf then
    return nil
  end
  local name = vim.treesitter.get_node_text(nf, buf):gsub("[\r\n].*", "")
  return name ~= "" and name or nil
end

--- Enclosing named container at the cursor of the current window.
---@param buf? integer
---@return string? kind, string? name
function M.enclosing(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok or not parser then
    return nil
  end
  -- get_node returns nil on a never-parsed buffer.
  pcall(parser.parse, parser)
  local cur = vim.api.nvim_win_get_cursor(0)
  local okn, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { cur[1] - 1, cur[2] } })
  if not okn then
    return nil
  end
  while node do
    local t = node:type()
    if M.CONTAINERS[t] then
      local name = node_name(node, buf)
      if name then
        return M.canonical_kind(t), name
      end
    end
    node = node:parent()
  end
  return nil
end

return M
