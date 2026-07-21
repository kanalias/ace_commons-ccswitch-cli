#!/usr/bin/env bash
# Cài "harness" (orchestrator + delegate subagent mechanism) vào project khác.
# Thin entry — logic thật ở harness-delegate/install.sh (đọc file đó để biết flow).
# Delegate wrapper là bash-only → Windows cần WSL hoặc Git-Bash (không chạy CMD/PowerShell thuần).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/harness-delegate/install.sh" "$@"
