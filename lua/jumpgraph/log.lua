-- Notifications + the core's log file.
local M = {}

local levels = vim.log.levels

function M.notify(msg, level)
  vim.notify("jumpgraph: " .. msg, level or levels.INFO, { title = "jumpgraph" })
end

function M.info(msg)
  M.notify(msg, levels.INFO)
end

function M.warn(msg)
  M.notify(msg, levels.WARN)
end

function M.error(msg)
  M.notify(msg, levels.ERROR)
end

--- Where the core's stderr goes (`:JumpGraphLog` opens it).
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("log"), "jumpgraph.log")
end

return M
