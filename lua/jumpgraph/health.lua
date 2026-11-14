-- :checkhealth jumpgraph
local M = {}

function M.check()
  local h = vim.health
  local install = require("jumpgraph.install")
  local platform = require("jumpgraph.platform")
  local manifest = install.manifest()

  h.start("jumpgraph: editor")
  if vim.fn.has("nvim-0.11") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.11+ required")
  end
  h.ok(("treesitter mode: %s"):format(vim.treesitter and "available" or "unavailable"))

  h.start("jumpgraph: core binary")
  local target, terr = platform.target()
  if target then
    h.ok("platform: " .. target)
  else
    h.warn(terr .. " — set `core.path`")
  end

  local override = install.override_path()
  local bin, err = install.resolve()
  if not bin then
    if override then
      h.error(err)
    elseif target and manifest.assets[target] then
      h.warn(("core v%s not installed yet (downloads on first start, or :JumpGraphInstall)"):format(manifest.version))
    else
      h.error(("core v%s has no build for this platform"):format(manifest.version))
    end
    if vim.fn.executable("curl") == 1 then
      h.ok("curl found (needed for download)")
    else
      h.error("curl not found (needed for download)")
    end
    return
  end
  h.ok((override and "override: " or "installed: ") .. bin)

  local res = vim.system({ bin, "--version" }, { text = true }):wait(3000)
  local version = res.code == 0 and res.stdout:match("jumpgraph%-core%s+(%S+)")
  if not version then
    h.error("binary does not run: " .. vim.trim((res.stderr or "") .. (res.stdout or "")))
    return
  end
  if version == manifest.version then
    h.ok("version " .. version)
  else
    h.warn(("version %s, plugin pins %s"):format(version, manifest.version))
  end
  local proto = vim.system({ bin, "--protocol" }, { text = true }):wait(3000)
  if vim.trim(proto.stdout or "") == tostring(manifest.protocol) then
    h.ok("host protocol " .. manifest.protocol)
  else
    h.error(("host protocol %s, plugin speaks %s"):format(vim.trim(proto.stdout or "?"), manifest.protocol))
  end
  if not override then
    local f = io.open(bin, "rb")
    local sum = f and vim.fn.sha256(f:read("*a"))
    if f then
      f:close()
    end
    if sum == manifest.assets[target] then
      h.ok("checksum matches the manifest")
    else
      h.error("checksum does not match the manifest — :JumpGraphInstall!")
    end
  end

  h.start("jumpgraph: session")
  local st = require("jumpgraph").status()
  h.info(
    ("core %s, tracking %s, mode %s"):format(
      st.core_running and "running" or "not running",
      st.tracking and "on" or "off",
      st.mode
    )
  )
  if st.url then
    h.info("UI: " .. st.url)
  end
  h.info("log: " .. require("jumpgraph.log").path())
end

return M
