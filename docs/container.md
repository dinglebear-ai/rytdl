---
title: "Container Runtime"
created: 2026-06-12
updated: 2026-08-05
---

# Container Runtime

The container image packages `ytdl-rmcp` with the host tools needed for download,
fingerprinting, tagging, and transfer workflows:

- `ffmpeg`
- `fpcalc` from `libchromaprint-tools`
- `openssh-client` for `host:/path` targets
- `rclone` for `remote:path` targets
- `rsync` for resumable local/SSH transfers
- CA certificates

The server still runs MCP over stdio by default.

## Product-owned TOOTIE deployment

The supported persistent TOOTIE runtime declaration lives at:

```text
ops/compose/tootie/docker-compose.yaml
```

It deliberately overrides the image entrypoint with `sleep infinity`, retaining the container as a stable environment containing RYTDL, yt-dlp bootstrap state, ffmpeg, fpcalc, SSH, rclone, rsync, and mounted media. Each MCP session is started independently over stdio with:

```bash
ops/compose/tootie/mcp-stdio.sh
```

The helper runs `docker exec -i ytdl-mcp ytdl-rmcp serve`; it allocates no TTY and exposes no HTTP port. The current live deployment remains at `tootie:/mnt/user/compose/ytdl-mcp` until an explicit reviewed deploy/sync copies the product-owned declaration there.

Validate the declaration with:

```bash
scripts/check-tootie-compose.sh
```

## Build

```bash
docker build -t ytdl-rmcp:local .
```

## Published Image

Every push to `main` publishes:

```text
ghcr.io/dinglebear-ai/rytdl:main
ghcr.io/dinglebear-ai/rytdl:main-<git-sha>
```

Pull the latest `main` image with:

```bash
docker pull ghcr.io/dinglebear-ai/rytdl:main
```

## Run As An MCP Server

Mount SSH credentials if `youtube_download` transfers to a `host:/path` target.
Keep state and cache directories mounted so yt-dlp, ffmpeg sidecars, the ledger,
and archives survive container restarts.

```bash
docker run --rm -i \
  -e YTDLP_TARGET_PATH=nashost:/mnt/user/data/media/music/yt-dlp \
  -e YTDLP_HISTORY_PATH=/home/ytdl/.local/state/ytdl-rmcp/downloads.jsonl \
  -v "$HOME/.ssh:/home/ytdl/.ssh:ro" \
  -v ytdl-rmcp-state:/home/ytdl/.local/state/ytdl-rmcp \
  -v ytdl-rmcp-cache:/home/ytdl/.cache \
  ghcr.io/dinglebear-ai/rytdl:main serve
```

For MCP clients that expect a command, use
`docker run --rm -i ... ghcr.io/dinglebear-ai/rytdl:main serve` as the command.

## Identify A Mounted Library

`youtube_identify` reads local paths from inside the container. Mount the library
and pass container paths such as `/library/...`.

```bash
docker run --rm -i \
  -e YTDLP_ACOUSTID_CLIENT_KEY="$YTDLP_ACOUSTID_CLIENT_KEY" \
  -e YTDLP_MUSICBRAINZ_CONTACT="you@example.com" \
  -v /mnt/user/data/media/music/yt-dlp:/library \
  ghcr.io/dinglebear-ai/rytdl:main serve
```

Then call:

```json
{
  "paths": "/library/Artist/Song [id].mp3",
  "write_tags": false,
  "response_format": "json"
}
```

Run with `write_tags=false` first and save the JSON response as a report. After
reviewing candidates, rerun only accepted files with `write_tags=true`.

## Batch Shape For The Existing yt-dlp Library

The current yt-dlp audio library on nashost is expected at:

```text
/mnt/user/data/media/music/yt-dlp
```

A safe batch pass should:

1. Inventory audio files under the mounted library.
2. Call `youtube_identify` with `write_tags=false`.
3. Save one JSONL row per file with candidates, preview, and errors.
4. Write tags only for high-confidence reviewed rows.

This avoids blindly mutating files where AcoustID returns multiple plausible
MusicBrainz releases or soundtrack variants.
