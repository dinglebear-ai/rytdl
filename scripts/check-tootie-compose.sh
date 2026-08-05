#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
SOURCE=$ROOT/ops/compose/tootie
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

cp -a "$SOURCE/." "$TMP/"
cp "$TMP/.env.example" "$TMP/.env"

for required in CLAUDE.md AGENTS.md GEMINI.md CHANGELOG.md README.md .env.example docker-compose.yaml mcp-stdio.sh; do
  test -e "$SOURCE/$required" || { echo "missing $required" >&2; exit 1; }
done

for link in AGENTS.md GEMINI.md; do
  test -L "$SOURCE/$link"
  test "$(readlink "$SOURCE/$link")" = CLAUDE.md
done

sh -n "$SOURCE/mcp-stdio.sh"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh "$SOURCE/mcp-stdio.sh"
fi

docker compose -f "$TMP/docker-compose.yaml" config --no-interpolate --quiet

if grep -Eq '^[[:space:]]*version:' "$SOURCE/docker-compose.yaml"; then
  echo 'legacy Compose version field is forbidden' >&2
  exit 1
fi
grep -F 'image: ghcr.io/dinglebear-ai/rytdl:main' "$SOURCE/docker-compose.yaml" >/dev/null
grep -F 'external: true' "$SOURCE/docker-compose.yaml" >/dev/null
if grep -Eq '^[[:space:]]*ports:' "$SOURCE/docker-compose.yaml"; then
  echo 'RYTDL is stdio-only; ports are forbidden' >&2
  exit 1
fi
if git ls-files --error-unmatch ops/compose/tootie/.env >/dev/null 2>&1; then
  echo 'live .env must not be tracked' >&2
  exit 1
fi

echo 'TOOTIE Compose contract is valid'
