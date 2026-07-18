<#
.SYNOPSIS
  Install global Claude Code rules (Windows / PowerShell).

.DESCRIPTION
  Copies rules\*.md into %USERPROFILE%\.claude\rules\, always overwriting any existing
  file (no symlink mode — symlinking personal rules into a repo-tracked path is a leak
  risk if the repo is ever shared/forked).

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
  $ans = Read-Host "── copy global rules into $DestDir (overwrites existing)? [y/N]"
} catch {
  Write-Host "skipped (no input available)"
  exit 0
}

if ($ans.ToLower() -ne "y") {
  Write-Host "skipped"
  exit 0
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

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
