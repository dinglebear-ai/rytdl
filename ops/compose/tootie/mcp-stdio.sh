#!/bin/sh
set -eu

container=${RYTDL_CONTAINER_NAME:-ytdl-mcp}
exec docker exec -i "$container" ytdl-rmcp serve
