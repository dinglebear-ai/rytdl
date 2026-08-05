# TOOTIE Compose Deployment

Product-owned declaration for the persistent TOOTIE RYTDL runtime container. It exposes no network port. MCP clients use `mcp-stdio.sh`, which starts `ytdl-rmcp serve` through `docker exec -i`.

This repository directory is declared state. The current live deployment remains at `/mnt/user/compose/ytdl-mcp` until an explicit deploy/sync is performed.

```bash
scripts/check-tootie-compose.sh
```
