<#
.SYNOPSIS
  Install global Claude Code rules (Windows / PowerShell).

.DESCRIPTION
  Mirrors rules\*.md into %USERPROFILE%\.claude\rules\: always overwrites existing
  files, and removes any *.md in the destination that no longer exists in rules\
  (e.g. a rule deleted from this repo). No symlink mode — symlinking personal
  rules into a repo-tracked path is a leak risk if the repo is ever shared/forked.

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
  $ans = Read-Host "── mirror global rules into $DestDir (overwrites + removes anything not in rules\)? [y/N]"
} catch {
  Write-Host "skipped (no input available)"
  exit 0
}

if ($ans.ToLower() -ne "y") {
  Write-Host "skipped"
  exit 0
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if (Test-Path $DestDir) {
  Get-ChildItem (Join-Path $DestDir "*.md") -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $srcMatch = Join-Path $Src $_.Name
    if (-not (Test-Path $srcMatch)) {
      Remove-Item -Path $_.FullName -Force
      Write-Host "  ✗ rules\$($_.Name) (removed — not in repo)"
    }
  }
}

Get-ChildItem (Join-Path $Src "*.md") | ForEach-Object {
  $name = $_.Name
  $dest = Join-Path $DestDir $name
  $existing = Get-Item -Path $dest -Force -ErrorAction SilentlyContinue
  if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Remove-Item -Path $dest -Force
  }
  Copy-Item $_.FullName $dest -Force
  Write-Host "  ✓ rules\$name (copied)"
}
