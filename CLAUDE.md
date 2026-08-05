# ytdl-rmcp — agent memory

Cross-platform single-binary MCP server: downloads media with yt-dlp, embeds
metadata + cover art, organizes by artist, and transfers to a **local**, **SSH**,
or **rclone** target. Also does AcoustID/MusicBrainz identification + retagging
and optional Plex playlist sync. Rust on the `rmcp` crate; yt-dlp + ffmpeg are
auto-downloaded at runtime.

User-facing docs live in `README.md`. This file is for working **on** the repo.

## Repo facts

| Fact | Value |
| --- | --- |
| Remote | `git@github.com:dinglebear-ai/rytdl.git`, default branch `main` |
| Layout | Single-crate Cargo workspace (`members = ["."]`); no `crates/` dir |
| Crate name | `ytdl-rmcp` (`Cargo.toml` `[package].name`) |
| Binary | `rytdl` (`[[bin]]`, also `default-run`) |
| Edition / MSRV | 2024 / Rust 1.97.1 |
| MCP crate | `rmcp = "=3.0.0-beta.2"`, `default-features = false`, features `server`/`macros`/`transport-io`/`schemars` |
| Transport | **stdio only. There is NO HTTP server and no service port.** `transport-io` is the only transport feature; nothing in `src/` binds a socket |
| TOOTIE deployment | Product-owned persistent runtime declaration at `ops/compose/tootie/`; MCP sessions launch through `mcp-stdio.sh` using `docker exec -i` |
| Lints | Workspace Clippy + rustdoc Phase-0 policy; CI gates with `clippy -D warnings` |

Two deliberate divergences from the rest of the rmcp fleet:

- **No port.** Unlike `rgotify` (40020), `runifi` (40030), etc., this server is
  launched per-session over stdio by an MCP client. Do not invent a port for
  docs, manifests, or the gateway config.
- **No full CLI↔MCP parity.** The CLI is only `serve` / `setup` / `doctor`;
  every media operation is MCP-tool-only. That is intentional — the binary is
  distributed as a client-launched plugin, not an operator CLI.

**Retired (2026-07-27):** the `marketplace-no-mcp` branch variant is gone —
branch deleted locally and on the remote, protection policy removed. Older
`docs/sessions/*.md` logs still describe it as a protected long-lived branch;
those are historical records, and this file overrides them. Do not recreate it.

## Architecture (module layout)

`src/`, all files < 500 LOC, `foo.rs` + `foo/` (never `mod.rs`):

| File | Role |
| --- | --- |
| `main.rs` | clap dispatch: bare or `serve` → serve stdio, `setup` → installer, `doctor` → diagnostics; stderr tracing |
| `config.rs` | `Config::from_env_result` — all `YTDLP_*` env vars (the panicking `from_env` is now `#[cfg(test)]`-only) |
| `doctor.rs` | `ytdl-rmcp doctor` — read-only install/diagnostics probe: prints version/git-sha, platform, resolved tool paths, and redacted config presence |
| `model.rs` | tool input structs + enums (serde + schemars); `Urls` accepts string or array |
| `mcp.rs` | `rmcp` `ServerHandler` via `#[tool_router]`/`#[tool]`/`#[tool_handler]` — **8 tools**: `youtube_download`, `youtube_probe`, `youtube_identify`, `youtube_search`, `youtube_stats`, `youtube_plex_playlist`, `youtube_transfer_queue`, `youtube_search_ui` |
| `service.rs` | orchestration: resolve tools → download → (retag) → transfer → (Plex) → ledger → format payload |
| `service/format.rs` | render the response payload as JSON or Markdown per `ResponseFormat` |
| `service/retag.rs` | in-place AcoustID/MusicBrainz retag of staged audio before transfer |
| `service/plex_tracks.rs` | map transferred audio files onto Plex tracks for playlist adds |
| `downloader.rs` | builds the yt-dlp argv, runs it, parses `--print` output; `fetch` (download) path |
| `downloader/probe.rs` | `ProbeResult` + `probe`: metadata-only yt-dlp query (no media download) |
| `transfer.rs` | target parsing (`TargetPath::{Local,Ssh,Rclone}`) + dispatch: local → in-process Rust dir copy, SSH → rsync-or-scp + `ensure_remote_dir`, rclone → `rclone copy` |
| `transfer_queue.rs` | retained-staging failure manifests; backs `youtube_transfer_queue` list/drain |
| `history.rs` | persistent JSONL download ledger + `youtube_stats` aggregation derived from it |
| `history/candidates.rs` | selects transferred-audio candidates from the ledger for Plex playlist builds |
| `identify.rs` | AcoustID fingerprint (fpcalc) → MusicBrainz lookup → retag preview; backs `youtube_identify` |
| `identify/musicbrainz.rs` | MusicBrainz REST client + `RetagPreview` scoring |
| `identify/tagger.rs` | writes retag-preview tags into the audio file via `lofty` |
| `plex.rs` | optional Plex integration — search/match tracks, create playlists |
| `plex/playlist.rs` | Plex playlist create/append REST calls |
| `search_app.rs` | MCP-app HTML resource (`ui://…/youtube-search.html`) backing `youtube_search_ui` |
| `bootstrap.rs` + `bootstrap/{ytdlp,ffmpeg,http}.rs` | resolve/install yt-dlp + ffmpeg into the cache dir |
| `urls.rs` | YouTube mix/radio URL cleaning |
| `setup.rs` | interactive installer; registers into claude/codex/gemini via `mcp add` |
| `util.rs` | shared `command_error` + the single subprocess runner (`run_capped`) used by the downloader, probe, fingerprinter, and transfer paths |

Tests are sibling `foo_tests.rs` files wired via `#[cfg(test)] #[path = "foo_tests.rs"] mod tests;`.

## Conventions

- **No file over 500 LOC.** Split into a `foo/` dir with submodules instead.
- **No `mod.rs`** — `foo.rs` declares `mod bar;` resolving to `foo/bar.rs`.
- **Sibling test files** — `foo_tests.rs` next to `foo.rs`, never inline `mod tests {}`.
  A large module MAY also carry extra focused test files under its `foo/` submodule
  dir (e.g. `service/render_tests.rs`, `service/stats_identify_tests.rs`), each wired
  with its own `#[cfg(test)] #[path = "service/render_tests.rs"] mod render_tests;`,
  in addition to the canonical sibling `service_tests.rs`.
- **stdout is the JSON-RPC channel** — ALL logging goes to **stderr**
  (`tracing_subscriber ... .with_writer(std::io::stderr)`). Never print to stdout
  outside the MCP transport, and never forward yt-dlp's captured stdout.

## Build / test / cross-compile

```bash
cargo build --release
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt --all --check                       # CI gates on this

# Windows cross-build (needs: apt install nasm llvm clang lld; cargo install cargo-xwin):
cargo xwin build --release --target x86_64-pc-windows-msvc
```

The plain `cargo xwin` form above is correct for CI and ordinary shells.
**GOTCHA — the cargo wrapper.** `~/.local/bin/cargo` is a wrapper that runs
builds inside a constrained systemd slice and breaks `cargo xwin` (manifests as
`error[E0463]: can't find crate for std` on one dep). For cross-compilation,
invoke the real rustup cargo directly: `~/.cargo/bin/cargo xwin build …`.

## Key gotchas

- **TLS / cross-compile**: downloads use `ureq` 3 with `rustls`+**ring** (NOT
  aws-lc). ffmpeg-sidecar piggybacks on the same ureq. Verify after any dep bump:
  `cargo tree -i aws-lc-sys` must be empty, or the Windows build breaks.
- **Bootstrap trust**: `YTDLP_SHA256` and `FFMPEG_SHA256` optionally pin the
  resolved executable bytes. This is hash pinning, not upstream signature
  verification; known-good binaries plus `YTDLP_PATH` / `FFMPEG_PATH` are the
  strictest supported mode.
- **Local targets do NOT use rsync.** `transfer.rs` dispatches
  `TargetPath::Local` to an in-process Rust directory copy
  (`copy_dir_contents_blocking`, which also refuses a dest nested inside the
  source). Only **SSH** targets shell out — rsync `-a --partial -s`
  (`-s` == `--protect-args`) when `rsync` is on `PATH`, else `scp`. rclone
  targets shell out to `rclone copy`. Local targets additionally require
  `YTDLP_ALLOW_LOCAL_TARGETS=true`.
- **Timeouts**: `YTDLP_TIMEOUT_SECS` defaults to 1800 and is enforced for
  yt-dlp download/probe commands. `YTDLP_TRANSFER_TIMEOUT_SECS` defaults to 600
  and is enforced around each transfer phase from `service.rs`.
- **Edition 2024 is fleet policy.** Keep Linux checks, the Windows x64 cross-build,
  and plugin startup verification together when changing build or packaging code.
- **`--windows-filenames` is always on** so the `Artist/Title [id]` layout is
  identical across OSes. Side effect: a trailing `.` in a name (e.g. "Disney Jr.")
  becomes "Disney Jr.#".
- **Some videos need a specific yt-dlp player client** (e.g. Disney content fails
  on the default but works with `youtube:player_client=android`). Surface via the
  `YTDLP_EXTRACTOR_ARGS` env var (`--extractor-args`).
- **Probe doesn't download ffmpeg** — the probe path (`src/downloader/probe.rs`,
  driven from `service.rs`) resolves only `bootstrap::ensure_ytdlp` (yt-dlp); only
  `youtube_download` pulls ffmpeg.
- **Testing the stdio server**: a piped-stdin smoke test EOFs and rmcp closes
  after a ~5s drain — slow first-run downloads get cut off. Hold stdin open
  (`{ printf …; sleep N; } | bin serve`) or use `mcporter` (real MCP client).
- **Windows testing**: cross-build the `.exe`, run it on **agent-os** (the Windows
  VM) over `ssh agent-os` — serve via a `Diagnostics.Process` harness that keeps
  stdin open and redirect stdout to a file (SSH buffers piped stdout).

## Distribution

- **GitHub**: `dinglebear-ai/rytdl`. Workflows in `.github/workflows/`:
  `ci.yml` (fmt/clippy/test + Windows cross-build smoke per push/PR),
  `release.yml` (linux + windows-msvc binaries + the mcpb bundle on `v*`),
  `release-please.yml`, `container.yml` (ghcr image on `main`), `audit.yml`,
  `codeql.yml`, and `openwiki-update.yml`.
- **npm launcher**: `packages/ytdl-rmcp` publishes `ytdl-rmcp` to npm. MCP clients
  should launch with `npx -y @dinglebear/rytdl`; the npm postinstall/lazy installer
  downloads the matching GitHub Release binary.
- **Claude Code plugin**: root `.claude-plugin/plugin.json` + `.mcp.json` +
  `skills/ytdl/`. `.mcp.json` uses `npx -y @dinglebear/rytdl` plus plugin `userConfig`
  env mapping. **This plugin ships no hooks** — there is no `hooks/` dir and
  `plugin.json` has no `hooks` key; do not reintroduce one.
- **Container**: `Dockerfile` → `ghcr.io/dinglebear-ai/rytdl:main`, bundling
  ffmpeg, fpcalc, openssh-client, rclone, and rsync. See `docs/container.md`.
- **Gemini extension**: `gemini-extension.json` (settings → `YTDLP_*` env vars);
  prefer the npm launcher command for MCP stdio registration.
- **MCP bundle**: `mcpb/manifest.json` (`server.type: "binary"`, manifest schema
  `0.3`). `scripts/build-mcpb.sh` stages the linux + windows binaries into
  `server/` and runs the `@anthropic-ai/mcpb` CLI to produce `ytdl-rmcp.mcpb`; the
  `mcpb` job in `release.yml` attaches it to `v*` releases. Targets
  `["linux", "win32"]` only — no macOS binary is built. `check-packaging.sh`
  cross-checks all four config surfaces: the Claude plugin's `userConfig`
  (`.claude-plugin/plugin.json`), the `.mcp.json` `user_config` references and env
  mapping, the mcpb manifest's `user_config` keys ↔ `mcp_config.env`, and
  `gemini-extension.json`'s `envVar`s — verifying they stay in sync and that every
  Gemini env var follows the `YTDLP_`/`FFMPEG_`/`FPCALC_PATH` naming and maps into
  `.mcp.json`.

## Per-CLI `mcp add` arg ordering (setup.rs)

Each CLI parses repeated/variadic env flags differently:
- claude: `mcp add -s user <name> -e K=V… -- <cmd>`
- codex:  `mcp add --env K=V… <name> -- <cmd>`
- gemini: `mcp add -s user <name> <cmd> -e K=V…` (env array goes last)

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
