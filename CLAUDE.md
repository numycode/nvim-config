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
fails with `attempt to index field 'list' (a nil value)`. **Fedora 44 now packages 0.12.4**, so
the dnf path is taken there and `install_neovim_from_tarball` never runs; Debian latest still
ships 0.10.4, so it falls back to the upstream tarball. Both were measured on 2026-07-27 — do
not assume the tarball path is the only Linux path any more.

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

**Never measure parser health by counting `get_installed("parsers")`.** It also reports parsers
nvim-treesitter pulled in as *dependencies* — `xml` drags in `dtd` — so its length is not the
size of the wanted set. This produced a false pass: a Fedora bootstrap run printed
`parsers: 26/26 installed` against 26 wanted while `dtd` was present and **`vimdoc` was
missing**, and the same code printed the equally meaningless `27/26` on Debian. `ensure()` now
returns the count of *wanted* parsers plus the missing names, and `install.sh` puts them in the
Summary's warnings. Compare sets, never lengths.

**A 26-parser `nvim-treesitter.install()` batch silently drops one to three of them, and
resolves its handle anyway.** Four clean bootstrap runs lost a *different* set each time:
`vimdoc`; `dockerfile`+`sql`; `dockerfile`+`python` (on Debian — losing `python` matters rather
a lot here); `css`+`git_config`+`html`. `handle:wait(timeout_ms)` is part of it — measured
returning after **1007ms** against a 900,000ms budget with a parser still compiling, after which
a headless `+qa` kills the straggler — but it is not the whole story, because the dropped
parsers never arrive however long you wait.

`install.sh` therefore calls `ensure()` **twice**. The second pass sees only the shortfall and is
quick: measured 24/26 → 26/26 in **6.3s**, and 2 parsers installed cleanly in 6.1s when driven
on their own. Anything still missing after that goes into the Summary's warnings.

Two plausible-looking fixes were tried and are measured *worse* — do not reintroduce them:

- **Polling the wanted set until it is complete** stalls for the entire 900s budget, because the
  dropped parsers are not coming.
- **A retry loop with stall detection** (reinstall the shortfall when the count stops shrinking)
  measured **3/26** on a from-scratch batch, giving up after 186s: a 60s stall threshold cuts
  into compiles that are still progressing, and re-entering `install()` mid-batch interferes with
  the jobs already running.

The upstream drop itself is unfixed and still not understood; the two-pass call papers over it.

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
fail silently while everything else succeeds. Fedora needs no `python3-venv` — it has no such
package and bundles `venv` with `python3`; measured by creating a venv and pip-installing `ruff`
into it, which is the thing Mason actually does.

**`set -o pipefail` turns a short-circuiting reader into a false negative.** `install.sh` runs
under `set -euo pipefail`, so `producer | grep -q ...` fails with **141** whenever `grep` finds
its match and exits while the producer is still writing: the producer takes SIGPIPE, and
pipefail promotes it to the pipeline's status. This bit `nerd_font_present`, which reported the
JetBrainsMono Nerd Font *missing* on a machine with 98 font files installed and 96 matching
`fc-list` entries — deterministically, 141 on 5/5 runs — so every run re-downloaded the font and
`--check` listed it forever. The failure is backwards from how the code reads, which is why it
survived. Capture into a variable and pattern-match; never pipe a large producer into `grep -q`
or `head` here. (`nvim --version | head -1` and the `github_latest_tag` sed are fine only
because their output fits the pipe buffer, so nothing blocks and no SIGPIPE is raised.)

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
- A full run takes 10-20 minutes, mostly Mason. Run it in the background. Measured end to end on
  the Fedora box: 17.8 min (fedora) and 19.9 min (debian).
- Drop `--rm` and `--name` the container. The functional check has to run *after* the installer
  exits, and `podman commit <name> <img>` turns the finished container into a re-enterable image;
  with `--rm` the evidence is gone the moment the run ends.

## Handoff: what the installer has and has not proven

Measured on the Fedora x86_64 box on 2026-07-27 with podman 5.8.4. This replaces an earlier list
of known-unknowns; anything not under "Still unverified" below is now a measured fact.

**The full `./install.sh --yes --skip-font` bootstrap run passes on both Linux targets.** Run
against `fedora:latest` and `debian:latest` through the stdin/bootstrap path (no mount, so both
cloned `main` from GitHub — the thing a new machine actually gets). Both closing Summaries
listed no failures, and both were then driven past `:checkhealth` with the functional check from
"Verifying changes", on a real `.py` file:

| | fedora:latest | debian:latest |
| --- | --- | --- |
| platform line | `fedora (dnf, x86_64)` | `debian (apt, x86_64)` |
| neovim | 0.12.4 **from dnf** | 0.12.4 upstream tarball (packaged 0.10.4 too old) |
| treesitter parsers | 26/26 wanted | 26/26 wanted |
| Mason packages | 17 | 17 |
| LSP clients on a `.py` | `basedpyright` + `ruff` | `basedpyright` + `ruff` |
| treesitter | active, 2 captures | active, 2 captures |
| inlay hints | enabled, 4 returned | enabled, 4 returned |

Inlay hints being *enabled* is the weak half of that row. The half that matters is
`vim.lsp.inlay_hint.get()` returning real labels — `: int`, `: str`, `name=` — because that is
what separates a working basedpyright from one that merely attached.

The table is from runs of the *fixed* code. Getting there took six bootstrap runs, because the
first pair is what exposed the parser bugs: a Fedora run reported `parsers: 26/26 installed`
with `vimdoc` genuinely absent, and every run after it lost a different set until `install.sh`
started calling `ensure()` twice. Both treesitter entries under "Things that will bite you" are
the result — read them before touching parser installation, especially the list of fixes that
measured *worse*.

The practical consequence for anyone verifying a run: the parser line is now trustworthy, so a
Summary with no warnings really does mean all 26 landed. Confirm it independently anyway, with a
set difference against `require("config.parsers").parsers` — `total=27` is the healthy number,
26 wanted plus the `dtd` dependency.

**The Fedora/dnf branch has now run.** Findings:

- **`gh` is packaged on Fedora** (2.94.0-1.fc44), as it is on Debian. So `ensure_gh` takes the
  package path on both Linux targets and `install_gh_from_release` is unreachable on the normal
  path — it has to be forced by hand, which is what the x86_64 run below does.
- **Fedora bundles `venv` with `python3`, and `python3-venv` is not a package at all**
  (`dnf info python3-venv` finds nothing). Proven past `import venv`, which is the weak check:
  `python3 -m venv` created a venv, `pip` inside it worked, and it installed `ruff` from PyPI —
  the actual thing Mason does. The Fedora branch adding only `python3-pip` is correct.
- **`git-delta` is Fedora's real package name** (0.19.1-3.fc44); plain `delta` does not exist
  there. The dead `[[ "$DISTRO" == "fedora" ]] && delta_pkg="git-delta"` line is gone.
- Note `python3` is **not** in the `fedora:latest` base image, so a bare
  `podman run fedora python3 ...` probe fails with "command not found" and looks like a broken
  interpreter rather than a missing package. Install `python3` first.

**The x86_64 release assets are downloaded, extracted and executed** — not merely HEAD-checked.
Forced in a `fedora:latest` container with `detect_platform` printing `linux/fedora/x86_64`:

| Asset | Result |
| --- | --- |
| `gh_2.96.0_linux_amd64.tar.gz` | `gh version 2.96.0` |
| `lazygit_0.63.1_Linux_x86_64.tar.gz` | `version=0.63.1, os=linux, arch=amd64` |
| `nvim-linux-x86_64.tar.gz` | `NVIM v0.12.4`, ELF 64-bit, runs Lua, `vim.list.unique` is a `function` |

**The font step works, and is where the `pipefail` bug above was found.** `ensure_nerd_font`
fetches JetBrainsMono v3.4.0 and unzips 98 files into `~/.local/share/fonts/JetBrainsMonoNerdFont`,
after which `fc-list` matches 96 entries. Verified in a container across all three states —
absent → installs; already present → no-op, nothing appended to `INSTALLED`; `--check` on a
machine that has it → not listed as missing — and then run for real on the Fedora box, which had
no `~/.local/share/fonts` at all. Note the terminal font still has to be set to
"JetBrainsMono Nerd Font" by hand; the installer only warns.

**Both `ensure_hackatime_config` branches are verified, with a dummy key under a fake `$HOME`.**
No `~/.wakatime.cfg` plus `HACKATIME_API_KEY` writes the file at mode **0600** with the default
`api_url`. An *existing* file is left **byte-identical** — asserted by sha256 with a sentinel key
in it, with `HACKATIME_API_KEY` also set in the environment, which is the case that would matter
if the leave-alone check were ever weakened. The installer never reads the key out of an existing
file and does not need to: the key reaches Hackatime through vim-wakatime at runtime, not through
`install.sh`. A fresh container has no such file, which is why full runs only ever show the skip.

### Still unverified

- **macOS/arm64, from this box.** `install_gh_from_release`'s `macOS` + `.zip` mapping and the
  whole Homebrew branch are still only HEAD-checks and reading. That is the macOS box's job.
  The `brew install --cask font-jetbrains-mono-nerd-font` font branch is likewise unrun.
- **Anything behind `gh auth login`.** Both runs warn that gh is unauthenticated, so octo and
  `<leader>go` are installed but never driven against GitHub.

### Re-running this verification

Start the two long ones first — 10-20 minutes each, mostly Mason — then do the cheap checks
while they run. Push before running: the bootstrap path clones `main` from GitHub, so unpushed
local changes to anything but `install.sh` are not tested.

Drop `--rm` and name the containers. The functional check has to run *after* the installer
exits, and `podman commit` turns the finished container into an image you can re-enter; with
`--rm` the evidence is gone the moment the run ends.

```sh
podman run --name nvim-fedora -i docker.io/library/fedora:latest bash -s -- --yes --skip-font < install.sh
podman run --name nvim-debian -i docker.io/library/debian:latest bash -s -- --yes --skip-font < install.sh
podman commit nvim-fedora nvim-fedora-img     # then run the functional check against the image
```

A run is a pass only if the Summary lists no failures **and** the editor then works. Parsers
live in `~/.local/share/nvim/site/parser/`, and the honest completeness check is a set
difference against `require("config.parsers").parsers`, not a count — see the treesitter entries
in "Things that will bite you".

Then the things a bootstrap run will not isolate, because `gh` is packaged on both distros:

```sh
mkdir -p /tmp/m && cp install.sh /tmp/m/
podman run --rm -v /tmp/m:/mnt:Z docker.io/library/fedora:latest bash -c '
  dnf install -y -q curl tar gzip >/dev/null
  source /mnt/install.sh
  CHECK_ONLY=false; DRY_RUN=false
  INSTALLED=(); MISSING=(); SKIPPED=(); WARNINGS=()
  detect_platform && echo "platform: $OS/$DISTRO/$ARCH"
  install_gh_from_release      && "$HOME/.local/bin/gh" --version
  install_lazygit_from_release && "$HOME/.local/bin/lazygit" --version
  install_neovim_from_tarball  && /usr/local/bin/nvim --version | head -3'
```

`install_neovim_from_tarball` installs into `/opt/nvim` and symlinks `/usr/local/bin/nvim`; it
does **not** put anything in `~/.local/bin`, so looking for it there reports "No such file or
directory" and looks like a failed extract. `detect_platform` must print `linux/fedora/x86_64` —
`arm64` means you are on the wrong box and the run proves nothing new.

## Style of work expected here

Report what was measured, not what should follow from the code. Several bugs in this repo
survived because a plausible-looking check (`language.add`, coloured terminal output, a plugin
being `loaded`) was accepted as proof. When something is unverified, say so.
