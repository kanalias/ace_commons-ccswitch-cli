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

# 2. profile template — copy ONLY if missing (never clobber a real key).
# NOTE (.ps1 parity lag): this installer wires only the `claude` profile. The deepseek profile
# is copied on macOS/Linux by setup.sh; on Windows, add it by hand (copy profiles\deepseek.json)
# then `ccswitch set-key deepseek` (same 9router key as claude). TODO: loop $Order.
$dst9 = Join-Path $Profiles "claude.json"
if (Test-Path $dst9) {
  Write-Host "  • profiles\claude.json exists — kept (edit manually or run: ccswitch set-key)"
} else {
  Copy-Item (Join-Path $Src "profiles\claude.json") $dst9 -Force
  Write-Host "  ✓ profiles\claude.json (template — fill in your key)"
}

# 2b. prompt for the router key (interactive only — never echoed, never clobbers silently)
$dst9 = Join-Path $Profiles "claude.json"
if (-not [Environment]::UserInteractive) {
  Write-Host "  • non-interactive session — skipped key prompt (edit profiles\claude.json manually)"
} else {
  $p9  = Get-Content $dst9 -Raw | ConvertFrom-Json
  $cur = $p9.ANTHROPIC_AUTH_TOKEN
  $ask = $true
  if ($cur -and $cur -notmatch '<your-9router-key>') {
    $ans = Read-Host "  • profiles\claude.json already holds a key. Overwrite? [y/N]"
    if ($ans -notmatch '^(y|yes)$') { Write-Host "    kept existing key."; $ask = $false }
  }
  if ($ask) {
    $secure = Read-Host "  ▸ Paste your router key (input hidden, Enter to skip)" -AsSecureString
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key    = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ([string]::IsNullOrEmpty($key)) {
      Write-Host "    no key entered — kept placeholder (edit profiles\claude.json later)."
    } else {
      Copy-Item $dst9 "$dst9.bak" -Force
      $p9.ANTHROPIC_AUTH_TOKEN = $key
      $p9 | ConvertTo-Json -Depth 10 | Set-Content $dst9 -Encoding UTF8
      Write-Host "  ✓ router key saved to profiles\claude.json"
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
$short = @{ claude = "cc"; deepseek = "ds" }
foreach ($t in @("claude", "deepseek")) {
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
Write-Host "   1. (if you skipped the prompt) Fill your key:  notepad `$env:USERPROFILE\.claude\profiles\claude.json"
Write-Host "   2. Reload profile:  . `$PROFILE   then run: ccswitch claude"
Write-Host "   3. Restart Claude Code (quit + reopen) to load the new env."
Write-Host "   4. Parallel:  open 3 terminals -> claude-cc / claude-cx / claude-ds (shared 9router quota)"
Write-Host ""
Write-Host "Note: the health hook uses 'bash' (Git Bash / WSL). If you have neither, the hook is skipped harmlessly." -ForegroundColor DarkGray
