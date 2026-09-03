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
Set-Content -Path (Join-Path $ClaudeDir ".ccswitch-repo") -Value (Split-Path $Src -Parent)
Write-Host "  ✓ repo path recorded (ccswitch install)"
Copy-Item (Join-Path $Src "statusline-context.sh") (Join-Path $ClaudeDir "statusline-context.sh") -Force
Write-Host "  ✓ statusline-context.sh (context-usage early-warning bar)"

# 2. profile templates — copy ONLY if missing (never clobber a real key).
# 4 profiles: claude/codex/deepseek/kimi via 9router share ONE token.
# kimi_api_key_force_subscription=1 switches kimi to Kimi's own direct Anthropic-compatible endpoint instead.
$ProfileTargets = @("claude", "codex", "deepseek", "kimi")
$RouterTargets = @("claude", "codex", "deepseek", "kimi")
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
# Preferred source: `.env` at repo root (one level up from this script's dir, gitignored)
# holding `proxy_host=` + `proxy_key=`. When both are present, ALWAYS overwrite host + key
# in all three profiles — no prompt, no placeholder check, interactive or not. `.env` is the
# source of truth; re-run this script any time it changes to resync. No `.env` (or missing
# fields) falls back to the manual prompts (host, then key). Key values are never echoed.
$EnvPro = Join-Path (Split-Path $Src -Parent) ".env"

function Test-AnyRealKey {
  foreach ($t in $RouterTargets) {
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
  foreach ($t in $RouterTargets) {
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

function Set-KimiProfileFromEnv([string]$key) {
  if (-not $key) { return }
  $dst = Join-Path $Profiles "kimi.json"
  if (-not (Test-Path $dst)) { Copy-Item (Join-Path $Src "profiles\kimi.json") $dst -Force }
  Copy-Item $dst "$dst.bak" -Force
  try {
    $p = Get-Content $dst -Raw | ConvertFrom-Json
    $p.ANTHROPIC_BASE_URL = "https://api.moonshot.ai/anthropic"
    $p.ANTHROPIC_AUTH_TOKEN = $key
    $p.ANTHROPIC_DEFAULT_OPUS_MODEL = "kimi-k3"
    $p.ANTHROPIC_DEFAULT_SONNET_MODEL = "kimi-k3"
    $p.ANTHROPIC_DEFAULT_HAIKU_MODEL = "kimi-k3"
    $p.ANTHROPIC_DEFAULT_FABLE_MODEL = "kimi-k3"
    $p | ConvertTo-Json -Depth 10 | Set-Content $dst -Encoding UTF8
    Write-Host "  ✓ .env kimi_api_key applied to profiles\kimi.json (direct endpoint mode)"
  } catch {
    Write-Host "  ❌ failed to write profiles\kimi.json (profile unchanged)"
  }
}

$envProHost = ""; $envProKey = ""; $kimiForceSubscription = "0"; $kimiEnvKey = ""
if (Test-Path $EnvPro) {
  $envProHost = Get-EnvProValue "proxy_host"
  $envProKey  = Get-EnvProValue "proxy_key"
  $kimiForceSubscription = Get-EnvProValue "kimi_api_key_force_subscription"
  $kimiEnvKey = Get-EnvProValue "kimi_api_key"
}

$useEnvPro = $false
if ($envProHost -and $envProKey) {
  $useEnvPro = $true
  if (Test-AnyRealKey) { Write-Host "  • profiles already hold a key — .env always overrides host+key (by design, no prompt)." }
} elseif (Test-Path $EnvPro) {
  Write-Host "  • .env found but missing proxy_host/proxy_key — ignored"
}

if ($useEnvPro) {
  if (Set-AllProfiles $envProHost $envProKey) {
    Write-Host "  ✓ .env proxy_host + proxy_key applied to profiles\{$($RouterTargets -join ',')}.json"
  }
} elseif ([Console]::IsInputRedirected) {
  Write-Host "  • non-interactive session — skipped key prompt (edit profiles\*.json manually)"
} else {
  $cur = (Get-Content (Join-Path $Profiles "claude.json") -Raw | ConvertFrom-Json).ANTHROPIC_BASE_URL
  $host_ = Read-Host "  ▸ Router base URL [$cur] (Enter to keep)"
  if ($host_) {
    if (Set-AllProfiles $host_ "") { Write-Host "  ✓ base URL saved to profiles\{$($RouterTargets -join ',')}.json" }
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
        Write-Host "  ✓ shared router key saved to profiles\{$($RouterTargets -join ',')}.json"
      }
    }
    $key = $null
  }
}
if ($kimiForceSubscription -eq "1") {
  if ($kimiEnvKey) { Set-KimiProfileFromEnv $kimiEnvKey }
  else { Write-Host "  • kimi_api_key_force_subscription=1 but kimi_api_key missing — kimi profile kept" }
}
$kimiEnvKey = $null

# 3. ensure settings.json exists + wire SessionStart hook (upsert by basename, not exact
#    string match) — a stale entry pointing at a different path/wording for check-router.sh
#    would otherwise never get cleaned up and re-installs would pile up duplicate entries.
if (-not (Test-Path $Settings)) { "{}" | Set-Content $Settings -Encoding UTF8 }
$HookCmd = "bash ~/.claude/hooks/check-router.sh"
$s = Get-Content $Settings -Raw | ConvertFrom-Json
Copy-Item $Settings "$Settings.bak" -Force
if (-not $s.hooks) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
$existingGroups = @()
if ($s.hooks.SessionStart) { $existingGroups = @($s.hooks.SessionStart) }
$kept = @()
foreach ($grp in $existingGroups) {
  $remainingHooks = @($grp.hooks | Where-Object { $_.command -notmatch 'check-router\.sh' })
  if ($remainingHooks.Count -gt 0) { $kept += [pscustomobject]@{ hooks = $remainingHooks } }
}
$entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = $HookCmd }) }
$kept += $entry
if (-not $s.hooks.SessionStart) { $s.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() -Force }
$s.hooks.SessionStart = $kept
$s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
Remove-Item "$Settings.bak" -Force
Write-Host "  ✓ synced SessionStart health hook into settings.json"

# 3a. wire statusLine (context-usage early-warning bar) idempotently
$s = Get-Content $Settings -Raw | ConvertFrom-Json
$SlCmd = "bash ~/.claude/statusline-context.sh"
if ($s.statusLine.command -ne $SlCmd) {
  Copy-Item $Settings "$Settings.bak" -Force
  $s | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{ type = "command"; command = $SlCmd }) -Force
  $s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
  Write-Host "  ✓ wired statusLine (context-usage bar) into settings.json"
} else {
  Write-Host "  • statusLine already wired — skipped"
}

# 3b. default model — intentionally NOT set. Let Claude Code pick per its own default
#     (last-used / account default). Forcing a `.model` here caused a stale pin (e.g. sonnet)
#     to be requested even after the active endpoint changed. The user chooses via /model.

# 4. register `ccswitch` function in PowerShell profile
$psProfile = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $psProfile
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (-not (Test-Path $psProfile)) { New-Item -ItemType File -Force -Path $psProfile | Out-Null }

# Upsert-Function <name-pattern (regex, anchored)> <full function line>
# Re-installs must converge to the CURRENT line even if content changed (e.g. a moved
# ccswitch.ps1 path) — appending a second definition and relying on "last wins on reload"
# leaves a stale line behind permanently. So: drop any line matching the name, then append.
function Upsert-Function([string]$namePattern, [string]$line) {
  $content = Get-Content $psProfile
  $filtered = $content | Where-Object { $_ -notmatch $namePattern }
  if ($filtered.Count -ne $content.Count) {
    Set-Content $psProfile $filtered -Encoding UTF8
  }
  Add-Content $psProfile $line
}

$fnLine = 'function ccswitch { & powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\ccswitch.ps1" @args }'
if (Select-String -Path $psProfile -SimpleMatch $fnLine -Quiet) {
  Write-Host "  • ccswitch function already in $psProfile — skipped"
} else {
  Upsert-Function '^function ccswitch ' $fnLine
  Write-Host "  ✓ synced ccswitch function in $psProfile"
}

# 4b. parallel-launcher functions — one per target. Each spawns a SEPARATE Claude Code
#     instance pinned to that vendor via process env. Run N in N terminals = N vendors in parallel.
$short = @{ claude = "cc"; codex = "cx"; deepseek = "ds"; kimi = "km" }
foreach ($t in @("claude", "codex", "deepseek", "kimi")) {
  $fn = "claude-$($short[$t])"
  $line = "function $fn { & powershell -ExecutionPolicy Bypass -File `"`$env:USERPROFILE\.claude\ccswitch.ps1`" spawn $t @args }"
  if (Select-String -Path $psProfile -SimpleMatch $line -Quiet) {
    Write-Host "  • launcher $fn already in $psProfile — skipped"
  } else {
    Upsert-Function "^function $fn " $line
    Write-Host "  ✓ synced launcher $fn ($t) in $psProfile"
  }
}

Write-Host ""
Write-Host "✅ Installed. Next steps:" -ForegroundColor Green
Write-Host "   1. (if you skipped the prompt) Fill a key:  ccswitch set-key <claude|codex|deepseek|kimi>  (same 9router key for all four)"
Write-Host "   2. Reload profile:  . `$PROFILE   then run: ccswitch claude (or codex/deepseek/kimi)"
Write-Host "   3. Restart Claude Code (quit + reopen) to load the new env."
Write-Host "   4. Parallel:  open 4 terminals -> claude-cc / claude-cx / claude-ds / claude-km (all share 9router quota; force-subscription Kimi uses its own Moonshot key)"
Write-Host ""
Write-Host "Note: the health hook uses 'bash' (Git Bash / WSL). If you have neither, the hook is skipped harmlessly." -ForegroundColor DarkGray
