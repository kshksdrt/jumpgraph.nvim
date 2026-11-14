-- The core process: spawn it, speak its NDJSON protocol, shut it down.
--
-- Protocol (one JSON object per line; see README "Host protocol"):
--   plugin → core (stdin):  {"op": "hello"|"configure"|"start"|"stop"|"clear"|"visit"|"activity"|"shutdown", …}
--   core → plugin (stdout): {"ev": "hello"|"config"|"started"|"stopped"|"cleared"|"error", …}
--   core stderr → log file (:JumpGraphLog)
-- The first exchange is `hello`; nothing else is sent until the core answers
-- with a matching protocol version.
local log = require("jumpgraph.log")

local M = {}

local PROTOCOL = 1
local HELLO_TIMEOUT_MS = 3000

---@type vim.SystemObj?
local proc = nil
local ready = false
local queue = {} ---@type string[]
local on_event = function(_) end
local on_exit = function(_) end
local log_file = nil ---@type file*?

local function write_line(line)
  if proc and not proc:is_closing() then
    pcall(proc.write, proc, line .. "\n")
  end
end

--- Queue (until the handshake completes) or send an op.
---@param op table
function M.send(op)
  if not proc then
    return -- no core: nothing to tell
  end
  local line = vim.json.encode(op)
  if ready then
    write_line(line)
  else
    queue[#queue + 1] = line
  end
end

function M.alive()
  return proc ~= nil
end

local function reset()
  proc, ready, queue = nil, false, {}
  if log_file then
    log_file:close()
    log_file = nil
  end
end

local function dispatch(ev)
  if ev.ev == "hello" then
    if ev.protocol ~= PROTOCOL then
      log.error(
        ("core v%s speaks protocol %s, this plugin speaks %s — run :JumpGraphInstall!"):format(
          tostring(ev.version),
          tostring(ev.protocol),
          PROTOCOL
        )
      )
      M.kill()
      return
    end
    ready = true
    for _, line in ipairs(queue) do
      write_line(line)
    end
    queue = {}
  end
  on_event(ev)
end

--- Split a byte stream into lines; `cb` gets each complete line.
local function line_splitter(cb)
  local buf = ""
  return function(_, data)
    if not data then
      if buf ~= "" then
        cb(buf)
      end
      return
    end
    buf = buf .. data
    while true do
      local nl = buf:find("\n", 1, true)
      if not nl then
        break
      end
      local line = buf:sub(1, nl - 1):gsub("\r$", "")
      buf = buf:sub(nl + 1)
      if line ~= "" then
        cb(line)
      end
    end
  end
end

--- Start the core and begin the handshake.
---@param bin string
---@param handlers { on_event: fun(ev: table), on_exit: fun(code: integer) }
---@return boolean ok, string? err
function M.spawn(bin, handlers)
  if proc then
    return true
  end
  on_event, on_exit = handlers.on_event, handlers.on_exit
  local log_path = log.path()
  vim.fn.mkdir(vim.fs.dirname(log_path), "p")
  log_file = io.open(log_path, "a")
  if log_file then
    log_file:write(("\n--- %s core %s ---\n"):format(os.date("%Y-%m-%d %H:%M:%S"), bin))
    log_file:flush()
  end

  local ok, obj = pcall(vim.system, { bin }, {
    stdin = true,
    -- Fast-event context: decode here, touch the editor only via schedule.
    stdout = line_splitter(function(line)
      local okj, ev = pcall(vim.json.decode, line)
      vim.schedule(function()
        if okj and type(ev) == "table" then
          dispatch(ev)
        else
          log.warn("unparseable core output: " .. line)
        end
      end)
    end),
    stderr = function(_, data)
      if data and log_file then
        log_file:write(data)
        log_file:flush()
      end
    end,
  }, function(res)
    vim.schedule(function()
      local was = proc
      reset()
      if was then
        on_exit(res.code)
      end
    end)
  end)
  if not ok then
    reset()
    return false, "cannot run core: " .. tostring(obj)
  end
  proc = obj
  write_line(vim.json.encode({ op = "hello", protocol = PROTOCOL }))

  local this = proc
  vim.defer_fn(function()
    if proc == this and not ready then
      log.error("core did not answer the handshake — see :JumpGraphLog")
      M.kill()
    end
  end, HELLO_TIMEOUT_MS)
  return true
end

function M.kill()
  if proc then
    pcall(proc.kill, proc, "sigterm")
  end
end

--- Graceful exit: ask the core to close clients + release the port, wait a bit.
---@param timeout_ms? integer
function M.shutdown(timeout_ms)
  local p = proc
  if not p then
    return
  end
  write_line(vim.json.encode({ op = "shutdown" }))
  pcall(p.write, p, nil) -- close stdin: EOF is also a shutdown
  pcall(p.wait, p, timeout_ms or 1000)
end

return M
