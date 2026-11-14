-- jumpgraph.nvim — a live map of how you navigate a codebase.
--
-- This plugin is the editor half: it watches where you go and reports it to
-- the jumpgraph core (a prebuilt binary, downloaded on first use), which keeps
-- the graph and serves the browser view.
--
--   require("jumpgraph").setup(opts)   -- optional
--   :JumpGraphStart / :JumpGraphStop / :JumpGraphClear / :JumpGraphOpen
local config = require("jumpgraph.config")
local core = require("jumpgraph.core")
local install = require("jumpgraph.install")
local log = require("jumpgraph.log")
local tracker = require("jumpgraph.tracker")

local M = {}

-- Session state. `tracking` flips only on the core's `started`/`stopped`.
local S = {
  tracking = false,
  starting = false,
  url = nil, ---@type string?
  open_on_start = false,
  core_version = nil, ---@type string?
  config = nil, ---@type table? last `config` event (the core's live values)
}

---@param opts? jumpgraph.Opts
function M.setup(opts)
  config.set(opts)
  if core.alive() then
    core.send(config.core_patch())
  end
end

local function handle_event(ev)
  local kind = ev.ev
  if kind == "hello" then
    S.core_version = ev.version
  elseif kind == "config" then
    S.config = ev
    tracker.mirror.mode = ev.mode
    tracker.mirror.throttle_ms = ev.activity_throttle_ms
  elseif kind == "started" then
    S.tracking, S.starting, S.url = true, false, ev.url
    tracker.enable()
    log.info("tracking started — " .. ev.url)
    if S.open_on_start or config.options.open_browser then
      S.open_on_start = false
      vim.ui.open(ev.url)
    end
  elseif kind == "stopped" then
    log.info("tracking stopped")
  elseif kind == "cleared" then
    if not ev.by_client then
      log.info("session cleared")
    end
  elseif kind == "error" then
    if ev.op == "start" then
      S.starting, S.open_on_start = false, false
    end
    log.error(ev.message or "core error")
  end
end

local function handle_exit(code)
  local was_active = S.tracking or S.starting
  S.tracking, S.starting, S.url = false, false, nil
  tracker.disable()
  if was_active then
    log.warn(("core exited unexpectedly (code %d) — see :JumpGraphLog"):format(code))
  end
end

--- Make sure the core is running; `cb(ok)` once it is (or isn't).
local function ensure_core(cb)
  if core.alive() then
    return cb(true)
  end
  local function spawn(bin)
    local ok, err = core.spawn(bin, { on_event = handle_event, on_exit = handle_exit })
    if not ok then
      log.error(err)
      return cb(false)
    end
    core.send(config.core_patch())
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("jumpgraph.lifecycle", { clear = true }),
      callback = function()
        core.shutdown(1000)
      end,
      desc = "jumpgraph: stop the core (closes the UI socket, frees the port)",
    })
    cb(true)
  end

  local bin, err = install.resolve()
  if bin then
    return spawn(bin)
  end
  if install.override_path() or not config.options.core.auto_install then
    log.error(err .. " — run :JumpGraphInstall")
    return cb(false)
  end
  install.install({}, function(path)
    if path then
      spawn(path)
    else
      cb(false)
    end
  end)
end

function M.start()
  if S.tracking then
    return log.info("already tracking")
  end
  if S.starting then
    return
  end
  S.starting = true
  ensure_core(function(ok)
    if not ok then
      S.starting, S.open_on_start = false, false
      return
    end
    core.send({ op = "start", addr = config.addr(), location = tracker.current_file_location() })
  end)
end

function M.stop()
  if not S.tracking then
    return log.info("not currently tracking")
  end
  S.tracking, S.url = false, nil
  tracker.disable()
  core.send({ op = "stop" })
end

function M.clear()
  if core.alive() then
    core.send({ op = "clear" })
  else
    log.info("session cleared")
  end
end

--- Open the browser view (starting tracking first if needed).
function M.open()
  if S.tracking and S.url then
    return vim.ui.open(S.url)
  end
  S.open_on_start = true
  M.start()
end

--- Switch what the graph tracks. Clears the graph (nodes of different kinds
--- don't mix).
---@param mode "file"|"treesitter"
function M.set_mode(mode)
  local core_mode = config.core_mode(mode)
  if not core_mode then
    return log.error("unknown mode '" .. tostring(mode) .. "' (file | treesitter)")
  end
  config.options.mode = mode
  if core.alive() then
    core.send({ op = "configure", mode = core_mode })
  end
  log.info("mode: " .. mode)
end

--- (Re)install the pinned core binary.
---@param force? boolean
function M.install(force)
  install.install({ force = force })
end

--- Snapshot of the session, for statuslines and :checkhealth.
function M.status()
  return {
    tracking = S.tracking,
    url = S.url,
    core_running = core.alive(),
    core_version = S.core_version,
    mode = tracker.mirror.mode,
    config = S.config,
  }
end

return M
