-- Which prebuilt core binary fits this machine.
local M = {}

-- (sysname, machine) → Rust target triple of the published build. Linux builds
-- are static musl binaries, so they run on any distro regardless of glibc.
local TARGETS = {
  Linux = { x86_64 = "x86_64-unknown-linux-musl", aarch64 = "aarch64-unknown-linux-musl" },
  Darwin = { x86_64 = "x86_64-apple-darwin", arm64 = "aarch64-apple-darwin" },
  Windows_NT = { x86_64 = "x86_64-pc-windows-msvc" },
}

local MACHINE_ALIASES = { amd64 = "x86_64", AMD64 = "x86_64", x64 = "x86_64", arm64 = "arm64", aarch64 = "aarch64" }

--- @param uname? { sysname: string, machine: string } defaults to vim.uv.os_uname()
--- @return string? target, string? err
function M.target(uname)
  uname = uname or vim.uv.os_uname()
  local sys, machine = uname.sysname, MACHINE_ALIASES[uname.machine] or uname.machine
  if sys:match("^MINGW") or sys:match("^MSYS") then
    sys = "Windows_NT"
  end
  local by_machine = TARGETS[sys]
  if by_machine then
    -- Darwin reports arm64, Linux aarch64; accept either spelling for both.
    local t = by_machine[machine]
      or (machine == "arm64" and by_machine.aarch64)
      or (machine == "aarch64" and by_machine.arm64)
    if t then
      return t
    end
  end
  return nil, ("no prebuilt jumpgraph core for %s/%s"):format(uname.sysname, uname.machine)
end

function M.is_windows()
  return vim.uv.os_uname().sysname == "Windows_NT"
end

function M.exe_suffix()
  return M.is_windows() and ".exe" or ""
end

return M
