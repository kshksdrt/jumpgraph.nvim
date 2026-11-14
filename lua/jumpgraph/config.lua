-- User options. Everything is optional; `setup()` is only needed to change
-- something.
local M = {}

---@class jumpgraph.CoreOpts
---@field path? string        Use this core binary instead of downloading one ($JUMPGRAPH_CORE).
---@field auto_install? boolean Download the pinned binary on first :JumpGraphStart (default true).
---@field url? string         Download URL template with {version} and {asset} ($JUMPGRAPH_CORE_URL).
---@field install_dir? string Where downloaded binaries live (default stdpath("data")/jumpgraph/bin).

---@class jumpgraph.Opts
---@field addr? string        host:port for the UI + websocket ($JUMPGRAPH_ADDR, default 127.0.0.1:9001).
---@field open_browser? boolean Open the UI when tracking starts (default false).
---@field mode? "file"|"treesitter" What the graph tracks (default "file").
---@field activity_base? number
---@field activity_decay? number
---@field activity_throttle_ms? integer
---@field poll_interval_ms? integer
---@field draw_back_edges? boolean
---@field ignore_buftypes? string[] Buffers with these 'buftype's are never recorded.
---@field core? jumpgraph.CoreOpts

---@type jumpgraph.Opts
M.defaults = {
  addr = nil,
  open_browser = false,
  mode = nil,
  activity_base = nil,
  activity_decay = nil,
  activity_throttle_ms = nil,
  poll_interval_ms = nil,
  draw_back_edges = nil,
  ignore_buftypes = { "terminal", "prompt", "quickfix", "nofile" },
  core = { path = nil, auto_install = true, url = nil, install_dir = nil },
}

-- Tunables forwarded to the core verbatim (nil = keep the core's default).
M.TUNABLES = {
  "activity_base",
  "activity_decay",
  "activity_throttle_ms",
  "poll_interval_ms",
  "draw_back_edges",
}

---@type jumpgraph.Opts
M.options = vim.deepcopy(M.defaults)

local MODES = { file = "File", treesitter = "Treesitter" }

--- Normalize a user-facing mode name to the core's spelling.
---@return string? core_mode
function M.core_mode(mode)
  if mode == nil then
    return nil
  end
  return MODES[tostring(mode):lower()]
end

---@param opts? jumpgraph.Opts
function M.set(opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  vim.validate("addr", merged.addr, "string", true)
  vim.validate("open_browser", merged.open_browser, "boolean")
  vim.validate("mode", merged.mode, function(m)
    return M.core_mode(m) ~= nil
  end, true, "'file' or 'treesitter'")
  vim.validate("activity_base", merged.activity_base, "number", true)
  vim.validate("activity_decay", merged.activity_decay, "number", true)
  vim.validate("activity_throttle_ms", merged.activity_throttle_ms, "number", true)
  vim.validate("poll_interval_ms", merged.poll_interval_ms, "number", true)
  vim.validate("draw_back_edges", merged.draw_back_edges, "boolean", true)
  vim.validate("ignore_buftypes", merged.ignore_buftypes, "table")
  vim.validate("core", merged.core, "table")
  M.options = merged
end

function M.addr()
  local env = vim.env.JUMPGRAPH_ADDR
  return M.options.addr or (env ~= nil and env ~= "" and env) or "127.0.0.1:9001"
end

--- The `configure` patch implied by the options (only what the user set).
function M.core_patch()
  local patch = { op = "configure" }
  patch.mode = M.core_mode(M.options.mode)
  for _, k in ipairs(M.TUNABLES) do
    patch[k] = M.options[k]
  end
  return patch
end

return M
