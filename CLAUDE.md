# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A hand-rolled Neovim IDE configuration — no distro base. lazy.nvim plus ~35 curated plugins,
built for **Python** and **JavaScript**. The owner comes from JetBrains, so the bar is
"an IDE's features are present and discoverable", not "a minimal vim setup".

**TypeScript is deliberately not configured.** `ts_ls` is restricted to `javascript` and
`javascriptreact` filetypes. Do not add TypeScript support without being asked.

Also deliberately absent, by the owner's explicit decision: **DAP/debugging**, **test runners**
(neotest), and **AI plugins**. Do not add them unprompted.

## Hard requirements

**Neovim 0.12+.** Not 0.11 — that was wrong and cost real debugging time. `nvim-treesitter`'s
`main` branch calls `vim.list.unique()`, which does not exist before 0.12; parser installation
fails with `attempt to index field 'list' (a nil value)`. No distribution packages 0.12 yet,
so `install.sh` installs the upstream tarball on Linux.

The config also uses 0.11 APIs (`vim.lsp.config`, `vim.lsp.foldexpr`, `vim.hl.on_yank`), but
treesitter is the binding constraint.

## Layout

```
install.sh              cross-platform installer; also curl-able (clones the repo itself)
init.lua                leader keys, config.* requires, lazy.nvim bootstrap
lua/config/
  options.lua           vim.opt, folding, diagnostics presentation, provider disabling
  keymaps.lua           plugin-independent keymaps only
  autocmds.lua          yank highlight, cursor restore, LspAttach, mkdir-on-write
  lsp.lua               capabilities() + on_attach() (buffer-local LSP keymaps)
  servers.lua           LSP servers + settings          <- also read by install.sh
  parsers.lua           treesitter parsers + ensure()   <- also read by install.sh
  tools.lua             Mason formatters/linters        <- also read by install.sh
  python.lua            venv auto-detection, :UvSync / :UvAdd / :UvRun / :RuffCheck
lua/plugins/            one file per concern; lazy.nvim specs
```

### The three shared modules

`servers.lua`, `parsers.lua` and `tools.lua` exist so `install.sh` can enumerate what the
config needs and pre-install it. **They are the single source of truth.** If you add a
language server, parser or formatter, add it there — not inline in a plugin spec — or the
installer will not know about it.

## Things that will bite you

These were all found the hard way. Do not undo them.

**LSP is lazy-loaded on `BufReadPre`.** This keeps bare `nvim` at ~96ms. The consequence:
a headless run with no file open never loads `mason-lspconfig`, so Mason installs nothing.
`install.sh` therefore calls `require("lazy").load({...})` explicitly. Any script that expects
LSP or Mason must do the same.

**Mason's registry is empty until refreshed.** `get_all_packages()` returns `0` on a fresh
machine and `587` after `registry.refresh()`. A wait loop that polls `is_installing()` before
the refresh completes will exit immediately having installed nothing. Always refresh first.

**Treesitter parsers are not installed by lazy's `build`.** `build` only runs when the plugin
itself is installed or updated, so adding a parser to `parsers.lua` would never fetch it.
Installation lives in `config.parsers.ensure()`, called async from `treesitter.lua` at startup
and synchronously by `install.sh`.

**`vim.treesitter.language.add()` is not proof a parser works.** It returns true without a
usable parser. Verify with `vim.treesitter.start()`, `get_installed("parsers")`, or
`get_captures_at_pos()`. Coloured output in a terminal is not proof either — Neovim falls back
to legacy regex syntax, which looks similar.

**`get_installed()` returns queries; `get_installed("parsers")` returns parsers.** The bare
call returns `{"html_tags"}` and means nothing.

**Wait for the right number of LSP clients.** Python attaches two (`basedpyright` and `ruff`)
and JavaScript one. `ruff` is a Rust binary and attaches almost immediately; `basedpyright` is
a Node server and takes several seconds longer. A probe that waits for `>= 1` client returns
while only `ruff` is up and looks exactly like "basedpyright is broken" — that mistake cost a
full debugging cycle. Wait for `>= 2` on Python, then sleep briefly before sampling inlay hints,
which need basedpyright.

**pyright is not used — basedpyright is.** pyright does not implement
`textDocument/inlayHint`; basedpyright is a drop-in fork that does.

**`mason-lspconfig` has `automatic_enable = false`.** It otherwise attaches every server
installed in Mason, so removing one from `servers.lua` would not stop it running. Servers are
enabled explicitly via `vim.lsp.enable()`.

**Remote provider hosts are disabled** (`python3`, `perl`, `ruby`, `node`) in `options.lua`.
vim-wakatime probes `has('python3')`, and Neovim answered by spawning an interpreter — ~160ms
on the first Python buffer.

**`vim.g.python3_host_prog` is deliberately not set** by the venv detection. It names the
interpreter hosting Neovim's `:python3` provider (which needs pynvim), not the project
interpreter. The LSP path travels via `python.pythonPath`.

**On Debian, `fd` is installed as `fdfind`.** The snacks picker shells out to `fd`;
`install.sh` symlinks it into `~/.local/bin`.

**Mason installs `basedpyright` and `ruff` from PyPI into a venv.** Debian and Fedora ship
`pip` separately from `python3`; without `python3-pip` (and `python3-venv` on Debian) those two
fail silently while everything else succeeds.

## Conventions

- **Formatting**: `.stylua.toml`, 2-space indent, 120 columns,
  `collapse_simple_statement = "FunctionOnly"` so keymap tables stay readable. Run
  `stylua init.lua lua/` before committing; format-on-save does it in-editor.
- **Shell**: `install.sh` must stay `shellcheck -S style` clean.
- **Keymaps**: plugin keymaps live with their plugin spec (`keys = {}`); only
  plugin-independent ones go in `lua/config/keymaps.lua`. Every mapping needs a `desc` —
  which-key is the discovery mechanism and the JetBrains-muscle-memory replacement.
- **Leader groups**: `f` find, `s` search, `c` code, `g` git (`gh` hunks), `x` diagnostics,
  `u` UI toggles, `b` buffer, `S` session, `t` terminal, `m` multicursor, `r` refactor.
- **Lockfile**: `lazy-lock.json` is committed. `install.sh` runs `:Lazy restore`, never
  `sync` — `sync` updates everything and rewrites the lockfile.
- **`node_modules/` is gitignored.** It holds a platform-specific tree-sitter binary; it was
  once committed (25MB, macOS-arm64) which broke portability. Fresh clones run `npm install`.

## Verifying changes

Config loads cleanly (must print nothing):

```sh
nvim --headless -c 'qa'
```

Functional check — do this rather than trusting that a plugin loaded:

```sh
nvim --headless some.py -c 'lua
  vim.wait(25000, function() return #vim.lsp.get_clients({bufnr=0}) >= 2 end, 250)
  local b = vim.api.nvim_get_current_buf()
  for _, c in ipairs(vim.lsp.get_clients({bufnr=b})) do print(c.name) end
  print("ts: " .. tostring(vim.treesitter.highlighter.active[b] ~= nil))
  print("captures: " .. #vim.treesitter.get_captures_at_pos(b, 2, 8))
  print("inlay: " .. tostring(vim.lsp.inlay_hint.is_enabled({bufnr=b})))
' -c qa
```

Startup budget — bare `nvim` ~85ms, `nvim file.py` ~130ms, against ~64ms for `nvim -u NONE`.
Treat a regression past ~120ms bare as a bug, usually something loading eagerly:

```sh
nvim --startuptime /tmp/st.log -c 'qa' && tail -1 /tmp/st.log
```

`:checkhealth` should be clean. Ignore `snacks.image` complaints about kitty/magick/mmdc, and
the `vim.ui.input`/`vim.ui.select` errors under `--headless` — snacks wires those on `UIEnter`,
which never fires without a UI. Verify with a real PTY (`script -q /dev/null nvim ...`).

## Testing installer changes

`install.sh` cannot be meaningfully validated by reading it. Apple's `container` CLI is
available on this machine:

```sh
# Bootstrap path (clones from GitHub), exactly as `curl ... | bash -s --` behaves:
container run --rm -i docker.io/library/ubuntu:latest bash -s -- --check < install.sh

# Same, with a copy of just the script mounted so local edits are exercised:
mkdir -p /tmp/m && cp install.sh /tmp/m/
container run --rm -v /tmp/m:/mnt docker.io/library/debian:latest \
  bash /mnt/install.sh --yes --skip-font
```

Mount only the script, never the whole repo: `is_config_repo()` would then be true for the
mount point, and the run would exercise the symlink path instead of the clone path.

Caveats learned:

- The installer **clones the config from GitHub**, so unpushed local changes to anything other
  than `install.sh` are not tested. Push first, or the container silently runs an old config
  against a new script — which looks exactly like a code bug.
- Container images are large. This machine has run low on disk; check `df -h /` first and
  `container image delete` what you pulled.
- Apple's runtime is arm64-only, so x86_64 paths remain unexercised.
- A full run takes 10-20 minutes, mostly Mason. Run it in the background.

## Style of work expected here

Report what was measured, not what should follow from the code. Several bugs in this repo
survived because a plausible-looking check (`language.add`, coloured terminal output, a plugin
being `loaded`) was accepted as proof. When something is unverified, say so.
