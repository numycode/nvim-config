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
  autocmds.lua          yank highlight, cursor restore, LspAttach, mkdir-on-write,
                        dressing neogit's commit editor
  git.lua               <leader>gc staged-gate + commit editor buttons + <leader>g? sheet
  lsp.lua               capabilities() + on_attach() (buffer-local LSP keymaps)
  servers.lua           LSP servers + settings          <- also read by install.sh
  parsers.lua           treesitter parsers + ensure()   <- also read by install.sh
  tools.lua             Mason formatters/linters        <- also read by install.sh
  python.lua            venv auto-detection, :UvSync / :UvAdd / :UvRun / :RuffCheck
  preview.lua           live-preview state shared by the Live button and <leader>p
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

For scale, the Live button costs, against a stashed baseline: **0 spawns** over 1000 renders;
~135µs → ~145µs per render on a buffer where it is *shown*, and nothing resolvable on one where
`cond` hides it; **+0.9ms** of startup on the headless basis (medians 29.4 → 30.3, both sets
ranging over ~3ms, 10 interleaved pairs). The pty basis could not resolve that at all — its
medians sat 5ms apart inside sets ranging over 17 and 33ms, which is why the quiet headless
basis is the one to A/B a change this size on.

**The Live button gates on the buffer's *name*, not its `filetype`, and that is deliberate.**
live-preview.nvim decides what it can serve with a set of filename patterns
(`livepreview/utils.lua`, `supported_filetype`), so a `.htm` file — `filetype=html`, which every
instinct says is previewable — fails its `%.html$` and is refused. Gate the button on the
filetype and clicking it silently previews whatever *other* buffer `find_supported_buf()`
stumbles on (`plugin/livepreview.lua:450-459`), which is worse than no button. `config.preview`
therefore carries its own copy of upstream's extension list. Measured: `index.html`, `notes.md`
and `logo.svg` get the button; `page.htm` (`ft=html`) and `main.py` do not.

**`:LivePreview start` leaves a hit-enter prompt, and it blocks the event loop.** The command
body ends in `print("live-preview.nvim: Opening browser at <url>")`
(`plugin/livepreview.lua:470`), and that produces `Press ENTER or type command to continue` —
captured off the screen of an 80-column pty, with the server already listening *behind* the
prompt. A probe that called the command from a timer wrote its line before the call and nothing
after; the editor sat there until the run was killed. Clicking a status-bar button and having
the editor freeze is the worst possible version of this feature, so `config.preview.toggle()`
runs `silent LivePreview start`. Measured with `silent`: no prompt, `vim.ui.open` still called
with the right URL, loop alive afterwards, clean exit. `silent` suppresses only that `print` and
the matching one in `close`; the plugin's real failures go through `vim.notify`, which it does
not touch.

**live-preview.nvim's `picker = "snacks.picker"` is documented and broken.** `LivePreview.pick`
builds its dispatch as `picker_funcs[v] = picker[k]` over the `pickers` enum, and while the enum
carries `snacks = "snacks.picker"` the picker module defines only `telescope`, `fzflua`,
`minipick`, `vimui` and `pick` — there is no `snacks`, so the entry resolves to `nil` and the
guard below it rejects the value with "config option 'snacks.picker' invalid". Measured: setting
it made `<leader>pf` produce that notification and no picker at all. `picker = ""` (auto-detect)
is correct here — its fallback chain reaches snacks through `vimui` + `snacks.picker.select`,
which opens the real thing (`source=select`, input and list windows both up).

**live-preview.nvim gates its HTML rewriting on the request's `Accept` header.** `serve_file`
only injects the reload client (or renders Markdown to HTML) when `Accept` matches `text/html`
(`server/handler.lua:93-103`) — deliberately, so an SVG pulled in by an `<img>` tag is not
converted. `curl` sends `Accept: */*`, so `curl http://127.0.0.1:5500/index.html` returns the
file **byte-identical to disk** and looks exactly like "live reload is broken". It is not: with
`-H 'Accept: text/html,...'` the same request returns 250 bytes instead of 188, carrying
`<script src='/live-preview.nvim/static/ws-client.js'></script>` immediately after `<head>`.

Proving the reload itself needs a websocket client, not curl. A ~40-line raw-socket client in
Python (handshake, then parse frames) is enough, and is what established both halves here:
saving an `.html` pushed `{"type":"reload"}`, and *typing* in a `.md` with no write pushed
`{"type":"update","content":...}` — twice, one frame per `TextChanged`. That asymmetry is
upstream's design (`livepreview/init.lua:273-288`), not a bug: HTML reloads on write because it
is watched on the filesystem, everything else streams from the buffer.

**live-preview.nvim ignores the result of `bind`, so a second server silently loses the port and
the first one keeps answering.** `Server:start` calls `self.server:bind(ip, port)` and never
looks at what it returned (`server/init.lua`), so when the port is taken the new server is inert
while `is_running()` reports `true` and the button shows `󰓛 Live :5500`. Requests are answered
the whole time — by the *other* process, out of the *other* webroot. `M.start`'s
`processes_listening_on_port` warning is the only signal that anything is wrong, and it is a
`vim.notify` WARN, so `silent` does not suppress it: verified by squatting on 5500 from a second
Neovim and watching `NOTIFY[3] Port 5500 is being used by another process 'nvim' (PID …)` arrive
through the silenced toggle, with `running=true` alongside it. Heed that notification.

This cost most of an afternoon, because it also poisons testing. A probe whose `qa!` never
fired kept port 5500, and **every subsequent run for the next hour was measured against that
zombie** — the new server bound nothing, its fs watcher fired correctly in its own process, and
the websocket client that had just completed a 101 handshake was connected to the old process,
so the client list read `clients=0` while a reload was plainly being requested. That produced a
tidy, entirely false story about garbage collection eating the macOS fs watcher, with an A/B to
match. What broke it open was wrapping `websocket.handshake` and finding it was *never called*
in the process being tested: a 101 with no handshake in your own server means you are talking to
someone else. `lsof -nP -i:5500 | grep LISTEN` before believing any result, and kill strays —
CLAUDE.md already said so, and the advice was ignored anyway.

**On Linux, deleting any watched directory kills the live preview for the rest of the session —
and a plain `git gc` is enough to do it.** This is the Linux-only half of the plugin and it does
not exist on macOS, so nothing in the macOS handoff could have caught it. Two upstream bugs that
compound, both measured on Fedora x86_64:

- `Server:watch_dir` branches on `uv.os_uname().sysname`. macOS and Windows get one recursive
  `uv.new_fs_event`; **everything else gets `fswatch.Watcher`**, a hand-rolled tree of
  *non-recursive* watchers, one per directory, extended as directories appear.
- `Watcher:close()` (`server/fswatch.lua:102`) is a bare `self.watcher:close()` with no nil
  guard, while `Watcher:start()` sets `self.watcher = nil` when its directory disappears. So
  once any watched directory is deleted, `close()` throws — and everything after the throw is
  skipped: `Server:stop` never nils `_watcher` nor deletes the `LivePreview` augroup, and
  `livepreview.close()` never nils `serverObj`. Because `start()` calls `close()` first, the
  next start throws too (`handle 0x… is already closing`, same line). Preview dead until you
  restart Neovim.
- The blast radius is much wider than "don't delete folders", because **`.git` is watched**:
  upstream's `if subdir ~= ".git"` compares `dir .. "/" .. name`, a *full path*, against the
  bare string, so it never matches. Measured: `git gc --prune=now` in a two-commit repo removed
  6 directories under `.git/objects` and wedged the preview exactly as deleting a source folder
  did. git runs `gc` on its own via `gc.auto`.

`config.preview` works around it — `start()`/`stop()`/`toggle()` catch the throw, clear
`livepreview.serverObj` and drop the augroup, which is what lets the next start succeed. Clearing
`serverObj` also defuses the plugin's own `VimLeavePre` handler, which bails out early when it is
nil instead of throwing on the way out (that throw is what leaves a hit-enter prompt on quit).
Keep `<leader>po`/`<leader>px` pointed at `config.preview`, not at the raw commands.

Verified by controlled A/B, not by reading: with the deletion, `close` fails and the restart
fails; in the identical run *without* it, both succeed. And recovery is proven from the wire —
after the reset the server rebound the port, completed a 101 handshake and delivered a real
`{"type":"reload"}` frame on the next write. `is_running()` alone would have lied: it reports
`true` for a moment after the failed close while the port already has **zero** listeners.

**live-preview's `connecting_clients` only ever grows, and holds every TCP connection — not just
websockets.** `Server:start`'s listen callback does `table.insert(M.connecting_clients, client)`
for *every* accepted connection (`server/init.lua:129`), and the only `table.remove` is on the
error branch above it. So each asset request from a page load — markdown-it, the CSS, katex,
mermaid, `ws-client.js` — leaves a permanent entry. Measured: one Firefox page load put **18**
entries in the list. It is a *module-level* table, so it also survives `Server:stop` and every
restart, including a wedge recovery. `send_scroll`/reload then write a frame to every stale entry,
which is exactly the ~3.2µs-per-entry term in the `sync_scroll` table above. The nearby guard
`if #M.connecting_clients then` is `if <number>`, always true — they meant `> 0`.

**The `sync_scroll` autocmds are registered with no group, so nothing ever removes them.**
`Server:new` creates `WinScrolled`/`CursorMoved`/`CursorMovedI` with a bare
`api.nvim_create_autocmd(...)` and no `group` field (`server/init.lua:76-89`), while the cleanup
in `Server:stop` is `nvim_del_augroup_by_name("LivePreview")` — which cannot see them. Measured
across start/stop cycles: ungrouped `CursorMoved` handlers went 2 → 3 → 4 → 5 → 6, one per start,
with stop removing none, and a wedge recovery adding one like any other start. Two consequences
for anyone measuring here: the accumulation is nearly free (they early-return, see above), and
**a group-filtered query cannot find them** — `nvim_get_autocmds({group = "LivePreview", event =
"CursorMoved"})` returns `0` whether `sync_scroll` is on or off, which reads exactly like "the
handler was never registered". Count ungrouped `CursorMoved` autocmds instead. This is also why
"does the augroup double-fire" is the wrong question: the augroup is clean, and the thing that
does accumulate is not in it.

**`:LivePreview start` opens a *real* browser on this desktop, and that poisons any measurement
of the preview.** The command ends in `vim.ui.open`, which on the Fedora box launches the default
handler — a full Firefox — whose asset requests land in `connecting_clients`. A `sync_scroll` A/B
run without stubbing it measured **174µs/move** and looked cleanly resolvable; the same A/B with
`vim.ui.open` stubbed measured **6µs, inside the noise**. The first number was not the autocmd, it
was 18 websocket writes to a browser nobody asked for. Worse, that browser *outlives the probe*:
`ws-client.js` reloads on socket close, so it reconnects to port 5500 for as long as it is alive,
and a later run inherits it. Stub `vim.ui.open` in any preview probe, and check
`ps -eo comm | grep firefox` alongside the `lsof -nP -i:5500` that CLAUDE.md already demands.
Note `pkill -f firefox` **kills its own shell**, because the pattern matches the shell's own
command line; use `killall -9 firefox` or a `[f]irefox`-style pattern.

**live-preview's `on_events` is either/or, fixed at start time by the *first* file's type.**
`livepreview/init.lua` passes `LivePreviewDirChanged` (fs-watch → `reload`) when
`supported_filetype(filepath) == "html"`, and otherwise `TextChanged`/`TextChangedI` (→ `update`
carrying the unsaved buffer). An HTML preview therefore gets **no** live typing, and a Markdown
preview gets **no** fs-watch reload, whatever you subsequently open. Do not test one and conclude
the other works. Measured on Linux: starting on `index.html` produced `reload` on every write —
top level, `nested/deep/` two levels down, a directory created *after* the server started, and
inside `.git` — while starting on `notes.md` produced `update` frames with the typed text and the
file unchanged on disk, plus `scroll` frames from `sync_scroll`.

**`vim.wait()` blocks the loop that detects `TextChanged`.** A headless harness that starts the
server and then sits in `vim.wait(16000, …)` sees fs-watch `reload` frames arrive normally but
**never** a single `update` frame, however the buffer is modified — including via
`nvim_buf_set_lines`. That is the harness, not the plugin: the same test under a real PTY
produced the `update` immediately. Use a PTY for anything that depends on a text-change autocmd.

**A `pkill`ed probe leaves a swap file, and the next run hangs on `E325`.** A gating probe that
walked five buffers stopped dead after the second, with no error and no output — it was sitting
on a swap-file prompt for a file an earlier killed probe had open. It reads as a hang in the
code under test. `rm ~/.local/state/nvim/swap/*<label>*` between runs, alongside the `pkill`
that CLAUDE.md already recommends.

**`script -q /dev/null nvim` inherits the caller's 80 columns, which truncates the statusline.**
Two separate checks failed on this and looked like real bugs: the running button's label
searched for as `󰓛 Live :5500` was on screen as `<ive :5500`, the leading glyph cut by the `<`
truncation marker. A statusline assertion needs a pty of a size you chose. `pty.fork()` plus a
`TIOCSWINSZ` ioctl gives one in about twenty lines of Python; at 200 columns the same probe
found the button at column 132 and the round trip asserted cleanly.

**`neogit.action("commit", "commit")` does not work.** The documented
`neogit.action(popup, action)` API synthesises a stub popup (`close`, `state.env`,
`get_arguments`), and that is enough for `push`/`to_pushremote` and `pull`/`from_pushremote` --
both verified end to end here by watching the remote and local SHAs move. It is **not** enough
for `do_commit`: calling it blocks the event loop and opens no editor, and no commit happens.
`:Neogit commit` followed by `c` opens `gitcommit` + `NeogitDiffView` in the identical harness,
which is the controlled comparison that rules out a test artifact. So `<leader>gc` goes through
the popup on purpose. Do not "simplify" it back to `action()`.

**Nor back to `a.void`.** The obvious next theory — that the missing piece is the coroutine
context, since `neogit.action` runs the action from `dispatch_refresh`'s *callback* (no coroutine
on the stack) while the popup wraps it in `a.void` (`popup/init.lua:376`), and every git call
outside an async context silently degrades to a blocking spawn-and-wait
(`runner.lua:145-171`) — is **wrong, and measured worse**. Calling
`require("neogit.lib.async").void(function() require("neogit.popups.commit.actions").commit(stub) end)()`
hangs Neovim outright: the probe wrote its first line and nothing after, the editor never opened,
no commit was made, and the process had to be killed. The explanation is consistent; the fix is
not. `config.git.open_commit_editor()` still runs `:Neogit commit`.

**What *does* remove the extra keystroke is pressing `c` for the user.** The commit popup is a
real buffer with a published filetype and name (`NeogitPopup` / `NeogitCommitPopup`,
`lib/popup/init.lua:418-421`), so a one-shot `BufWinEnter` autocmd can feed `c` into it —
scheduled, because the popup closes itself on `WinLeave` (`popup/init.lua:426`). That depends on
two strings rather than on neogit's async internals. Measured: `<leader>gc` lands directly in the
message box. The autocmd must be disarmed on a timer too, or a popup that never appears leaves a
stray `c` waiting for the next buffer.

**Neogit's commit editor `q` commits, and its prompt does not say so.** `q` is Close
(`editor/init.lua:192-206`); on a modified buffer it asks `"Save changes?"` through
`vim.fn.confirm(msg, "&Yes\n&No", 1)` — **default Yes** — and Yes makes the commit. Measured on
this config before the fix: `q` then `<CR>` took a scratch repo from 1 commit to 2. `<leader>q`
did *not* commit (1 → 1); it fails with E37 instead, because the buffer is modified. Both are now
overridden buffer-locally by `config.git.cancel()`, a three-way confirm defaulting to *Keep
editing*. All three branches verified: `C` → 2, `D` → 1, `<CR>` → 1.

Note when driving this in a test: **`nvim_input("<C-c>…")` cannot submit** — CTRL-C clears the
typeahead, so the second `<C-c>` never arrives and the run looks like "submit is broken". Use
`nvim_feedkeys(vim.keycode(...), "m", false)`. And `vim.fn.confirm` answers to the **accelerator
letter**, not a digit: feeding `1<CR>` selects nothing and the prompt sits there.

**Two submit keys are bound, and the editor's own help block names them at random.** Neogit
resolves a mapping table's key through `util.tbl_wrap` (`lib/buffer.lua:794`), so
`commit_editor = { ["<c-s>"] = "Submit" }` adds `<C-s>` *alongside* `<c-c><c-c>` — both verified
to commit. But the injected `# Commands:` block prints `mapping[name][1]`
(`editor/init.lua:110-113`), and that list's order is `pairs()` order over a merged table:
measured across 5 headless runs it printed `<c-s>` twice and `<c-c><c-c>` three times. The `#`
block is therefore not a place to advertise anything. The winbar is.

**Winbar click labels work.** `%@v:lua.Fn@…%X` in `vim.wo[win][0].winbar` is clickable, not just
in the tabline: `nvim_input_mouse("left", "press", "", 0, row, col)` at the button's column
committed, with `row` from `nvim_win_get_position(win)` (measured `{1, 0}` — row 0 is bufferline's
tabline). `nvim_eval_statusline(wb, { winid = win, use_winbar = true })` reports the resolved
`.str` and a correct `.width` (96 for the commit bar), which is how to prove one is present
without a screenshot.

**A winbar truncates from the *left* unless you place `%<`.** The commit bar rendered at 80
columns as `<ss Ctrl-S   ✕ Cancel…` — it dropped the ✓ Commit button and kept the trailing
prose, which is exactly backwards. `%<` before the prose fixes it: measured at 238/100/80/60/40
columns, both buttons survive to 60 and ✓ Commit survives to 40.

**`<C-s>` survives the terminal — measured, not assumed.** This was carried as an open risk on
the grounds that `nvim_feedkeys` injects *inside* Neovim, downstream of the terminal, and so
cannot rule out iTerm2 eating CTRL-S as XOFF. Settle it by writing the raw byte down a real pty
instead: `{ sleep 6; printf ' gc'; sleep 10; printf 'SUBJECT'; sleep 2; printf '\023'; } |
script -q /dev/null nvim`. Measured 1 → 2 commits from **normal** mode and 1 → 2 from **insert**
mode, subject clean. `stty -a` on the live tty shows `-ixon`, so Neovim's TUI does clear flow
control. Note the editor opens *already in insert mode*, so a leading `i` in a driver script is
typed as literal text and ends up in the subject line.

**Spell keys out in prose — `<C-s>` is not a hint, it is a cipher.** Measured on the owner: the
button bar rendered correctly at width 71, in a 238-column window, with `mouse=a` and `<C-s>`
bound in both normal and insert mode, and the reported experience was still *"I typed the
message but I can't figure out how to commit"* — from inside that editor. Reading the winbar
over RPC is what proved the affordance was present and the notation was the failure. The bar now
says `✓ Commit — press Ctrl-S`. Vim notation belongs in `desc` strings which-key renders beside
the literal keys, not in prose aimed at someone who does not already know the notation.

**A running Neovim can be interrogated over its socket, and this is the fastest way to tell
"broken" from "not noticed".** Sockets live under
`$TMPDIR/nvim.$USER/*/nvim.<pid>.0`; `nvim --server <sock> --remote-expr 'luaeval("dofile(...)")'`
runs a read-only probe in the live session and returns its string. That is how the winbar
contents, the resolved keymaps and `mode=i` above were obtained from the owner's actual editor
rather than reproduced in a harness. Beware `nvim_buf_get_keymap` returns `lhs` in **readable**
form (`<C-S>`), not as raw bytes — filtering for `"\19"` finds nothing and looks exactly like an
unbound key.

**dropbar claims `gitcommit` buffers unless told not to.** The commit editor is `buftype = ""`
with a real filename, so dropbar's `enable` passed it and set
`winbar=%{%v:lua.dropbar()%}`, rendering `󰉋 .git  COMMIT_EDITMSG`. The `winbar ~= ""` test in that
`enable` is not enough to rely on — dropbar also attaches on `BufEnter` and `FileType`, so the
race is not one to win by registration order. `ui.lua` excludes the filetype by name instead.

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
- **User-facing text spells keys out**: "press Ctrl-S", "Space, g, c" — never `<C-s>` or
  `<leader>gc`. Vim notation belongs in `desc` strings, where which-key renders the literal
  keys beside it, and nowhere else: not in winbars, floats, prompts or hint lines. The owner
  came from JetBrains and does not read the notation; see "Spell keys out in prose" above for
  the measurement that established this. Expand `<leader>` to "Space" the first time a
  walkthrough uses it.
- **Leader groups**: `f` find, `s` search, `c` code, `g` git (`gh` hunks, `go` github,
  `gx` conflicts, `g?` the plain-English walkthrough), `x` diagnostics,
  `u` UI toggles, `b` buffer, `S` session, `t` terminal, `m` multicursor, `r` refactor,
  `p` preview (live server for HTML/Markdown/SVG/AsciiDoc).
- **Lockfile**: `lazy-lock.json` is committed. `install.sh` runs `:Lazy restore`, never
  `sync` — `sync` updates everything and rewrites the lockfile.
  **`restore` does not restore in a run that also installs something.** Measured on Fedora:
  with a plugin missing *and* others sitting at newer-than-pinned commits, one `+Lazy! restore`
  left the drifted ones alone and **rewrote `lazy-lock.json` to record the drift** — the
  opposite of the job. Run it a second time and it checks the drifted plugins back out and
  leaves the lockfile byte-identical. So after any `git pull` that adds a plugin, restore twice,
  and check `git status lazy-lock.json` before committing: a lockfile change you did not intend
  is this bug, not an upstream bump. The fresh-machine path is **fine** — a pristine data dir
  cloned all 39 at exactly their pinned commits with the lockfile untouched, which is the case
  `install.sh` actually faces, so its single call is not a bug.
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

**`script -q /dev/null nvim …` is BSD syntax and does not work on the Fedora box.** Two separate
traps, and both fail *silently* in a way that reads as "my Lua is broken":

- Fedora does not ship `script` at all by default — util-linux is installed but the binary lives
  in the separate **`util-linux-script`** package. Without it every PTY recipe above exits
  **127** and writes nothing, so the probe file is simply absent.
- Even installed, util-linux `script` takes the command via `-c`: `script -qec 'nvim …'
  /dev/null`. The BSD trailing-argv form is what macOS wants.

Rather than depend on either, drive a PTY from Python — no package, no root, and it works the
same on both boxes. `scratchpad/pty_run.py` in the session that wrote this is the whole thing:
`pty.fork()`, `TIOCSWINSZ` to a chosen size, `execvp`, drain the master fd. Sizing it explicitly
also side-steps the 80-column truncation trap above.

**Also: zsh is the shell here, and it mangles inline `-c 'lua …'` blocks.** A multi-line Lua
argument containing `%`, `<Esc>` or braces dies with `no matches found:` before nvim ever starts
— again, no probe file, looking exactly like a config error. Put the Lua in a file and use
`-c "luafile /path/to.lua"`, and pass values in through `vim.env`.

**Arm the answer to a `vim.fn.confirm` *before* calling the thing that prompts.** `confirm`
blocks the event loop, so in a driver script written the obvious way —
`require("config.git").commit(); vim.defer_fn(function() vim.api.nvim_input("S") end, 1200)` —
the second statement never runs: `commit()` has not returned. The prompt sits unanswered and the
run burns its whole timeout. Reverse them, and the deferred keypress lands while `confirm` is
blocking:

```lua
vim.defer_fn(function() vim.api.nvim_input("S") end, 1200)
require("config.git").commit()
```

Pre-queuing the key with no delay does not work either — `confirm` is not up yet to consume it.
And remember `confirm` answers to the **accelerator letter**, not a digit.

**Auditing keymaps needs a buffer that would actually have them.** `<leader>g?` claims 13
keys, and a cheat sheet that names a key which does not exist is worse than no cheat sheet — so
assert them. But gitsigns sets `<leader>ghs`, `<leader>ghp`, `<leader>ghr`, `]h` and `[h`
buffer-locally from `on_attach`, so a `maparg` sweep in a scratch buffer reports **5 missing**
and looks like five broken mappings. Open a tracked file first and wait for the attach:

```sh
nvim --headless init.lua -c 'lua
  vim.wait(8000, function() return vim.fn.maparg("]h", "n", false, true).buffer == 1 end, 200)
  for _, k in ipairs({ "<leader>ghs", "]h", "[h" }) do
    local m = vim.fn.maparg(k, "n", false, true)
    print(k .. " " .. tostring(type(m) == "table" and next(m) ~= nil))
  end' -c 'qa'
```

**Kill strays.** A driver that hangs on an unanswered prompt leaves a live `nvim` holding the
scratch repo. `pkill -f "repos/<label>"` before re-running, or the next run's git assertions
race against it. **A stray also holds port 5500**, and that failure is silent and misleading —
see the `bind` entry in "Things that will bite you". `lsof -nP -i:5500 | grep LISTEN` before and
after anything touching the preview.

### Testing the live preview

Three things need proving separately, and only the third is the feature.

**A pty of a size you chose**, because 80 columns truncates the statusline out from under any
assertion about a button:

```python
pid, fd = pty.fork()
if pid == 0: os.execvp(argv[0], argv)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
```

**The button**, by finding it in the resolved bar and clicking where it actually is — the column
must be computed, not guessed, since `nvim_eval_statusline(...).str` has the escapes resolved but
`find` returns a byte offset:

```lua
local ev = vim.api.nvim_eval_statusline(require("lualine").statusline(true), {})
local at = ev.str:find("󰖟 Live", 1, true)
local col = at and vim.api.nvim_strwidth(ev.str:sub(1, at - 1))
vim.api.nvim_input_mouse("left", "press", "", 0, vim.o.lines - 2, col + 1)
```

**The reload**, which needs a websocket client — `curl` cannot see it, and worse, `curl` sends
`Accept: */*` and so gets the untransformed file back and makes the feature look broken. A
~40-line raw-socket client in Python (handshake, then unmask and print frames) is enough. Expect
`{"type":"reload"}` after writing an `.html`, and `{"type":"update","content":…}` while merely
typing in an `.md`.

To watch a *real* browser instead, sample `lsof -nP -i:5500` before and after the save: a reload
shows up as new ephemeral local ports on the browser side, because the client closes its socket
and `onclose` calls `window.location.reload()` (`static/ws-client.js`). Measured on this machine
with the default handler, which is **Zen** (`app.zen-browser.zen`), not Safari — two sockets
before the save, three additional ones after.

**To read the rendered page itself, drive headless Firefox over Marionette.** There is no
selenium or playwright on the Fedora box and neither is needed: `firefox --headless --marionette
--profile $(mktemp -d)` opens a JSON-over-TCP server on port 2828 whose wire format is just
`<len>:<json>`, and ~60 lines of Python gives `WebDriver:NewSession`, `WebDriver:Navigate` and
`WebDriver:ExecuteScript`. That is how "the page actually follows the cursor" was settled —
`return window.scrollY` before and after a cursor jump — and it is the only tool here that can
answer a question about the DOM rather than the socket. Kill it with `killall -9 firefox` when
done; see the `vim.ui.open` entry in "Things that will bite you" for why a surviving browser
silently corrupts the next run.

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

**A bootstrap that has to install live-preview.nvim has now run** — re-measured 2026-07-28, both
targets, because every earlier run predates the plugin existing in this config. Same
stdin/bootstrap path, both Summaries clean:

| | fedora:latest | debian:latest |
| --- | --- | --- |
| live-preview.nvim checkout | `a30e54e5` = the `lazy-lock.json` pin | `a30e54e5` = the pin |
| `git status lazy-lock.json` in the clone | clean | clean |
| preview actually serves | `{"type":"reload"}` off a real websocket | `{"type":"reload"}` off a real websocket |

The lockfile row is the one that matters: a *dirty* `lazy-lock.json` after a bootstrap is the
"restore does not restore" bug under Conventions, not an upstream bump. Both clones were
byte-clean, and the fresh-machine path stays the case `install.sh` handles correctly.

The pin row is weaker than it looks and should be re-read when upstream moves: **upstream `main`
is currently at the pinned commit too**, so this run cannot distinguish "restored to the pin"
from "cloned main and got lucky". It proves the plugin installs and is not *ahead* of the pin; it
does not prove drift would be corrected.

`is_running()` was deliberately not accepted as evidence for the third row — upstream ignores the
result of `bind()`, so it reports `true` for a server that owns nothing. Only a frame off the
wire counts. Containers have no browser, so `vim.ui.open` failing there is expected and is not
part of the assertion; the server starts before the browser is opened.

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

## Handoff: what the live preview has and has not proven

Measured on the macOS arm64 box on 2026-07-27/28, against live-preview.nvim
`a30e54e51e7480d7060c8c8185f2a963ad3518b4`.

| Claim | How it was established |
| --- | --- |
| Button appears only where the server can serve | `index.html`, `notes.md`, `logo.svg` yes; `page.htm` and `main.py` no; none on the dashboard, whose statusline lualine disables outright |
| Click starts it | 200-column pty, button found at column 132, `nvim_input_mouse` → `running=true` and the right URL handed to `vim.ui.open` |
| Click stops it | label flips to `󰓛 Live :5500` at column 128, second click returns `running=false` and the `󰖟` glyph |
| No hit-enter prompt | probe reaches its post-command line and exits 0; without `silent` it never does |
| The page is served, rewritten | 200, and 188 → 250 bytes with a browser `Accept`, carrying the `ws-client.js` tag after `<head>` |
| Reload fires on write | raw websocket client received `{"type":"reload"}` |
| Markdown streams unsaved | `{"type":"update","content":…}` while typing, file on disk unchanged |
| A real browser reloads | Zen held 2 sockets; three new ephemeral ports after the save |
| Costs nothing to have | 0 spawns/1000 renders, ~135 → ~145µs where shown, +0.9ms headless startup |
| `<leader>p` group | which-key renders `p ➜ +preview`; all four maps resolve with their descs; `<leader>pf` opens a snacks picker (`source=select`) |
| No stray server | `lsof -i:5500` empty after `:qa`, via upstream's own `VimLeavePre` |
| `:checkhealth livepreview` | Nvim compatible, `sh` present, snacks picker found, server healthy, webroot = cwd |

### Still unverified

- **What the page actually looks like**, in the sense of rendering fidelity. Nothing has taken a
  screenshot. The DOM is no longer unexamined, though — a headless Firefox on the Fedora box
  reported 801 `.source-line` elements, the injected `ws-client.js` tag, and a `scrollHeight` of
  40931 against a 714px viewport, and the page demonstrably scrolls (see the Linux table below).
  So "the page is built and responds"; "it is *pretty*" is still inference.
- **Markdown `update` streaming inside the containers.** The container assertion is the fs-watch
  `reload` path only, driven headless — which is legitimate, since only `TextChanged` needs a PTY.
  The `update` half is measured on the Fedora *host*, not in the images.
- **The `.git` inotify waste**, deliberately left alone: 9 of 15 watches are `.git` subdirectories
  because upstream's `subdir ~= ".git"` guard compares a full path against the bare string.
  Harmless at this scale against a `max_user_watches` of 274132, and not worth patching upstream
  behaviour to fix.

### The Linux fs-watch branch: measured 2026-07-28, Fedora x86_64 host

This closes the "Linux" unknown above. `uv.os_uname().sysname` is `Linux`, so the
`fswatch.Watcher` tree is the code under test throughout.

| Claim | How it was established |
| --- | --- |
| Serves and rewrites | `GET /index.html` 200 with `ws-client.js` injected; `/notes.md` 200, 1756 bytes; missing file 404 |
| Reload on write | raw websocket client received `{"type":"reload"}` — top level, `nested/deep/` (depth 2), `assets/`, and a directory created *after* the server started |
| Unsaved markdown streams | `update` frame carrying `"# Heading \| \| body text \| typed but never saved"`, `notes.md` byte-identical on disk |
| `sync_scroll` is live | `scroll` frames arrive on cursor movement |
| Survives directory deletion | `rmtree` of a watched subtree: server keeps listening, new directories still watched, top-level writes still reload |
| No stray server | 0 listeners on 5500 after `:qa!`, via upstream's own `VimLeavePre` |
| `:checkhealth livepreview` | Nvim 0.12.4 compatible, `sh` present, `snacks.picker` found, config table shows our port/`browser`/`dynamic_root`/`picker` |
| The button renders | `󰓛 Live :5500` seen in the rendered statusline under a 200-column PTY |
| **`.git` is watched** | a servable file written *inside* `.git` fired a reload — the `subdir ~= ".git"` guard is dead code |
| **Deleting a watched dir wedges it** | see the entry in "Things that will bite you"; `git gc` reproduces it |
| **Recovery is a real rebind, not the old server** | across a `git gc` wedge: listeners on 5500 went 1 → **0** between stop and start, the old `Server`'s `.server` handle went `nil`, and the new one is a different table with a different `uv_tcp_t`. `Server:stop` closes the TCP handle *before* the line that throws, which is why this works |
| **Two wedges in one session are both survivable** | `git gc`, recover, fresh commit, `git gc` again, recover — reload frames delivered after *each* recovery. The single-shot retry in `M.start()` is enough because each start begins from cleared state |
| **The new watcher tree is live after recovery** | a directory created *after* the recovery, written into, fired a reload — the old tree could not have done that |
| **The `LivePreview` augroup does not accumulate** | 1 entry on HTML / 2 on Markdown after every start, **absent** after every stop, identical after both recoveries. No double-fire |
| **The `sync_scroll` autocmds DO accumulate** | see "Things that will bite you" — they are registered with no group, so nothing deletes them |
| **The page actually follows the cursor** | headless Firefox over Marionette: `window.scrollY` 0 → **11569** on jumping to line 350 of a 1202-line Markdown file, → **0** again on jumping back to line 2 |

`:checkhealth livepreview` reports **"No healthcheck found"** unless the plugin is loaded first —
it is `cmd`-lazy, so a bare `nvim -c 'checkhealth livepreview'` proves nothing. Force it with
`require("lazy").load({ plugins = { "live-preview.nvim" } })`.

Two cost notes: the watcher tree held **15 inotify watches** for a 14-directory webroot, 9 of
those directories being `.git` — real waste, but `max_user_watches` is 274132 here, so not a
practical limit. And the `config.preview` workaround added no measurable startup cost: headless
medians 25.4ms with it and 25.9ms without, inside sets spanning 24.4–28.4ms.

### `sync_scroll` costs ~3.2µs per attached socket per cursor move — keep it `true`

Measured 2026-07-28 on the Fedora box, interleaved A/B over 6 reps, 2000 synchronous
`CursorMoved` dispatches per run, `vim.ui.open` stubbed so no real browser skews the client list:

| connected clients | `sync_scroll = true` | `= false` | attributable cost |
| --- | --- | --- | --- |
| 0 | 121.6µs/move | 113.5µs | 8.1µs — **inside the noise** |
| 1 | 125.7µs | 112.1µs | 13.6µs |
| 5 | 137.9µs | 108.9µs | 29.0µs |
| 20 | 184.7µs | 111.7µs | 73.0µs |

So the cost is real but linear and small: ~8µs fixed plus ~3.2µs per entry in
`connecting_clients`. The `false` arm is flat at ~111µs whatever the client count, which is what
confirms the whole difference is the handler's per-client writes. Against a 16ms frame budget the
worst measured case is 0.45%. **`sync_scroll = false` in `webpreview.lua` is not worth making** —
it would remove a feature that demonstrably works to dodge a cost that does not resolve above
noise with a single browser attached.

The number that grows is not the handler, it is `connecting_clients` (see below). And the
accumulated *handlers* are nearly free: 1/3/5 starts gave 134.7/138.4/143.3µs at 5 clients —
~2µs each, not the ~16µs each they would cost if they multiplied. They early-return, because
`send_scroll` sets `cursor_line` and copies 2..N find it already equal.

## Style of work expected here

Report what was measured, not what should follow from the code. Several bugs in this repo
survived because a plausible-looking check (`language.add`, coloured terminal output, a plugin
being `loaded`) was accepted as proof. When something is unverified, say so.

The live preview work is the cautionary tale to read first. A stray `nvim` holding port 5500
turned an hour of clean-looking measurements into a fabricated conclusion about garbage
collection — complete with a plausible mechanism in the source and an A/B that "confirmed" it.
Both arms were talking to a process that was not under test. The check that would have caught it
immediately was already written down here: kill strays, and look at what is listening.

Its sequel is milder but the same shape: **an empty probe file is not evidence of anything.**
Verifying the Linux branch hit three unrelated ways to write no output at all — `script` absent
on Fedora (exit 127), zsh mangling an inline `-c 'lua …'` block before nvim started, and
`vim.wait` blocking the loop that detects `TextChanged`. Each looked exactly like "the feature is
broken", and one of them nearly got written up as a plugin bug. Before concluding a probe proved
a negative, prove the probe *ran*: check its exit status, and have it write a sentinel on the
success path so you can tell "it failed" from "it never got there".
