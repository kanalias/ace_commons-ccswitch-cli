<#
.SYNOPSIS
  Install global Claude Code rules (Windows / PowerShell).

.DESCRIPTION
  Copies or symlinks rules\*.md into %USERPROFILE%\.claude\rules\. Existing files are
  never clobbered. Symlink mode requires Administrator (or Developer Mode) on Windows —
  falls back to copy with a warning if link creation fails.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-rules.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Src       = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "rules"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$DestDir   = Join-Path $ClaudeDir "rules"

if (-not (Test-Path $Src)) {
  Write-Host "no rules\ dir found next to this script — nothing to install"
  exit 0
}

try {
  $ans = Read-Host "── install global rules into $DestDir ? [c]opy / [s]ymlink / [N]o"
} catch {
  Write-Host "skipped (no input available)"
  exit 0
}

switch ($ans.ToLower()) {
  "c" { $mode = "copy" }
  "s" { $mode = "symlink" }
  default { Write-Host "skipped"; exit 0 }
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

Get-ChildItem (Join-Path $Src "*.md") | ForEach-Object {
  $name = $_.Name
  $dest = Join-Path $DestDir $name
  if ((Test-Path $dest) -or (Get-Item -Path $dest -Force -ErrorAction SilentlyContinue)) {
    Write-Host "  • rules\$name exists — kept"
    return
  }
  if ($mode -eq "copy") {
    Copy-Item $_.FullName $dest -Force
    Write-Host "  ✓ rules\$name (copied)"
  } else {
    try {
      New-Item -ItemType SymbolicLink -Path $dest -Target $_.FullName -ErrorAction Stop | Out-Null
      Write-Host "  ✓ rules\$name (symlinked → $($_.FullName))"
    } catch {
      Copy-Item $_.FullName $dest -Force
      Write-Host "  ✓ rules\$name (copied — symlink needs Administrator/Developer Mode)"
    }
  }
}
