# Neovim config

A hand-rolled Neovim IDE setup. No distro base — [lazy.nvim](https://github.com/folke/lazy.nvim)
plus a curated plugin set, built around Python and JavaScript.

Primary languages: **Python** (basedpyright, ruff, uv) and **JavaScript** (ts_ls, eslint, prettier).
TypeScript is deliberately not configured. Also covers Lua, Bash, HTML/CSS/SCSS, JSON, YAML,
TOML, Markdown, SQL and XML.

## Requirements

Neovim **0.11+** is required (`vim.lsp.config`, `vim.lsp.foldexpr`, `vim.hl.on_yank`);
developed against 0.12.

### Required

| Tool | Used for | macOS | Debian / Ubuntu |
| --- | --- | --- | --- |
| `neovim` ≥ 0.11 | — | `brew install neovim` | `apt install neovim` |
| `git` | lazy.nvim, Mason, gitsigns | preinstalled | `apt install git` |
| `curl`, `unzip`, `tar`, `gzip` | Mason downloads | preinstalled | `apt install curl unzip tar gzip` |
| C compiler + `make` | Treesitter parsers | `xcode-select --install` | `apt install build-essential` |
| `ripgrep` | picker grep | `brew install ripgrep` | `apt install ripgrep` |
| `fd` | picker file listing | `brew install fd` | `apt install fd-find` |
| `node` + `npm` | ts_ls, eslint, emmet, prettierd, tree-sitter CLI | `brew install node` | `apt install nodejs npm` |
| `python3` | basedpyright, ruff | preinstalled | `apt install python3` |
| `uv` | `:UvSync`, venv detection | `brew install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `lazygit` | git panel (`<leader>gg`) | `brew install lazygit` | see [lazygit install](https://github.com/jesseduffield/lazygit#installation) |
| A Nerd Font | icons throughout | `brew install --cask font-jetbrains-mono-nerd-font` | [nerdfonts.com](https://www.nerdfonts.com/) |

### Optional

| Tool | Adds |
| --- | --- |
| `gh` | GitHub issue/PR pickers |
| `delta` | nicer lazygit diffs (`brew install git-delta`) |

## Install

```sh
git clone https://github.com/numycode/nvim-config.git ~/.config/nvim
cd ~/.config/nvim && npm install   # provides the tree-sitter CLI for parser builds
nvim                               # lazy.nvim bootstraps, Mason installs servers
```

`npm install` is what supplies the `tree-sitter` CLI used to compile parsers.
`lua/plugins/treesitter.lua` prefers a system `tree-sitter` if one is on `$PATH` and falls
back to the local `node_modules` copy. A system-wide install works equally well:

```sh
cargo install tree-sitter-cli   # or: npm install -g tree-sitter-cli
```

First launch downloads plugins and language servers, so give it a minute. Check progress
with `:Lazy` and `:Mason`, then `:checkhealth`.

### Platform notes

- **blink.cmp** ships a prebuilt Rust fuzzy matcher, downloaded on first run. On a platform
  with no prebuilt binary, set `fuzzy = { implementation = "lua" }` in
  `lua/plugins/completion.lua`.
- **Terminal**: designed for terminals that cannot send `Ctrl+Shift` chords (iTerm2, Terminal.app).
  All commands are reachable through `<leader>` mappings, so nothing depends on exotic key
  reporting.

## Layout

```
init.lua                  leader keys, config.* requires, lazy.nvim bootstrap
lua/config/
  options.lua             vim.opt, folding, diagnostics presentation
  keymaps.lua             plugin-independent keymaps
  autocmds.lua            yank highlight, cursor restore, LspAttach, mkdir-on-write
  lsp.lua                 capabilities + on_attach (buffer-local LSP keymaps)
  python.lua              venv auto-detection, :UvSync / :UvAdd / :UvRun / :RuffCheck
lua/plugins/
  snacks.lua              picker, explorer, dashboard, terminal, lazygit, notifier
  ui.lua                  lualine, bufferline, dropbar, treesitter-context, which-key
  colorscheme.lua         tokyonight (default), catppuccin, gruvbox-material
  completion.lua          blink.cmp, LuaSnip, autopairs
  lsp.lua                 server table, mason + mason-lspconfig
  treesitter.lua          parsers, textobjects, structural motions
  editor.lua              trouble, todo-comments, aerial, flash, surround,
                          multicursor, refactoring, persistence
  git.lua                 gitsigns, diffview
  formatting.lua          conform, format on save
  wakatime.lua            time tracking
```

## Keymaps

Leader is `<Space>`, local leader is `\`. Press `<Space>` and wait — **which-key** lists
everything. `<leader>sk` searches all keymaps.

### Top level

| Key | Action |
| --- | --- |
| `<leader><space>` | Smart find files |
| `<leader>/` | Grep project |
| `<leader>,` | Buffers |
| `<leader>e` | File explorer (sidebar) |
| `<leader>n` | Notification history |
| `<leader>w` / `<leader>q` / `<leader>Q` | Write / quit window / quit all |
| `<leader>?` | Buffer-local keymaps |

### Groups

| Prefix | Contents |
| --- | --- |
| `<leader>f` | **find** — `ff` files, `fr` recent, `fb` buffers, `fp` projects, `fg` git files, `fc` config, `fn` new file |
| `<leader>s` | **search** — `sg` grep, `sw` word/selection, `sd` diagnostics, `sk` keymaps, `sh` help, `su` undo, `sR` resume, `st` TODOs |
| `<leader>c` | **code** — `ca` action, `cr` rename, `cR` rename file, `cf` format, `cd` line diagnostics, `cs` symbols, `cO` outline, `cv` Python interpreter, `cx`/`cX` swap parameter |
| `<leader>g` | **git** — `gg` lazygit, `gs` status, `gb` branches, `gl` log, `gd` diffview, `gf` file history, `gB` open in browser |
| `<leader>gh` | **hunk** — `ghs` stage, `ghr` reset, `ghp` preview, `ghb` blame, `ghB` blame toggle, `ghd` diff |
| `<leader>x` | **diagnostics** — `xx` workspace, `xX` buffer, `xs` symbols, `xt` TODOs, `xq` quickfix, `xL` loclist |
| `<leader>u` | **UI toggles** — `uC` colorscheme, `uh` inlay hints, `uw` wrap, `ul` relative numbers, `ud` diagnostics, `uF` format on save, `uc` sticky context |
| `<leader>b` | **buffer** — `bd` delete, `bo` delete others, `bn` next, `bb` alternate, `bp` pin |
| `<leader>r` | **refactor** — `rr` menu, `rf` extract function, `rv` extract variable, `ri` inline variable |
| `<leader>m` | **multicursor** — `ma` cursor at next match, `mA` prev match, `ms` skip, `mm` all matches, `ml` split selection |
| `<leader>S` | **session** — `Ss` restore, `Sl` last, `Sd` stop saving |
| `<leader>t` | **terminal** — `tt` float, `tg` lazygit |

### LSP (buffer-local)

`gd` definition · `gD` declaration · `gr` references · `gI` implementation · `gy` type definition ·
`K` hover · `gK` signature help

### Motions

| Key | Action |
| --- | --- |
| `s` / `S` | Flash jump / treesitter jump |
| `<S-h>` / `<S-l>` | Previous / next buffer |
| `]d` `[d` / `]e` `[e` | Next/prev diagnostic / error |
| `]h` `[h` | Next/prev git hunk |
| `]f` `[f` / `]c` `[c` / `]a` `[a` | Next/prev function / class / parameter |
| `]t` `[t` | Next/prev TODO |
| `]]` `[[` | Next/prev reference to symbol under cursor |
| `<C-Up>` / `<C-Down>` | Add cursor above / below |
| `<C-/>` | Toggle terminal |

With multiple cursors active: `<left>`/`<right>` cycle between cursors, `<Esc>` clears them.
In visual mode `I` and `A` insert at the start/end of every selected line — a superset of
the built-in visual-block `I`/`A`, which also works charwise and linewise.

### Text objects

`af`/`if` function · `ac`/`ic` class · `aa`/`ia` parameter · `ai`/`ii` conditional ·
`al`/`il` loop · `ih` git hunk

### Completion (blink.cmp)

`<Tab>` accept · `<Tab>`/`<S-Tab>` cycle and jump between snippet placeholders ·
`<C-space>` open menu or docs · `<C-e>` hide · `<C-k>` signature help.

This is the `super-tab` preset, matching JetBrains. Switch to `preset = "default"` in
`lua/plugins/completion.lua` for vim-native `<C-y>` behaviour.

## Commands

| Command | Does |
| --- | --- |
| `:UvSync` | `uv sync` in the project root |
| `:UvAdd <pkg>...` | `uv add` |
| `:UvRun <cmd>...` | `uv run` |
| `:RuffCheck` | `ruff check .` (falls back to `uvx ruff`) |
| `:PythonVenv` | Show and re-apply the detected interpreter |
| `:FormatDisable[!]` | Disable format on save (`!` = current buffer) |
| `:FormatEnable` | Re-enable format on save |
| `:ConformInfo` | Formatter status for the buffer |

## Notes

- **Python interpreter** is detected automatically from `$VIRTUAL_ENV`, `.venv`, `venv` or
  `.env` under the project root and pushed into basedpyright. Without this, third-party imports
  resolve against the system interpreter and show as unresolved. `:PythonVenv` reports what
  was picked.
- **Inlay hints** are on by default where the server supports it. Python uses
  **basedpyright** rather than pyright precisely because pyright does not implement
  `textDocument/inlayHint`. Toggle hints with `<leader>uh`.
- **Only the servers listed in `lua/plugins/lsp.lua` run.** `automatic_enable` is off, so a
  server left installed in Mason after you remove it from that table will not attach.
- **Remote provider hosts are disabled** (`python3`, `perl`, `ruby`, `node`). Nothing here uses
  them, and probing the python3 provider cost ~160 ms on the first Python buffer. Re-enable by
  deleting the `loaded_*_provider` lines in `lua/config/options.lua` if you add a plugin that
  needs `:python3`.
- **Folding** uses the built-in `vim.lsp.foldexpr()`, so no nvim-ufo. Folds start open
  (`foldlevel = 99`).
- **`H` and `L`** are remapped to buffer navigation, shadowing the built-in
  screen-top/screen-bottom motions. Use `gg`/`G` or `zt`/`zb`.
- **Format on save** is on for all configured filetypes, with LSP formatting as fallback.
- `lazy-lock.json` is committed; run `:Lazy restore` to pin the exact plugin set.

## Startup

35 plugins. Warm timings, against ~64 ms for bare `nvim -u NONE`:

| | Time |
| --- | --- |
| `nvim` (dashboard) | ~96 ms |
| `nvim file.py` (full LSP path) | ~175 ms |

The LSP chain — mason-lspconfig, blink.cmp, LuaSnip — is deferred to `BufReadPre`, so
opening the dashboard never pays for it. Profile with `:Lazy profile` or
`nvim --startuptime /tmp/st.log`.
