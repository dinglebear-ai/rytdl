# RYTDL TOOTIE Deployment

## Service

Product-owned TOOTIE deployment for the `dinglebear-ai/rytdl` stdio MCP server. The container remains alive as a persistent tool/runtime environment; each MCP client session starts `ytdl-rmcp serve` through `mcp-stdio.sh`. No HTTP listener or service port exists.

## Ownership and paths

- Product repository source: `dookie:/home/jmagar/workspace/rytdl/ops/compose/tootie`
- Repository: `git@github.com:dinglebear-ai/rytdl.git`
- Current live project: `tootie:/mnt/user/compose/ytdl-mcp`
- Current live config: `tootie:/mnt/user/compose/ytdl-mcp/compose.yml`
- Persistent state: `tootie:/mnt/cache/appdata/ytdl-mcp/state`
- Persistent cache: `tootie:/mnt/cache/appdata/ytdl-mcp/cache`
- Media library: `tootie:/mnt/user/data/media/music/yt-dlp`
- Network: external `jakenet`
- Published ports: none

The repository declaration is not copied to TOOTIE automatically. A merge changes declared state only. Use an explicit reviewed deploy/sync with backup and rollback before replacing the live Compose file.

## Runtime shape

The image defaults to stdio serving, but the TOOTIE deployment overrides the entrypoint with `sleep infinity`. This keeps yt-dlp, ffmpeg, fpcalc, SSH, rclone, rsync, cache, and state available in a stable container. MCP clients launch a fresh protocol session with:

```bash
ops/compose/tootie/mcp-stdio.sh
```

The helper uses `docker exec -i` and does not allocate a TTY. Stdout remains the JSON-RPC channel.

## Validation

```bash
scripts/check-tootie-compose.sh
```

Before a live deploy, also verify:

```bash
ssh tootie 'docker compose -f /mnt/user/compose/ytdl-mcp/compose.yml config --quiet'
ssh tootie 'docker exec ytdl-mcp ytdl-rmcp --version'
```

After deployment, verify the container health, mounted paths, ownership under UID/GID `99:100`, and one real stdio MCP initialize/tools-list session.

## Guardrails

- Do not add an HTTP port. The product is stdio-only.
- Do not commit `.env`, API keys, contact addresses, SSH keys, state, cache, downloads, or media.
- Keep `.env.example` synchronized with deployment variables.
- Preserve external `jakenet`.
- Update this directory's `CHANGELOG.md`, root `CHANGELOG.md`, and product container docs for meaningful deployment changes.
- Product source and deployment declarations remain in `dinglebear-ai/rytdl`; homelab stores a reference only.
