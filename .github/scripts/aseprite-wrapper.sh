#!/usr/bin/env bash
set -euo pipefail

exec docker run --rm \
  -v "${GITHUB_WORKSPACE}:${GITHUB_WORKSPACE}" \
  -w "${GITHUB_WORKSPACE}" \
  al1ydn/aseprite-linux-build:v1.3.2 \
  /app/bin/aseprite "$@"
