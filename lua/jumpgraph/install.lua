-- Locating, downloading and verifying the core binary.
--
-- The core is closed source and ships as prebuilt binaries attached to this
-- repo's GitHub releases (tag `core-v<version>`). `manifest.lua` pins the
-- version and the SHA-256 of every platform build; a download is accepted only
-- if its hash matches. Binaries are stored per version, so updating the plugin
-- fetches the matching core and old versions are cleaned up.
local config = require("jumpgraph.config")
local log = require("jumpgraph.log")
local platform = require("jumpgraph.platform")

local M = {}

function M.manifest()
  return require("jumpgraph.manifest")
end

function M.install_dir()
  return config.options.core.install_dir or vim.fs.joinpath(vim.fn.stdpath("data"), "jumpgraph", "bin")
end

--- Release asset name for a target, e.g. `jumpgraph-core-x86_64-unknown-linux-musl`.
function M.asset_name(target)
  return "jumpgraph-core-" .. target .. (target:find("windows", 1, true) and ".exe" or "")
end

--- Download URL for an asset (honours core.url / $JUMPGRAPH_CORE_URL).
function M.asset_url(asset, version)
  local env = vim.env.JUMPGRAPH_CORE_URL
  local template = config.options.core.url or (env ~= nil and env ~= "" and env) or M.manifest().url
  return (template:gsub("{version}", version):gsub("{asset}", asset))
end

--- Path of the pinned version's binary (whether or not it exists yet).
function M.installed_path()
  return vim.fs.joinpath(M.install_dir(), ("jumpgraph-core-v%s%s"):format(M.manifest().version, platform.exe_suffix()))
end

--- A user-supplied binary (skips download + checksum, still handshake-checked).
function M.override_path()
  local env = vim.env.JUMPGRAPH_CORE
  local p = config.options.core.path or (env ~= nil and env ~= "" and env) or nil
  return p and vim.fs.normalize(p) or nil
end

local function is_file(path)
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "file"
end

--- @return string? path, string? err
function M.resolve()
  local override = M.override_path()
  if override then
    if is_file(override) then
      return override
    end
    return nil, "core.path / $JUMPGRAPH_CORE points to a missing file: " .. override
  end
  local path = M.installed_path()
  if is_file(path) then
    return path
  end
  return nil, "core binary not installed"
end

local function sha256_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return vim.fn.sha256(data)
end

--- Remove binaries of other versions (and stale partial downloads).
local function prune(keep)
  local dir = M.install_dir()
  for name, kind in vim.fs.dir(dir) do
    local full = vim.fs.joinpath(dir, name)
    if kind == "file" and full ~= keep and name:match("^jumpgraph%-core%-") then
      os.remove(full)
    end
  end
end

--- Verify, mark executable and move into place. Main loop only (vim.fn).
--- @return string? path, string? err
local function finish(tmp, dest, expected)
  local actual = sha256_file(tmp)
  if actual ~= expected then
    os.remove(tmp)
    return nil,
      ("checksum mismatch for downloaded core (expected %s, got %s) — refusing to install"):format(
        expected,
        tostring(actual)
      )
  end
  vim.uv.fs_chmod(tmp, tonumber("755", 8))
  os.remove(dest) -- Windows rename won't overwrite
  local ok, err = os.rename(tmp, dest)
  if not ok then
    return nil, "cannot move core into place: " .. tostring(err)
  end
  prune(dest)
  return dest
end

--- Download + verify the pinned core.
--- @param opts? { force?: boolean, sync?: boolean, quiet?: boolean }
--- @param on_done? fun(path?: string, err?: string)
--- @return string? path, string? err  (only when opts.sync)
function M.install(opts, on_done)
  opts = opts or {}
  on_done = on_done or function() end
  local function done(path, err)
    if not opts.quiet then
      if path then
        log.info("installed core v" .. M.manifest().version)
      else
        log.error(err)
      end
    end
    on_done(path, err)
    return path, err
  end

  local manifest = M.manifest()
  local target, terr = platform.target()
  if not target then
    return done(nil, terr .. " — set `core.path` to a binary you have")
  end
  local asset = M.asset_name(target)
  local expected = manifest.assets[target]
  if not expected then
    return done(nil, ("core v%s has no build for %s — set `core.path`"):format(manifest.version, target))
  end
  local dest = M.installed_path()
  if not opts.force and is_file(dest) then
    return done(dest)
  end
  if vim.fn.executable("curl") ~= 1 then
    return done(nil, "curl is required to download the core binary")
  end

  vim.fn.mkdir(M.install_dir(), "p")
  local tmp = dest .. ".part"
  local url = M.asset_url(asset, manifest.version)
  local cmd = { "curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", "--output", tmp, url }

  local function after(res)
    if res.code ~= 0 then
      os.remove(tmp)
      return done(nil, ("download failed (%s): %s"):format(url, vim.trim(res.stderr or "")))
    end
    return done(finish(tmp, dest, expected))
  end

  if opts.sync then
    return after(vim.system(cmd, { text = true }):wait())
  end
  if not opts.quiet then
    log.info(("downloading core v%s for %s…"):format(manifest.version, target))
  end
  vim.system(cmd, { text = true }, vim.schedule_wrap(after))
end

return M
