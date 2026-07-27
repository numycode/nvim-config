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

**`showtabline` belongs to us, not to bufferline.** `auto_toggle_bufferline = false` is set in
`ui.lua` because bufferline's `toggle_bufferline()` runs on *every* tabline redraw and re-pins
the option, silently reverting anything an autocmd set. That is what defeats the obvious way to
keep tabs off the snacks dashboard — the autocmd fires, then the next redraw undoes it. With
auto-toggling off, the `bufferline-dashboard` autocmds own the value outright.

**bufferline renders `offsets` *before* `custom_areas`** (`bufferline/ui.lua`, the `utils.join`
at the end of `M.tabline`). The tabline's project button therefore cannot use an offset for the
explorer sidebar: it would be shoved 41 columns right the moment the sidebar opened, out from
under the pointer that just clicked it. The custom area does the offset's job instead — button,
padding to the sidebar width, then a `│` on the split column.

**`<leader>e` cannot close the explorer from inside it.** The mapping and the tabline button
share `_G.NvimTabline.toggle_explorer`, but once the sidebar has focus the picker's input is in
insert mode and swallows the keys — `<Space>e` types a space there. Toggle from the editor
window, use `q` inside the sidebar, or click the button, which works from anywhere.

**Only `custom_areas` can hold a clickable label.** Their text is concatenated into the tabline
verbatim and measured with `nvim_eval_statusline`, so `%@v:lua.Fn@…%X` survives and is sized
correctly. An `offsets` entry cannot: `get_section_text` measures with `nvim_strwidth`, which
counts the `%` escapes as visible characters and corrupts the layout. Click labels also only
reach global functions, hence `_G.NvimTabline`.

**git-conflict's `:GitConflictChoose*` and `:GitConflict{Next,Prev}Conflict` commands are
broken upstream.** `set_commands()` creates them with a `<Plug>` *string* as the body
(`git-conflict.lua:503-511`), and Vim executes a string body as an Ex command line, so every
one of them fails with `E492: Not an editor command: <80><fd>S(git-conflict-ours)`. Map
`<Plug>(git-conflict-ours|theirs|both|none|next-conflict|prev-conflict)` directly, with
`remap = true`. Only `:GitConflictListQf` and `:GitConflictRefresh` take function bodies and
actually work.

**git-conflict's `disable_diagnostics` must stay `false` on Neovim 0.12.** It is implemented
with `vim.diagnostic.disable()` (`git-conflict.lua:655`), which 0.12 removed — the symbol is
`nil`, so enabling the option throws inside the plugin's own `GitConflictDetected` handler.
`git.lua` does the same job from its own autocmd with `vim.diagnostic.enable(false, {bufnr})`.

**git-conflict detection runs from a decoration provider, so `--headless` never fires it.**
`on_win` → `process(bufnr)` only runs when a window is actually drawn. Headless, the
`GitConflictDetected` event never fires: no highlights, no buffer-local maps, no diagnostic
change — while `:GitConflictListQf` still works, because it shells out to git independently.
That combination looks exactly like "my autocmd is broken". Test conflicts under
`script -q /dev/null`. The event also carries **no payload** — `nvim_exec_autocmds("User",
{pattern = ...})` and nothing else — so take the buffer from `nvim_get_current_buf()`.

**A lualine component runs on every redraw — including its `cond`.** A synchronous
`vim.fn.system` there is not a micro-optimisation question: measured on this machine, one
`git rev-list --left-right --count @{upstream}...HEAD` costs **~11,000µs**, against ~10µs to
render the entire bare statusline 1000 times from cache. So the `gitbar` table in `ui.lua`
holds *both* the ahead/behind string and the `in_repo` flag that gates the Git button, and
both components only read it; the two `vim.system` calls happen on
`FocusGained`/`BufWritePost`/`DirChanged`/`User Neogit*`. Note `in_repo` needs its own
`git rev-parse --is-inside-work-tree` — `rev-list` also fails inside a good repo whose branch
has no upstream, so reusing it would hide the button in any repo you have not pushed yet.

Prove the render path by shadowing `vim.system`, rendering 1000 times and asserting the spawn
counter is still `0` — not by eyeballing latency. And A/B any component you add: bare-nvim
render timings here range over 5-10µs run to run, so a single pair of numbers a few µs apart
proves nothing. Measure with a file open only if you compare against a file-open baseline —
the wakatime, LSP and devicons components dominate that number (~130µs) and will swamp yours.

**`neogit.action("commit", "commit")` does not work.** The documented
`neogit.action(popup, action)` API synthesises a stub popup (`close`, `state.env`,
`get_arguments`), and that is enough for `push`/`to_pushremote` and `pull`/`from_pushremote` --
both verified end to end here by watching the remote and local SHAs move. It is **not** enough
for `do_commit`: calling it blocks the event loop and opens no editor, and no commit happens.
`:Neogit commit` followed by `c` opens `gitcommit` + `NeogitDiffView` in the identical harness,
which is the controlled comparison that rules out a test artifact. So `<leader>gc` goes through
the popup on purpose. Do not "simplify" it back to `action()`.

**Remote provider hosts are disabled** (`python3`, `perl`, `ruby`, `node`) in `options.lua`.
vim-wakatime probes `has('python3')`, and Neovim answered by spawning an interpreter — ~160ms
on the first Python buffer.

**`~/.wakatime.cfg` is hand-maintained and must never be written to.** It carries the API key
and the Hackatime `api_url`. `install.sh` creates one *only* when the file is absent and a key
is in the environment; an existing file is not read, merged, backed up or replaced. Inside
Neovim the danger is `:WakaTimeApiKey`, `:WakaTimeStatusBar*`, `:WakaTimeDebug*` and
`:WakaTimeScreenRedraw*` — every one of them rewrites the file through `set_ini_setting`. Pass
settings to `require("wakatime").setup()` instead. The plugin's own `setup_config_file()` is
safe: it writes only when `filereadable` is 0.

**vim-wakatime calls `setup()` itself, before yours.** `plugin/wakatime.vim` runs
`require('wakatime').setup()` with no options the moment it is sourced, and a second `setup()`
early-returns on `state.initialized` after merging only what can still be applied — so
init-time options (`cli_path`, `debug`) look accepted and do nothing. `hackatime.lua` claims
`vim.g.loaded_wakatime` in `init` so that file finishes immediately and our call is the only one.

**vim-wakatime injects its own lualine component at runtime.** `maybe_attach_lualine_status_bar`
calls `lualine.get_config()`, inserts at `lualine_x[1]` and re-runs `lualine.setup()`. It skips
all of that when a component already carries `__wakatime_statusline = true` — which is why
`ui.lua` declares one. Verified: the tag survives `get_config()`, and the total renders once.
Two of them means the tag was dropped, so check the rendered bar, not the config.

**`wakatime-cli` on `PATH` disables the plugin's autoupdate.** `setup_cli` tries `cli_path` →
`PATH` → `~/.wakatime/wakatime-cli` → Homebrew → self-download, and anything but the last turns
autoupdate off. `install.sh` puts it in `~/.local/bin`, so the version is the installer's to
bump. That is deliberate: the self-download path is the one that wanted a `python3` provider.

**`--file-experts` and `--today-goal` return empty against Hackatime.** They are wakatime.com
features. `--today` works. A failed `--today` writes only to stderr and returns nothing on
stdout, so the statusline empties rather than displaying an error string — measured against a
bad key and an unreachable host.

**`lualine.statusline()` with no argument renders the *inactive* sections.** Pass `true` for the
focused bar. Without it you get filename + location and conclude your component is missing.

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
  `stylua init.lua lua/` before committing; format-on-save does it in-editor. **`stylua` is not
  on `PATH`** — it comes from Mason, so the command is
  `~/.local/share/nvim/mason/bin/stylua init.lua lua/` unless you installed it separately.
- **Shell**: `install.sh` must stay `shellcheck -S style` clean. `shellcheck` is not installed
  by anything here; `brew install shellcheck` (~70MB) or run it in a container.
- **Keymaps**: plugin keymaps live with their plugin spec (`keys = {}`); only
  plugin-independent ones go in `lua/config/keymaps.lua`. Every mapping needs a `desc` —
  which-key is the discovery mechanism and the JetBrains-muscle-memory replacement.
- **Leader groups**: `f` find, `s` search, `c` code, `g` git (`gh` hunks, `go` github,
  `gx` conflicts), `x` diagnostics,
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

`--startuptime` needs a TTY. Run from a non-interactive shell (an agent's tool call, a script)
it writes no log at all and the `tail` silently reports nothing — which looks like a broken
command, not a missing terminal. Use `script -q /dev/null nvim --startuptime ...` or
`--headless`. The two disagree in absolute terms: headless skips UI init and reports ~26ms
where a PTY reports ~160ms, and neither matches the ~85ms figure above. So a number is only
meaningful against a baseline taken *the same way* — `git stash`, measure, `git stash pop`,
measure. Five runs each; the spread is a few ms. Report the difference against that spread: two
medians 2ms apart, inside sets that each range over 7ms, is not a regression.

Two things sabotage that one-liner in an agent's sandbox, both silently. Neovim may not be able
to write the log **under `/tmp`** — you get no file and the same empty `tail` as the missing-TTY
case, so write it into the session scratchpad instead. And `grep` here is **ugrep**, which reads
the leading dashes of `--- NVIM STARTED ---` as its own options and errors out; use
`grep -F -e 'NVIM STARTED'`.

Anything clickable — tabline buttons, dropbar breadcrumbs — is testable with
`nvim_input_mouse`, but only under a real PTY. `--headless` renders no tabline grid, so the
coordinates hit nothing and the click appears to do nothing:

```sh
script -q /dev/null nvim some.py -c 'lua
  vim.defer_fn(function()
    vim.api.nvim_input_mouse("left", "press", "", 0, 0, 3)   -- row 0 = tabline
    vim.defer_fn(function()
      vim.fn.writefile({ tostring(#Snacks.picker.get({ source = "explorer" })) }, "/tmp/n.txt")
      vim.cmd("qa!")
    end, 800)
  end, 3000)
' >/dev/null 2>&1; cat /tmp/n.txt
```

To read the tabline itself, `nvim_eval_statusline(_G.nvim_bufferline(), { use_tabline = true })`
returns both the visible `.str` (escapes resolved) and its `.width` — that is how to prove a
click label is present without a screenshot, and where a column lands.

`:checkhealth` should be clean. Ignore `snacks.image` complaints about kitty/magick/mmdc, and
the `vim.ui.input`/`vim.ui.select` errors under `--headless` — snacks wires those on `UIEnter`,
which never fires without a UI. Verify with a real PTY (`script -q /dev/null nvim ...`).

## Testing installer changes

`install.sh` cannot be meaningfully validated by reading it.

**Check which machine you are on first — the tooling and the limits differ.**

| | macOS box (arm64) | Fedora box (x86_64) |
| --- | --- | --- |
| Runtime | Apple `container` CLI | `docker` and `podman` |
| Disk | tight — check `df -h /`, delete images after | ample |
| Exercises | `linux-arm64`, Debian/apt | `linux-x86_64`, **Fedora/dnf**, Debian/apt |

```sh
# Bootstrap path (clones from GitHub), exactly as `curl ... | bash -s --` behaves.
container run --rm -i docker.io/library/ubuntu:latest bash -s -- --check < install.sh   # macOS
podman    run --rm -i docker.io/library/ubuntu:latest bash -s -- --check < install.sh   # Fedora

# Same, with a copy of just the script mounted so local edits are exercised.
mkdir -p /tmp/m && cp install.sh /tmp/m/
container run --rm -v /tmp/m:/mnt   docker.io/library/debian:latest bash /mnt/install.sh --yes --skip-font
podman    run --rm -v /tmp/m:/mnt:Z docker.io/library/fedora:latest bash /mnt/install.sh --yes --skip-font
```

**On Fedora the `:Z` suffix on the bind mount is not optional.** SELinux otherwise denies the
container read access and the script dies claiming the file is missing, which looks like a
mount-path typo rather than a label problem. `docker` on Fedora needs it too. Use `:z` instead
if the same directory is mounted into more than one container at once.

Mount only the script, never the whole repo: `is_config_repo()` would then be true for the
mount point, and the run would exercise the symlink path instead of the clone path.

Running as root inside the container is the intended path — `detect_platform` sets `SUDO=""`
when `id -u` is 0, so no sudo is needed and none is installed in these base images.

**Before reaching for a container, source the script.** The `BASH_SOURCE` guard at the bottom
exists so the functions can be pulled into a test shell and driven one at a time — set `HOME` to
a `mktemp -d` first and `LOCAL_BIN` follows it, since it is derived from `$HOME` at source time.
That turns "does this touch a file it must not" into a checksum assertion that runs in a second,
with no image pull and no 20-minute Mason wait:

```sh
T=$(mktemp -d)
HOME="$T" bash -c 'source /abs/path/install.sh
  CHECK_ONLY=false; DRY_RUN=false
  INSTALLED=(); MISSING=(); SKIPPED=(); WARNINGS=()   # the accumulators are not set by sourcing
  detect_platform
  ensure_hackatime_config'
```

Reserve the container for what a fake `$HOME` cannot reach: the package-manager branches, and
platform mappings that differ from the machine you are on. Where a container is still the wrong
tool — a release asset name for an architecture you do not have — a
`curl -o /dev/null -sIL -w '%{http_code}'` against the download URL settles it in a second.

Caveats learned:

- The installer **clones the config from GitHub**, so unpushed local changes to anything other
  than `install.sh` are not tested. Push first, or the container silently runs an old config
  against a new script — which looks exactly like a code bug.
- `--check` tests the installer, **not the config**. It changes nothing, which means it never
  clones the repo and never starts Neovim — it exercises platform detection and the missing-
  package list, and finishes in ~15s. It cannot tell you whether a config change works. Only
  the full `--yes` run does that. (It also prints an empty second "Configuration" section under
  bootstrap: `ensure_config_location` is skipped by the `$BOOTSTRAP ||` guard and
  `ensure_treesitter_cli` prints nothing in check mode. Cosmetic.)
- Container images are large. The **macOS** box has run low on disk; check `df -h /` first and
  `container image delete` what you pulled. An Ubuntu base is ~247MB reclaimed. The Fedora box
  has room, so this constraint does not apply there.
- Apple's runtime is arm64-only, so **x86_64 paths are unexercised from macOS**. That is the
  Fedora box's job.
- A full run takes 10-20 minutes, mostly Mason. Run it in the background.

## Handoff: what is still unverified

Everything below is *known-unknown*, not suspected-broken. Recorded so the next session does
not re-derive it, and does not assume it was covered.

**The full `./install.sh --yes` end-to-end run has never been executed anywhere.** Every
installer claim in this file comes from `--check`, from sourcing the functions, or from
targeted container runs of individual functions. The macOS box could not afford it on disk. It
is the single highest-value thing to run on Fedora, in the background, against
`fedora:latest` **and** `debian:latest`.

**The Fedora/dnf branch of `install.sh` has never been run at all.** Only apt and brew have.
Specifically unknown there:

- Whether `gh` is packaged (`dnf info gh`). It is on Debian latest — verified — so
  `ensure_gh` took the package path there and `install_gh_from_release` was exercised only by
  calling it directly. If Fedora also packages it, the release fallback stays untested on the
  normal path and should be forced once by hand.
- `ensure_optional` has `local delta_pkg="git-delta"` followed by
  `[[ "$DISTRO" == "fedora" ]] && delta_pkg="git-delta"` — a branch that assigns the value it
  already had. Confirm Fedora's real package name, then delete the dead line.
- The Fedora branch adds `python3-pip` but, unlike Debian, no `python3-venv` — Fedora bundles
  `venv` with `python3` rather than splitting it. That is believed correct and untested. If it
  is ever wrong the failure is silent in exactly the documented way: Mason's `basedpyright` and
  `ruff` fail to install and Python ends up with no language server. Confirm with
  `python3 -c 'import venv'` inside `fedora:latest` before trusting it.

**x86_64 release assets are URL-verified but never downloaded, extracted or run.** All four
return `200`, so the *naming* is right; what is unproven is the extract-and-install step on
that architecture:

| Asset | Built by |
| --- | --- |
| `nvim-linux-x86_64.tar.gz` | `install_neovim_from_tarball` |
| `lazygit_<ver>_Linux_x86_64.tar.gz` | `install_lazygit_from_release` |
| `gh_<ver>_linux_amd64.tar.gz` | `install_gh_from_release` |

Note `gh` is the odd one out and the easiest to get wrong: it wants Go's `amd64` where the
others want `x86_64`, `macOS` where lazygit wants `Darwin`, and a `.zip` on macOS. The mapping
lives in `install_gh_from_release` and was HEAD-checked for all four platform combinations.

**The git UI (commit `3664098`) is verified, but not by a full install.** What *was* proven:
a fresh `+Lazy! restore` into an empty `XDG_DATA_HOME` installs 38 plugins reconciling exactly
against `lazy-lock.json`; Neogit, octo and git-conflict then work on that tree; and a fresh
`--depth 1` clone of `main` contains all of it. What was **not**: that a real end-to-end
`install.sh` run produces a working editor. Same background run as above covers it — after it
finishes, open a Python file in the container and use the functional check under
"Verifying changes", not just `:checkhealth`.

**`wakatime-cli` is genuinely absent on the macOS box** (`~/.local/bin/wakatime-cli` does not
exist), so `--check` reports it missing there. Unrelated to any recent work; do not "fix" it as
part of something else.

### Runbook for the Fedora box

Start the long one first — it is 10-20 minutes, mostly Mason — then do the cheap checks while
it runs. `--skip-font` because a container has no font consumer; drop it if testing the font
step itself. No `-v` mount: this is the bootstrap path, which clones `main` from GitHub, so it
tests exactly what a new machine gets. Push before running.

```sh
podman run --rm -i docker.io/library/fedora:latest bash -s -- --yes --skip-font < install.sh
podman run --rm -i docker.io/library/debian:latest bash -s -- --yes --skip-font < install.sh
```

A run is a pass only if the closing Summary lists no failures **and** the editor then works.
`:checkhealth` alone is not sufficient — see the note about `language.add` and coloured output
below. Keep the container alive and run the functional check from "Verifying changes" against
a real `.py` file: two LSP clients, treesitter active, inlay hints on.

Then, individually, the things the bootstrap run will not isolate:

```sh
# Does Fedora package gh? Decides whether the release fallback is even reachable there.
podman run --rm docker.io/library/fedora:latest bash -c 'dnf -q info gh >/dev/null 2>&1 && echo packaged || echo not-packaged'

# Force the x86_64 release paths regardless of what is packaged. Mount the script (SELinux :Z).
mkdir -p /tmp/m && cp install.sh /tmp/m/
podman run --rm -v /tmp/m:/mnt:Z docker.io/library/fedora:latest bash -c '
  dnf install -y -q curl tar gzip >/dev/null
  source /mnt/install.sh
  CHECK_ONLY=false; DRY_RUN=false
  INSTALLED=(); MISSING=(); SKIPPED=(); WARNINGS=()
  detect_platform && echo "platform: $OS/$DISTRO/$ARCH"
  install_gh_from_release      && "$HOME/.local/bin/gh" --version
  install_lazygit_from_release && "$HOME/.local/bin/lazygit" --version'
```

That last one is the real x86_64 gap: it downloads, extracts and *runs* the binaries, which the
`200`-response HEAD checks above deliberately do not. `detect_platform` should print
`linux/fedora/x86_64` — if it prints `arm64` you are on the wrong box and the run proves
nothing new.

## Style of work expected here

Report what was measured, not what should follow from the code. Several bugs in this repo
survived because a plausible-looking check (`language.add`, coloured terminal output, a plugin
being `loaded`) was accepted as proof. When something is unverified, say so.
