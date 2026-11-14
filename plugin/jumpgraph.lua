-- Commands only; nothing runs (no process, no port, no autocmds) until
-- :JumpGraphStart.
if vim.g.loaded_jumpgraph then
  return
end
vim.g.loaded_jumpgraph = true

local function jg()
  return require("jumpgraph")
end

local cmd = vim.api.nvim_create_user_command

cmd("JumpGraphStart", function()
  jg().start()
end, { desc = "jumpgraph: start tracking navigation" })

cmd("JumpGraphStop", function()
  jg().stop()
end, { desc = "jumpgraph: stop tracking (keeps the graph)" })

cmd("JumpGraphClear", function()
  jg().clear()
end, { desc = "jumpgraph: wipe the graph" })

cmd("JumpGraphOpen", function()
  jg().open()
end, { desc = "jumpgraph: open the graph in a browser" })

cmd("JumpGraphMode", function(o)
  jg().set_mode(o.args)
end, {
  nargs = 1,
  complete = function()
    return { "file", "treesitter" }
  end,
  desc = "jumpgraph: switch between file and treesitter graphs",
})

cmd("JumpGraphInstall", function(o)
  jg().install(o.bang)
end, { bang = true, desc = "jumpgraph: download the core binary (! = reinstall)" })

cmd("JumpGraphLog", function()
  vim.cmd.split(vim.fn.fnameescape(require("jumpgraph.log").path()))
end, { desc = "jumpgraph: open the core's log" })
