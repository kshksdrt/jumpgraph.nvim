-- Editor events → core ops. Autocmds exist only while tracking.
--
--   BufEnter     (File mode)        → visit {file}            (a cross-file jump)
--   CursorMoved  (File mode)        → activity                (grow the current file)
--   CursorMoved  (Treesitter mode)  → visit {file, symbol}    (jump between symbols)
-- CursorMoved is throttled to the core's `activity_throttle_ms`.
local config = require("jumpgraph.config")
local core = require("jumpgraph.core")
local symbols = require("jumpgraph.symbols")

local M = {}

local GROUP = "jumpgraph.tracker"

---@type { mode: string, throttle_ms: integer }
M.mirror = { mode = "File", throttle_ms = 120 }

local last_cursor = 0

--- File path of a trackable buffer, or nil.
---@param buf integer
function M.file_of(buf)
  if vim.tbl_contains(config.options.ignore_buftypes, vim.bo[buf].buftype) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and name or nil
end

--- Where the user is at file level (seeds the first edge on start).
function M.current_file_location()
  local file = M.file_of(vim.api.nvim_get_current_buf())
  return file and { file = file } or nil
end

local function on_buf_enter(args)
  if M.mirror.mode ~= "File" then
    return
  end
  local file = M.file_of(args.buf)
  if file then
    core.send({ op = "visit", location = { file = file } })
  end
end

local function on_cursor_moved(args)
  local now = vim.uv.now()
  if now - last_cursor < M.mirror.throttle_ms then
    return
  end
  last_cursor = now
  if M.mirror.mode == "File" then
    core.send({ op = "activity" })
    return
  end
  local file = M.file_of(args.buf)
  if not file then
    return
  end
  local kind, name = symbols.enclosing(args.buf)
  if name then
    core.send({ op = "visit", location = { file = file, symbol = name, kind = kind }, activity = true })
  end
end

function M.enable()
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = on_buf_enter,
    desc = "jumpgraph: record cross-file jumps",
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = on_cursor_moved,
    desc = "jumpgraph: in-file activity + treesitter symbol tracking",
  })
end

function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, GROUP)
end

return M
