<#
.SYNOPSIS
  ccswitch setup (Windows / PowerShell).

.DESCRIPTION
  Installs ccswitch.ps1 + profile templates + SessionStart health hook into %USERPROFILE%\.claude,
  then registers a `ccswitch` function in your PowerShell profile. Never overwrites existing
  profile files that already hold real keys — templates are only copied when missing.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Src       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Profiles  = Join-Path $ClaudeDir "profiles"
$Hooks     = Join-Path $ClaudeDir "hooks"
$Settings  = Join-Path $ClaudeDir "settings.json"

Write-Host "▶ ccswitch setup — installing into $ClaudeDir"

New-Item -ItemType Directory -Force -Path $Profiles, $Hooks | Out-Null

# 1. tool (always refreshed — no secrets inside)
Copy-Item (Join-Path $Src "ccswitch.ps1") (Join-Path $ClaudeDir "ccswitch.ps1") -Force
Copy-Item (Join-Path $Src "hooks\check-router.sh") (Join-Path $Hooks "check-router.sh") -Force
Write-Host "  ✓ ccswitch.ps1 + hooks\check-router.sh"

# 2. profile templates — copy ONLY if missing (never clobber a real key).
# 3 router profiles (claude, codex, deepseek), all via 9router, sharing ONE token.
$ProfileTargets = @("claude", "codex", "deepseek")
foreach ($t in $ProfileTargets) {
  $dst = Join-Path $Profiles "$t.json"
  if (Test-Path $dst) {
    Write-Host "  • profiles\$t.json exists — kept (edit manually or run: ccswitch set-key $t)"
  } else {
    Copy-Item (Join-Path $Src "profiles\$t.json") $dst -Force
    Write-Host "  ✓ profiles\$t.json (template — fill in your key)"
  }
}

# 2b. fill credentials into all 3 profiles (claude/codex/deepseek share ONE 9router token).
# Preferred source: `.env.pro` next to this script (gitignored) holding `proxy_host=` +
# `proxy_key=`. When both are present we ask ONCE — Enter / yes (default) writes host + key
# into all three profiles; no falls back to the manual prompts (host, then key). Key values
# are never echoed. Non-interactive: .env.pro is applied only while the profiles still hold
# placeholders — a real key is never clobbered without a terminal to confirm.
$EnvPro = Join-Path $Src ".env.pro"

function Test-AnyRealKey {
  foreach ($t in $ProfileTargets) {
    $p = Get-Content (Join-Path $Profiles "$t.json") -Raw | ConvertFrom-Json
    if ($p.ANTHROPIC_AUTH_TOKEN -and $p.ANTHROPIC_AUTH_TOKEN -notmatch '<your-9router-key>') { return $true }
  }
  return $false
}

function Get-EnvProValue([string]$name) {
  foreach ($line in Get-Content $EnvPro) {
    if ($line -match "^\s*$name\s*=\s*(.*)$") {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return ""
}

function Set-AllProfiles([string]$url, [string]$key) {
  $failed = $false
  foreach ($t in $ProfileTargets) {
    $dst = Join-Path $Profiles "$t.json"
    Copy-Item $dst "$dst.bak" -Force
    try {
      $p = Get-Content $dst -Raw | ConvertFrom-Json
      if ($url) { $p.ANTHROPIC_BASE_URL = $url }
      if ($key) { $p.ANTHROPIC_AUTH_TOKEN = $key }
      $p | ConvertTo-Json -Depth 10 | Set-Content $dst -Encoding UTF8
    } catch {
      Write-Host "  ❌ failed to write profiles\$t.json (profile unchanged)"
      $failed = $true
    }
  }
  return -not $failed
}

$envProHost = ""; $envProKey = ""
if (Test-Path $EnvPro) {
  $envProHost = Get-EnvProValue "proxy_host"
  $envProKey  = Get-EnvProValue "proxy_key"
}

$useEnvPro = $false
if ($envProHost -and $envProKey) {
  if ([Environment]::UserInteractive) {
    if (Test-AnyRealKey) { Write-Host "  • profiles already hold a key — answering Yes overwrites all three." }
    $ans = Read-Host "  ▸ Use proxy_host + proxy_key from .env.pro for all profiles (claude/codex/deepseek)? [Y/n]"
    if ($ans -notmatch '^(n|no)$') { $useEnvPro = $true }
  } else {
    if (Test-AnyRealKey) {
      Write-Host "  • .env.pro found but profiles already hold a key — kept (overwrite: re-run interactively, or ccswitch set-key)"
    } else {
      $useEnvPro = $true
      Write-Host "  • non-interactive session — using proxy_host + proxy_key from .env.pro (default Yes)"
    }
  }
} elseif (Test-Path $EnvPro) {
  Write-Host "  • .env.pro found but missing proxy_host/proxy_key — ignored"
}

if ($useEnvPro) {
  if (Set-AllProfiles $envProHost $envProKey) {
    Write-Host "  ✓ .env.pro proxy_host + proxy_key applied to profiles\{$($ProfileTargets -join ',')}.json"
  }
} elseif (-not [Environment]::UserInteractive) {
  Write-Host "  • non-interactive session — skipped key prompt (edit profiles\*.json manually)"
} else {
  $cur = (Get-Content (Join-Path $Profiles "claude.json") -Raw | ConvertFrom-Json).ANTHROPIC_BASE_URL
  $host_ = Read-Host "  ▸ Router base URL [$cur] (Enter to keep)"
  if ($host_) {
    if (Set-AllProfiles $host_ "") { Write-Host "  ✓ base URL saved to profiles\{$($ProfileTargets -join ',')}.json" }
  } else {
    Write-Host "    kept current base URL."
  }

  $anyReal = Test-AnyRealKey
  $ask = $true
  if ($anyReal) {
    $ans = Read-Host "  • one or more profiles already hold a key. Overwrite all with a new shared key? [y/N]"
    if ($ans -notmatch '^(y|yes)$') { Write-Host "    kept existing keys."; $ask = $false }
  }
  if ($ask) {
    $secure = Read-Host "  ▸ Paste the shared 9router key (input hidden, Enter to skip)" -AsSecureString
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key    = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ([string]::IsNullOrEmpty($key)) {
      Write-Host "    no key entered — kept placeholders (edit profiles\*.json later)."
    } else {
      if (Set-AllProfiles "" $key) {
        Write-Host "  ✓ shared router key saved to profiles\{$($ProfileTargets -join ',')}.json"
      }
    }
    $key = $null
  }
}

# 3. ensure settings.json exists + wire SessionStart hook idempotently
if (-not (Test-Path $Settings)) { "{}" | Set-Content $Settings -Encoding UTF8 }
$HookCmd = "bash ~/.claude/hooks/check-router.sh"
$s = Get-Content $Settings -Raw | ConvertFrom-Json
$already = $false
if ($s.hooks -and $s.hooks.SessionStart) {
  foreach ($grp in $s.hooks.SessionStart) {
    foreach ($h in $grp.hooks) { if ($h.command -eq $HookCmd) { $already = $true } }
  }
}
if (-not $already) {
  Copy-Item $Settings "$Settings.bak" -Force
  if (-not $s.hooks) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
  if (-not $s.hooks.SessionStart) { $s.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() -Force }
  $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = $HookCmd }) }
  $s.hooks.SessionStart = @($s.hooks.SessionStart) + $entry
  $s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
  Write-Host "  ✓ wired SessionStart health hook into settings.json"
} else {
  Write-Host "  • SessionStart hook already wired — skipped"
}

# 3b. default model — set only if the user hasn't already chosen one (never clobber a pref).
$s = Get-Content $Settings -Raw | ConvertFrom-Json
if (-not (Get-Member -InputObject $s -Name model -MemberType NoteProperty)) {
  Copy-Item $Settings "$Settings.bak" -Force
  $s | Add-Member -NotePropertyName model -NotePropertyValue "sonnet" -Force
  $s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
  Write-Host "  ✓ set default model to sonnet in settings.json"
} else {
  Write-Host "  • settings.json already has a model preference — skipped"
}

# 4. register `ccswitch` function in PowerShell profile
$psProfile = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $psProfile
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (-not (Test-Path $psProfile)) { New-Item -ItemType File -Force -Path $psProfile | Out-Null }
$fnLine = 'function ccswitch { & powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\ccswitch.ps1" @args }'
if (-not (Select-String -Path $psProfile -SimpleMatch "function ccswitch" -Quiet)) {
  Add-Content $psProfile "`n$fnLine"
  Write-Host "  ✓ added ccswitch function to $psProfile"
} else {
  Write-Host "  • ccswitch function already in $psProfile — skipped"
}

# 4b. parallel-launcher functions — one per target. Each spawns a SEPARATE Claude Code
#     instance pinned to that vendor via process env. Run N in N terminals = N vendors in parallel.
$short = @{ claude = "cc"; codex = "cx"; deepseek = "ds" }
foreach ($t in @("claude", "codex", "deepseek")) {
  $fn = "claude-$($short[$t])"
  $line = "function $fn { & powershell -ExecutionPolicy Bypass -File `"`$env:USERPROFILE\.claude\ccswitch.ps1`" spawn $t @args }"
  if (-not (Select-String -Path $psProfile -SimpleMatch "function $fn " -Quiet)) {
    Add-Content $psProfile "`n$line"
    Write-Host "  ✓ added launcher $fn ($t) to $psProfile"
  } else {
    Write-Host "  • launcher $fn already in $psProfile — skipped"
  }
}

Write-Host ""
Write-Host "✅ Installed. Next steps:" -ForegroundColor Green
Write-Host "   1. (if you skipped the prompt) Fill a key:  ccswitch set-key <claude|codex|deepseek>  (same 9router key for all three)"
Write-Host "   2. Reload profile:  . `$PROFILE   then run: ccswitch claude"
Write-Host "   3. Restart Claude Code (quit + reopen) to load the new env."
Write-Host "   4. Parallel:  open 3 terminals -> claude-cc / claude-cx / claude-ds (shared 9router quota)"
Write-Host ""
Write-Host "Note: the health hook uses 'bash' (Git Bash / WSL). If you have neither, the hook is skipped harmlessly." -ForegroundColor DarkGray
