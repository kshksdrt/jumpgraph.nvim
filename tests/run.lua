-- Unit tests for the Lua side; no core binary needed.
--   nvim --clean --headless --cmd "set rtp^=." -l tests/run.lua
local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. "\n       " .. tostring(err))
  end
end

local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(("%s: expected %s, got %s"):format(msg or "eq", vim.inspect(b), vim.inspect(a)), 2)
  end
end

local platform = require("jumpgraph.platform")
local config = require("jumpgraph.config")
local install = require("jumpgraph.install")
local symbols = require("jumpgraph.symbols")
local tracker = require("jumpgraph.tracker")

print("platform")
test("maps every published target", function()
  local cases = {
    { "Linux", "x86_64", "x86_64-unknown-linux-musl" },
    { "Linux", "aarch64", "aarch64-unknown-linux-musl" },
    { "Darwin", "arm64", "aarch64-apple-darwin" },
    { "Darwin", "x86_64", "x86_64-apple-darwin" },
    { "Windows_NT", "x86_64", "x86_64-pc-windows-msvc" },
    { "Windows_NT", "AMD64", "x86_64-pc-windows-msvc" },
    { "MINGW64_NT-10.0", "x86_64", "x86_64-pc-windows-msvc" },
  }
  for _, c in ipairs(cases) do
    eq(platform.target({ sysname = c[1], machine = c[2] }), c[3], c[1] .. "/" .. c[2])
  end
end)
test("unknown platform is an error, not a guess", function()
  local t, err = platform.target({ sysname = "FreeBSD", machine = "x86_64" })
  eq(t, nil)
  assert(err:find("FreeBSD/x86_64", 1, true), err)
end)

print("config")
test("defaults", function()
  config.set({})
  eq(config.addr(), vim.env.JUMPGRAPH_ADDR or "127.0.0.1:9001")
  eq(config.core_patch(), { op = "configure" })
end)
test("patch forwards only what the user set", function()
  config.set({ mode = "Treesitter", poll_interval_ms = 500, draw_back_edges = false })
  eq(config.core_patch(), { op = "configure", mode = "Treesitter", poll_interval_ms = 500, draw_back_edges = false })
  config.set({})
end)
test("rejects bad options", function()
  assert(not pcall(config.set, { mode = "lsp" }), "bad mode accepted")
  assert(not pcall(config.set, { activity_base = "x" }), "bad number accepted")
  config.set({})
end)
test("addr precedence: option > $JUMPGRAPH_ADDR > default", function()
  local saved = vim.env.JUMPGRAPH_ADDR
  vim.env.JUMPGRAPH_ADDR = "127.0.0.1:7000"
  config.set({})
  eq(config.addr(), "127.0.0.1:7000")
  config.set({ addr = "127.0.0.1:7001" })
  eq(config.addr(), "127.0.0.1:7001")
  vim.env.JUMPGRAPH_ADDR = saved
  config.set({})
end)

print("install")
test("asset names", function()
  eq(install.asset_name("x86_64-unknown-linux-musl"), "jumpgraph-core-x86_64-unknown-linux-musl")
  eq(install.asset_name("x86_64-pc-windows-msvc"), "jumpgraph-core-x86_64-pc-windows-msvc.exe")
end)
test("url template + overrides", function()
  local saved = vim.env.JUMPGRAPH_CORE_URL
  vim.env.JUMPGRAPH_CORE_URL = nil
  config.set({})
  local m = install.manifest()
  local url = install.asset_url("A", "1.2.3")
  eq(url, (m.url:gsub("{version}", "1.2.3"):gsub("{asset}", "A")))
  assert(url:find("/core-v1.2.3/A", 1, true), url)
  vim.env.JUMPGRAPH_CORE_URL = "http://mirror/{version}/{asset}"
  eq(install.asset_url("A", "1"), "http://mirror/1/A")
  config.set({ core = { url = "file:///x/{asset}" } })
  eq(install.asset_url("A", "1"), "file:///x/A")
  vim.env.JUMPGRAPH_CORE_URL = saved
  config.set({})
end)
test("manifest is well-formed", function()
  local m = install.manifest()
  assert(type(m.version) == "string" and m.version:match("^%d+%.%d+%.%d+"), "version")
  eq(type(m.protocol), "number")
  for target, sum in pairs(m.assets) do
    assert(sum:match("^%x+$") and #sum == 64, "sha256 for " .. target)
  end
end)
test("override path must exist", function()
  config.set({ core = { path = "/definitely/not/here" } })
  local p, err = install.resolve()
  eq(p, nil)
  assert(err:find("missing file", 1, true), err)
  config.set({})
end)
test("unsupported build is reported, not downloaded", function()
  local saved = package.loaded["jumpgraph.manifest"]
  package.loaded["jumpgraph.manifest"] = { version = "9.9.9", protocol = 1, url = "http://x/{asset}", assets = {} }
  local path, err = install.install({ sync = true, quiet = true })
  package.loaded["jumpgraph.manifest"] = saved
  eq(path, nil)
  assert(err:find("no build for", 1, true) or err:find("no prebuilt", 1, true), err)
end)

print("symbols")
test("canonical kinds", function()
  eq(symbols.canonical_kind("method_definition"), "Method")
  eq(symbols.canonical_kind("function_declaration"), "Function")
  eq(symbols.canonical_kind("impl_item"), "Impl")
  eq(symbols.canonical_kind("mod_item"), "Module")
  eq(symbols.canonical_kind("weird"), "Symbol")
end)
test("enclosing function in a lua buffer", function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "local M = {}",
    "local function helper()",
    "  return 1",
    "end",
    "function M.run()",
    "  return helper()",
    "end",
    "return M",
  })
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  eq({ symbols.enclosing(buf) }, { "Function", "helper" })
  vim.api.nvim_win_set_cursor(0, { 6, 2 })
  eq({ symbols.enclosing(buf) }, { "Function", "M.run" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(symbols.enclosing(buf), nil)
end)

print("tracker")
test("ignores special buffers", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/jg-test-scratch")
  vim.bo[buf].buftype = "nofile"
  eq(tracker.file_of(buf), nil)
  vim.bo[buf].buftype = ""
  -- Neovim may resolve the path (macOS: /tmp -> /private/tmp; Windows: drive/slashes),
  -- so compare against what it reports rather than the literal we set.
  eq(tracker.file_of(buf), vim.api.nvim_buf_get_name(buf))
  assert(tracker.file_of(buf):find("jg-test-scratch", 1, true), "name should end up in the path")
end)

print("commands")
test("registered without setup(), nothing spawned", function()
  for _, c in ipairs({ "Start", "Stop", "Clear", "Open", "Mode", "Install", "Log" }) do
    eq(vim.fn.exists(":JumpGraph" .. c), 2, "JumpGraph" .. c)
  end
  eq(require("jumpgraph").status().core_running, false)
  local ok = pcall(vim.api.nvim_get_autocmds, { group = "jumpgraph.tracker" })
  eq(ok, false, "tracker autocmds must not exist before start")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
vim.cmd(failed == 0 and "qa!" or "cq!")
