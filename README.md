# jumpgraph.nvim

A live map of how you navigate a codebase. While you explore, jumpgraph
records where you go as a graph and shows it in your browser, so a long,
branching dive into unfamiliar code stays legible.

- **File mode**: one node per file, one edge per jump. Revisited files grow,
  and frequently travelled paths pull together.
- **Treesitter mode**: one node per function / method / class / impl, with
  jumps between symbols. Laid out as a hierarchy.
- Nodes also grow with cursor activity and dwell time, so "where I actually
  spent time" stands out.
- The browser view has live settings and clutter controls: hide one-off
  edges, merge A↔B, fade old edges, show only the last N jumps, dim edges
  away from the active node.

Nothing runs until you `:JumpGraphStart`: no process, no port, no autocmds.

## Install

Requires Neovim **0.11+** and `curl` (to fetch the core binary once).

```lua
-- lazy.nvim
{
  "kshksdrt/jumpgraph.nvim",
  build = function() require("jumpgraph.install").install({ sync = true }) end,
  cmd = { "JumpGraphStart", "JumpGraphOpen" },
  opts = {}, -- optional, see Configuration
}
```

The `build` step is optional. Without it, the binary is downloaded on the
first `:JumpGraphStart`. Check the result with `:checkhealth jumpgraph`.

## Use

| Command | |
|---|---|
| `:JumpGraphStart` | Start tracking. Prints the UI URL (default `http://127.0.0.1:9001/`). |
| `:JumpGraphOpen` | Open the UI in your browser, starting tracking if needed. |
| `:JumpGraphStop` | Stop tracking and free the port. The graph is kept for the next start. |
| `:JumpGraphClear` | Wipe the graph (the UI's **Clear** button does the same). |
| `:JumpGraphMode file\|treesitter` | Switch what is tracked. Clears the graph. |
| `:JumpGraphInstall[!]` | Download the pinned core binary (`!` reinstalls). |
| `:JumpGraphLog` | Open the core's log. |

Lua: `require("jumpgraph").start() / stop() / clear() / open() / set_mode(m) / status()`.

## Configuration

Everything is optional:

```lua
require("jumpgraph").setup({
  addr = "127.0.0.1:9001",   -- or $JUMPGRAPH_ADDR (one per Neovim instance)
  open_browser = false,       -- open the UI on start
  mode = "file",              -- "file" | "treesitter"
  -- Activity weighting (also editable live in the UI's ⚙ Settings):
  activity_base = 1.0,        -- first increment
  activity_decay = 0.5,       -- each further increment ×= decay
  activity_throttle_ms = 120, -- cursor sampling interval
  poll_interval_ms = 3000,    -- dwell-time tick
  draw_back_edges = true,     -- false: returning to the previous node draws no arrow
  ignore_buftypes = { "terminal", "prompt", "quickfix", "nofile" },
  core = {
    path = nil,          -- use your own core binary ($JUMPGRAPH_CORE); skips download
    auto_install = true, -- download on first start if missing
    url = nil,           -- mirror: template with {version} and {asset} ($JUMPGRAPH_CORE_URL)
    install_dir = nil,   -- default: stdpath("data")/jumpgraph/bin
  },
})
```

## How it works

```
Neovim (this plugin, Lua) ──stdin/stdout NDJSON──▶ jumpgraph-core ──HTTP + websocket──▶ browser
```

The plugin is the editor half. Autocmds report where you are: the file on
`BufEnter`, and the enclosing treesitter symbol on a throttled `CursorMoved`.
They send it to the **core**, a small native process that keeps the graph and
serves the UI and its websocket on a single localhost port. The core is
closed source and ships as prebuilt binaries (see below).

The core binds `127.0.0.1` only. It accepts websocket connections only from
its own UI's origin, so other web pages you visit can't read your file paths
from it. When Neovim exits (or crashes), the core sees its stdin close and
shuts down, releasing the port.

### The core binary: where it comes from

- Each core version is published as assets on this repo's
  [releases](https://github.com/kshksdrt/jumpgraph.nvim/releases) (tag
  `core-v<version>`), one static binary per platform, plus `SHA256SUMS`.
- [`lua/jumpgraph/manifest.lua`](lua/jumpgraph/manifest.lua) pins the version
  and the **SHA-256 of every build**. The plugin downloads only your platform's
  asset and refuses to install it unless the hash matches. Binaries change only
  when you update the plugin, and you can review the new pins in that commit.
- Binaries are stored per version under `stdpath("data")/jumpgraph/bin`, and
  old versions are removed.
- On startup the plugin and core exchange a protocol version, and a mismatched
  binary is refused.

| Platform | Asset |
|---|---|
| Linux x86_64 / aarch64 (any distro, static musl) | `jumpgraph-core-{x86_64,aarch64}-unknown-linux-musl` |
| macOS Intel / Apple silicon | `jumpgraph-core-{x86_64,aarch64}-apple-darwin` |
| Windows x86_64 | `jumpgraph-core-x86_64-pc-windows-msvc.exe` |

**Offline or air-gapped?** Download the asset and `SHA256SUMS` from the release
yourself, verify with `sha256sum -c`, then set `core = { path = "/path/to/it" }`.

### Host protocol (plugin ⇄ core)

One JSON object per line. The full contract is in `lua/jumpgraph/core.lua`.

| plugin → core | core → plugin |
|---|---|
| `{"op":"hello","protocol":1}` | `{"ev":"hello","version":"…","protocol":1}` |
| `{"op":"configure", …tunables}` | `{"ev":"config", mode, activity_*, poll_interval_ms, draw_back_edges}` |
| `{"op":"start","addr":"…","location":{"file":"…"}}` | `{"ev":"started","addr":"…","url":"…"}` |
| `{"op":"visit","location":{"file","symbol?","kind?"},"activity":bool}` | |
| `{"op":"activity"}` · `{"op":"clear"}` · `{"op":"stop"}` · `{"op":"shutdown"}` | `{"ev":"cleared","by_client":bool}` · `{"ev":"stopped"}` · `{"ev":"error","op","message"}` |

## Development

```bash
nvim --clean --headless --cmd "set rtp^=." -l tests/run.lua
```

## License

The plugin (everything in this repository) is [MIT](LICENSE). The core binaries
attached to releases are proprietary, free to use with this plugin. See
[LICENSE-core.md](LICENSE-core.md).
