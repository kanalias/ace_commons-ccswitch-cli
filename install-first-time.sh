#!/usr/bin/env bash
# First-time bootstrap for ccswitch — run THIS right after cloning the repo.
# The global `ccswitch` command doesn't exist until this installs it, so first run
# must use the script path (not `ccswitch install …`). After this, use
# `ccswitch install proxy` to re-sync. Thin alias → install-9router-proxy.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/install-9router-proxy.sh" "$@"
