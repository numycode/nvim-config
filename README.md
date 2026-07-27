# Neovim config

A hand-rolled Neovim IDE setup. No distro base — [lazy.nvim](https://github.com/folke/lazy.nvim)
plus a curated plugin set, built around Python and JavaScript.

Primary languages: **Python** (basedpyright, ruff, uv) and **JavaScript** (ts_ls, eslint, prettier).
TypeScript is deliberately not configured. Also covers Lua, Bash, HTML/CSS/SCSS, JSON, YAML,
TOML, Markdown, SQL and XML.

## Requirements

Neovim **0.12+** is required. The 0.11 APIs this config uses (`vim.lsp.config`,
`vim.lsp.foldexpr`, `vim.hl.on_yank`) are not the constraint — `nvim-treesitter`'s `main`
branch calls `vim.list.unique()`, which does not exist before 0.12, and parser installation
fails without it. No distribution packages 0.12 yet, so `install.sh` installs the upstream
tarball on Linux.

`./install.sh` installs all of this for you — see [Install](#install). The table below is
what it sets up, and what to install by hand on an unsupported platform.

### Required

| Tool | Used for | macOS | Debian / Ubuntu |
| --- | --- | --- | --- |
| `neovim` ≥ 0.12 | — | `brew install neovim` | installed from the upstream tarball by `install.sh` |
| `git` | lazy.nvim, Mason, gitsigns | preinstalled | `apt install git` |
| `curl`, `unzip`, `tar`, `gzip` | Mason downloads | preinstalled | `apt install curl unzip tar gzip` |
| C compiler + `make` | Treesitter parsers | `xcode-select --install` | `apt install build-essential` |
| `ripgrep` | picker grep | `brew install ripgrep` | `apt install ripgrep` |
| `fd` | picker file listing | `brew install fd` | `apt install fd-find` |
| `node` + `npm` | ts_ls, eslint, emmet, prettierd, tree-sitter CLI | `brew install node` | `apt install nodejs npm` |
| `python3` | basedpyright, ruff | preinstalled | `apt install python3` |
| `uv` | `:UvSync`, venv detection | `brew install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `lazygit` | git panel (`<leader>gz`) | `brew install lazygit` | see [lazygit install](https://github.com/jesseduffield/lazygit#installation) |
| `gh` | GitHub PR/issue review (`<leader>go`) — run `gh auth login` after | `brew install gh` | installed from the upstream release by `install.sh` |
| `wakatime-cli` | time tracking, statusline total | installed by `install.sh` to `~/.local/bin` | same |
| A Nerd Font | icons throughout | `brew install --cask font-jetbrains-mono-nerd-font` | [nerdfonts.com](https://www.nerdfonts.com/) |

### Optional

| Tool | Adds |
| --- | --- |
| `delta` | nicer lazygit diffs (`brew install git-delta`) |

## Install

### One command

Nothing needs to be installed first — not even git. The script clones the config to
`~/.config/nvim` for you, installs every dependency, and sets up plugins and language servers:

```sh
curl -fsSL https://raw.githubusercontent.com/numycode/nvim-config/main/install.sh | bash
```

Then run `nvim`. To pass flags through the pipe, use `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/numycode/nvim-config/main/install.sh | bash -s -- --check
```

Prefer to read it before running it — always reasonable for a piped installer:

```sh
curl -fsSL https://raw.githubusercontent.com/numycode/nvim-config/main/install.sh -o install.sh
less install.sh
bash install.sh
```

Installing a fork or branch:

```sh
NVIM_CONFIG_REPO=https://github.com/you/fork.git \
NVIM_CONFIG_BRANCH=my-branch \
  bash <(curl -fsSL https://raw.githubusercontent.com/numycode/nvim-config/main/install.sh)
```

### From a clone

```sh
git clone https://github.com/numycode/nvim-config.git ~/.config/nvim
cd ~/.config/nvim
./install.sh
```

It is safe to re-run — every step checks before acting. Run from a clone anywhere else and it
symlinks that directory to `~/.config/nvim`; an existing config is moved aside to
`~/.config/nvim.bak.<timestamp>` after asking.

| Flag | Effect |
| --- | --- |
| `--check` | Report what is missing, change nothing |
| `--dry-run` | Print the commands instead of running them |
| `-y`, `--yes` | Do not prompt |
| `--skip-font` | Do not install the Nerd Font |
| `--skip-optional` | Do not install `delta` |
| `--no-sync` | Do not run the headless plugin/LSP install |

Several tools come from upstream rather than the system package manager, because the packaged
versions are too old or missing:

- **Neovim** — whenever the packaged build is older than 0.12, which today means every
  distribution (Debian stable ships 0.10.4, Ubuntu 0.11.6, Fedora 41 0.10.4). Installed to
  `/opt/nvim` with a symlink in `/usr/local/bin`.
- **lazygit** — absent from Debian bookworm. Installed to `~/.local/bin`.
- **gh** — likewise absent from Debian bookworm. Installed to `~/.local/bin`.
- **uv** — via the official Astral installer.
- **wakatime-cli** — not packaged anywhere. Installed to `~/.local/bin`; see
  [Time tracking](#time-tracking).

On Debian the `fd` binary is installed as `fdfind`; the script symlinks it to `~/.local/bin/fd`
because the snacks picker looks for `fd`. If `~/.local/bin` is not on your `PATH`, the script
adds it for its own run and tells you to persist it in your shell profile.

The final step runs `:Lazy restore`, which installs the exact commits pinned in
`lazy-lock.json` rather than updating to latest, then loads the LSP stack so Mason downloads
the language servers during setup rather than during your first edit. Run `:Lazy update`
yourself when you actually want newer plugins.

### Manual

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
install.sh                cross-platform installer (macOS / Debian / Fedora)
init.lua                  leader keys, config.* requires, lazy.nvim bootstrap
lua/config/
  options.lua             vim.opt, folding, diagnostics presentation
  keymaps.lua             plugin-independent keymaps
  autocmds.lua            yank highlight, cursor restore, LspAttach, mkdir-on-write
  lsp.lua                 capabilities + on_attach (buffer-local LSP keymaps)
  servers.lua             LSP servers and their settings (read by install.sh)
  parsers.lua             treesitter parsers + install (read by install.sh)
  tools.lua               formatters/linters for Mason (read by install.sh)
  python.lua              venv auto-detection, :UvSync / :UvAdd / :UvRun / :RuffCheck
lua/plugins/
  snacks.lua              picker, explorer, dashboard, terminal, lazygit, notifier
  ui.lua                  lualine (branch + ahead/behind), bufferline, dropbar,
                          treesitter-context, which-key
  colorscheme.lua         tokyonight (default), catppuccin, gruvbox-material
  completion.lua          blink.cmp, LuaSnip, autopairs
  lsp.lua                 server table, mason + mason-lspconfig
  treesitter.lua          parsers, textobjects, structural motions
  editor.lua              trouble, todo-comments, aerial, flash, surround,
                          multicursor, refactoring, persistence
  git.lua                 gitsigns, diffview, neogit, git-conflict
  github.lua              octo (GitHub PR/issue review)
  formatting.lua          conform, format on save
  hackatime.lua           time tracking
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
| `<leader>g` | **git** — `gg` panel, `gc` commit, `gp` pull, `gP` push, `gl` history graph, `gz` lazygit, `gs` changed files, `gb` switch branch, `gC` search commits, `gL` commits touching this line, `gS` stashes, `gd` review changes, `gf` file history, `gB` open on GitHub |
| `<leader>gh` | **changes in this file** — `ghs` stage, `ghr` reset, `ghp` preview, `ghb` blame, `ghB` blame toggle, `ghd` diff |
| `<leader>go` | **github** — `gop` PRs, `goi` issues, `gor` start review, `gon` notifications (needs `gh auth login`) |
| `<leader>gx` | **conflict** — `gxo` ours, `gxt` theirs, `gxb` both, `gxn` neither, `gxq` quickfix |
| `<leader>x` | **diagnostics** — `xx` workspace, `xX` buffer, `xs` symbols, `xt` TODOs, `xq` quickfix, `xL` loclist |
| `<leader>u` | **UI toggles** — `uC` colorscheme, `uh` inlay hints, `uw` wrap, `ul` relative numbers, `ud` diagnostics, `uF` format on save, `uc` sticky context |
| `<leader>b` | **buffer** — `bd` delete, `bo` delete others, `bn` next, `bb` alternate, `bp` pin |
| `<leader>r` | **refactor** — `rr` menu, `rf` extract function, `rv` extract variable, `ri` inline variable |
| `<leader>m` | **multicursor** — `ma` cursor at next match, `mA` prev match, `ms` skip, `mm` all matches, `ml` split selection |
| `<leader>S` | **session** — `Ss` restore, `Sl` last, `Sd` stop saving |
| `<leader>t` | **terminal** — `tt` float |

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
| `]x` `[x` | Next/prev merge conflict |
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

### Git, by task

The git UI is [Neogit](https://github.com/NeogitOrg/neogit) — a panel where you stage and
commit, opened with `<leader>gg` or the `󰊢` button in the status bar. If you are not fluent in
git, this table is the short version. Every key below also shows up in which-key.

| I want to… | Do this |
| --- | --- |
| See what I have changed | `<leader>gg`. The panel lists **untracked**, **unstaged** and **staged** files |
| Mark a file to be committed | Put the cursor on it in the panel, press `s` ("stage"). `u` undoes that |
| Mark only part of a file | `<tab>` on the file expands it into chunks; `s` stages the chunk under the cursor |
| …or from the file itself | `<leader>ghs` stages the chunk you are sitting on, `<leader>ghr` throws it away |
| Commit what I staged | `<leader>gc`, then `c` from the menu. Type a message, then `<C-c><C-c>` to commit (`<C-c><C-k>` cancels) |
| Undo a change I have not committed | `<leader>ghr` on that chunk, or `x` on the file in the panel |
| Send my commits to GitHub | `<leader>gP` (capital P — **P**ush) |
| Get everyone else's commits | `<leader>gp` (**p**ull) |
| Know if I am out of sync | The status bar shows `↑2` (2 unsent) or `↓1` (1 waiting). Click it to act |
| Look at the history | `<leader>gl` for the graph, `<leader>gf` for just this file |
| See who wrote a line | `<leader>ghb` |
| Fix a merge conflict | `]x` jumps to one; `<leader>gxo` keeps **my** version, `<leader>gxt` keeps **theirs** |
| Switch branch | `<leader>gb` |
| Put changes aside for later | `<leader>gS` (stashes) |
| Amend, force-push, rebase, … | `<leader>gg`, then `c`, `P`, `p`, `b`, `Z` open the full menus |

Inside the panel, `?` lists every key, and the hint line along the top always shows the main
ones. The leader keys deliberately do the *ordinary* thing without asking; the panel's own
`c`/`p`/`P` keys open the full menus with all the flags when you want them.

> **staged vs unstaged** — git commits only what you have *staged*. Editing a file makes it
> unstaged; `s` stages it; `<leader>gc` commits everything staged and nothing else. That is why
> a commit can quietly leave out a file you forgot to stage — the panel shows you, in sections,
> exactly what is about to go in.

### Clickable

`mouse = "a"` is set, so the bars are mouse targets as well as displays:

| Target | Click opens |
| --- | --- |
| ` Files` (tab bar, left) | The explorer sidebar |
| `󰊢` (status bar) | Neogit — the same thing as `<leader>gg`. Hidden outside a git repo |
| Branch name (status bar) | Branch picker |
| `↑`/`↓` divergence (status bar) | `↑` alone pushes, `↓` alone pulls, both opens the panel. Shown only when the branch has diverged |
| Breadcrumbs (dropbar) | The symbol menu at that level |

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
| `:WakaTimeToday` | Today's total as a notification |
| `:WakaTimeApiKey` | Set the API key (**rewrites `~/.wakatime.cfg`**) |
| `:WakaTimeCliLocation` | Which `wakatime-cli` binary is in use |

## Time tracking

Heartbeats go to a self-hosted [Hackatime](https://hackatime.hackclub.com) instance via
`vim-wakatime`. Today's total sits in the statusline, left of the LSP client list:

```
 NORMAL   main  init.lua        󱑆 2h 54m   basedpyright, ruff   python   33%   20:1
```

It refreshes from `wakatime-cli --today` at most once a minute, and renders nothing at all
until the first result arrives — or if the call fails, since the CLI writes errors only to
stderr.

Configuration lives in `~/.wakatime.cfg`, which is **hand-maintained — the installer never
reads, merges or overwrites an existing one.** On a machine that has no such file yet:

| Variable | Effect |
| --- | --- |
| `HACKATIME_API_KEY` | Key to write. `WAKATIME_API_KEY` is accepted as a fallback. |
| `HACKATIME_API_URL` | Server, defaulting to `https://hackatime.hackclub.com/api/hackatime/v1` |

```sh
HACKATIME_API_KEY=... ./install.sh
```

With neither set the installer writes nothing and tells you to run `:WakaTimeApiKey` instead.
Note that `:WakaTimeApiKey`, `:WakaTimeStatusBar*` and `:WakaTimeDebug*` all rewrite the cfg;
the settings this config cares about are passed in Lua instead, from
`lua/plugins/hackatime.lua`.

`:WakaTimeFileExpert` and today-goal reporting are wakatime.com features and return nothing
against a Hackatime backend.

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
| `nvim` (dashboard) | ~85 ms |
| `nvim file.py` (full LSP path) | ~130 ms |

The LSP chain — mason-lspconfig, blink.cmp, LuaSnip — is deferred to `BufReadPre`, so
opening the dashboard never pays for it. Profile with `:Lazy profile` or
`nvim --startuptime /tmp/st.log`.
