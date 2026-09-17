#!/usr/bin/env bash
# One entry point for ccswitch install — detects OS, runs the matching setup script.
# macOS/Linux: bash setup.sh. Windows (Git Bash/WSL/Cygwin): powershell.exe setup.ps1.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${OSTYPE:-}" in
  msys*|cygwin*)
    # Git Bash / Cygwin on native Windows — no Unix symlinks, use the PowerShell script.
    command -v cygpath >/dev/null 2>&1 || { echo "❌ 'cygpath' not found (expected in Git Bash/Cygwin). Run instead: powershell -ExecutionPolicy Bypass -File setup.ps1" >&2; exit 1; }
    powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w "$SRC/ai-proxy/setup.ps1")"
    ;;
  *)
    # macOS, Linux, and WSL (real Linux userland) — bash script works natively.
    bash "$SRC/ai-proxy/setup.sh"
    ;;
esac
