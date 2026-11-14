-- lazy.nvim runs this after install/update: fetch the pinned core binary now
-- rather than on first :JumpGraphStart.
local path, err = require("jumpgraph.install").install({ sync = true, quiet = true })
if not path then
  error(err)
end
print("jumpgraph: core ready at " .. path)
