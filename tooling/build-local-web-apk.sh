#!/usr/bin/env bash
# Phone-local DSH + Android tools, with the original web UI as the only home.
# Accepts the same options as build-apk.sh, including --dry-run and -f arm64|x64|all.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec bash "$ROOT/tooling/build-apk.sh" "$@"
