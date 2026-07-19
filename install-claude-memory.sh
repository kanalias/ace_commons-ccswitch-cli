#!/usr/bin/env bash
# One entry point for global Claude rules install — detects OS, runs the matching script.
# macOS/Linux: bash setup-rules.sh. Windows (Git Bash/WSL/Cygwin): powershell.exe setup-rules.ps1.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${OSTYPE:-}" in
  msys*|cygwin*)
    # Git Bash / Cygwin on native Windows — no Unix symlinks, use the PowerShell script.
    command -v cygpath >/dev/null 2>&1 || { echo "❌ 'cygpath' not found (expected in Git Bash/Cygwin). Run instead: powershell -ExecutionPolicy Bypass -File setup-rules.ps1" >&2; exit 1; }
    powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w "$SRC/ai-memory-rules/setup-rules.ps1")"
    ;;
  *)
    # macOS, Linux, and WSL (real Linux userland) — bash script works natively.
    bash "$SRC/ai-memory-rules/setup-rules.sh"
    ;;
esac
