<#
.SYNOPSIS
  ccswitch — swap Claude Code auth profile (Windows / PowerShell port).

.DESCRIPTION
  Only replaces the `env` block in %USERPROFILE%\.claude\settings.json; leaves everything else intact.

  Targets (priority order):
    claude        (DEFAULT)  https://9router.acegalaxy.co/v1  cc/* claude   — Claude via 9router
    deepseek                 (same base)                      ds/* deepseek — DeepSeek via 9router
    subscription             (no env block)                   — Claude Code OAuth login (safe-harbor)

  claude / deepseek share the SAME base URL (9router); they differ only in the model prefix
  (cc/ vs ds/) and SHARE ONE 9router key (fill the same token into both). One router → one fallback: subscription.
  (codex/gpt via cx/* removed: 9router returns raw OpenAI wire format for cx/*, unparseable by Claude Code.)

  `subscription` is NOT a profile file: it removes the env block so Claude Code falls back to its
  own OAuth subscription login. No key, never probed — the guaranteed terminal.
  Aliases (backward compat): original->subscription, direct->subscription, clear==subscription.

.EXAMPLE
  ccswitch                # show current target + router-family health + subscription note
  ccswitch claude         # Claude via 9router (default)
  ccswitch deepseek       # DeepSeek via 9router (ds/* models)
  ccswitch subscription   # remove env block -> Claude Code OAuth subscription
  ccswitch spawn <target> # launch a separate instance pinned to <target> via process env
                          #   (settings.json untouched). N terminals + N targets = N vendors in parallel.
  ccswitch check          # probe router health (all profiles)
  ccswitch fallback       # active router profile if healthy, else fall back to subscription
  ccswitch set-key [p]    # prompt (hidden) for a new key for profile p (default claude), then apply
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Command = "status",
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings  = Join-Path $ClaudeDir "settings.json"
$Profiles  = Join-Path $ClaudeDir "profiles"
$Order     = @("claude", "deepseek")   # profile files (share one 9router key); subscription is env-clear

function Die($msg) { Write-Host "❌ $msg" -ForegroundColor Red; exit 1 }

function Get-Canon($name) {
  switch ($name) {
    "original" { "subscription" }
    "direct"   { "subscription" }
    "clear"    { "subscription" }
    default    { $name }
  }
}

# probe a profile's base url /models endpoint; returns http status code (string)
function Test-Profile($name) {
  $prof = Join-Path $Profiles "$name.json"
  if (-not (Test-Path $prof)) { return "000" }
  try {
    $p = Get-Content $prof -Raw | ConvertFrom-Json
  } catch { return "000" }

  $base = $p.ANTHROPIC_BASE_URL
  if (-not $base) { return "000" }   # subscription/OAuth has no URL to probe
  $auth = $p.ANTHROPIC_AUTH_TOKEN
  $url  = ($base.TrimEnd("/")) + "/models"

  $headers = @{}
  if ($auth) { $headers["Authorization"] = "Bearer $auth" }
  try {
    # NOTE: no -SkipHttpErrorCheck (PS7-only). On PS 5.1 non-2xx throws; catch reads the status.
    $resp = Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 4 `
              -UseBasicParsing
    return [string]$resp.StatusCode
  } catch {
    if ($_.Exception.Response) { return [string][int]$_.Exception.Response.StatusCode }
    return "000"
  }
}

# claude / deepseek share one base URL (9router) → tell them apart by model prefix.
function Get-Tag($base, $model) {
  if (-not $base) { return "subscription" }
  if ($base -like "*9router.acegalaxy.co*") {
    switch -Wildcard ($model) {
      "ds/*"  { return "deepseek" }
      "cc/*"  { return "claude" }
      default { return "claude" }
    }
  }
  return "custom"
}

function Show-Current {
  $s = Get-Content $Settings -Raw | ConvertFrom-Json
  $base  = $s.env.ANTHROPIC_BASE_URL
  $model = $s.env.ANTHROPIC_DEFAULT_OPUS_MODEL
  if ($base) {
    $tag = Get-Tag $base $model
    Write-Host "current: $tag ($base$(if ($model) { ", $model" }))"
  } else {
    Write-Host "current: subscription (no env block → OAuth login)"
  }
}

function Show-Health {
  foreach ($p in $Order) {
    $c = Test-Profile $p
    $tag = if ($c -eq "200") { "OK" } else { "DOWN" }
    Write-Host "  $p`: $c $tag"
  }
  Write-Host "  subscription: OAuth login (safe-harbor, no probe)"
}

# remove the env block -> Claude Code reverts to its own OAuth subscription login.
function Clear-Env {
  if (-not (Test-Path $Settings)) { Die "settings not found: $Settings" }
  Copy-Item $Settings "$Settings.bak" -Force
  $s = Get-Content $Settings -Raw | ConvertFrom-Json
  if ($s.PSObject.Properties.Name -contains "env") { $s.PSObject.Properties.Remove("env") }
  $s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
  Write-Host "✅ switched to 'subscription' — removed env block (backup: $Settings.bak)." -ForegroundColor Green
  Write-Host "   Claude Code will use its OAuth subscription login (run 'claude' + login if needed)."
  Write-Host "↻ restart Claude Code (quit + reopen) to load new env."
}

function Set-ProfileEnv($rawName) {
  $name = Get-Canon $rawName
  # subscription is not a profile file — it is the absence of an env block.
  if ($name -eq "subscription") { Clear-Env; return }
  $prof = Join-Path $Profiles "$name.json"
  if (-not (Test-Path $prof)) { Die "profile not found: $prof" }
  if (-not (Test-Path $Settings)) { Die "settings not found: $Settings" }

  try {
    $profObj = Get-Content $prof -Raw | ConvertFrom-Json
  } catch { Die "profile $prof is not valid JSON" }

  Copy-Item $Settings "$Settings.bak" -Force
  $s = Get-Content $Settings -Raw | ConvertFrom-Json
  # PS 5.1: cannot assign to a property that does not exist yet -> use Add-Member (-Force overwrites).
  $s | Add-Member -NotePropertyName env -NotePropertyValue $profObj -Force
  # depth 10 preserves nested hooks/permissions objects
  $s | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8

  Write-Host "✅ switched to '$name' profile (backup: $Settings.bak)" -ForegroundColor Green
  Write-Host "↻ restart Claude Code (quit + reopen) to load new env."
}

# set-key [profile] — prompt (hidden) for a new router key, write it into the profile, then apply.
function Set-ProfileKey($rawName) {
  $name = Get-Canon $rawName
  if ($name -eq "subscription") {
    Die "subscription uses Claude Code's OAuth login — no key to set. Run: ccswitch subscription, then 'claude' + login."
  }
  $prof = Join-Path $Profiles "$name.json"
  if (-not (Test-Path $prof)) { Die "profile not found: $prof (run setup first)" }
  try { $p = Get-Content $prof -Raw | ConvertFrom-Json } catch { Die "profile $prof is not valid JSON" }

  $field = "ANTHROPIC_AUTH_TOKEN"

  $secure = Read-Host "▸ Paste new key for '$name' → $field (input hidden)" -AsSecureString
  $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $key    = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  if ([string]::IsNullOrEmpty($key)) { Die "no key entered — profile unchanged." }

  Copy-Item $prof "$prof.bak" -Force
  $p | Add-Member -NotePropertyName $field -NotePropertyValue $key -Force
  $p | ConvertTo-Json -Depth 10 | Set-Content $prof -Encoding UTF8
  $key = $null
  Write-Host "✅ key updated in profiles\$name.json (backup: $prof.bak)" -ForegroundColor Green
  Set-ProfileEnv $name
}

# spawn <target> [claude-args…] — launch a SEPARATE Claude Code instance pinned to <target> via
# PROCESS ENV, leaving settings.json untouched. Open N terminals + spawn N targets = N vendors in
# parallel (a single instance reads one env → one model). subscription is env-clear → rejected.
# NOTE: same 9router account across targets = shared quota.
function Spawn-Target($rawName, $childArgs) {
  $name = Get-Canon $rawName
  if ($name -eq "subscription") {
    Die "spawn needs a real router target (claude|deepseek). subscription is env-clear — run: ccswitch subscription, then plain 'claude'."
  }
  $prof = Join-Path $Profiles "$name.json"
  if (-not (Test-Path $prof)) { Die "profile not found: $prof (run setup first)" }
  try { $profObj = Get-Content $prof -Raw | ConvertFrom-Json } catch { Die "profile $prof is not valid JSON" }

  $c = Test-Profile $name
  if ($c -ne "200") { Write-Host "⚠️  '$name' health=$c (not 200) — spawning anyway, may be down" -ForegroundColor Yellow }

  # set every profile field into this process's env, then invoke claude (inherits env).
  foreach ($p in $profObj.PSObject.Properties) {
    Set-Item -Path ("Env:" + $p.Name) -Value $p.Value
  }
  $Host.UI.RawUI.WindowTitle = "claude:$name"

  Write-Host "▶ spawning claude pinned to '$name' (process env only — settings.json untouched)"
  & claude @childArgs
}

switch ($Command) {
  { $_ -in @("claude", "deepseek") } {
    # both route through 9router (differ only by model prefix) and share one token.
    $c = Test-Profile $Command
    if ($c -ne "200") { Write-Host "⚠️  '$Command' health=$c (not 200) — switching anyway, may be down" -ForegroundColor Yellow }
    Set-ProfileEnv $Command
  }
  { $_ -in @("subscription", "original", "direct", "clear") } {
    # all resolve to subscription (env-clear -> Claude Code OAuth login)
    Set-ProfileEnv "subscription"
  }
  "check" { Show-Health }
  "fallback" {
    # Keep the currently-active router profile if healthy (don't force claude when the user is on
    # deepseek). Resolve active target from settings.json's model prefix; default claude.
    # `subscription` is the guaranteed SAFE-HARBOR terminal — env-clear OAuth, always reachable.
    $s = Get-Content $Settings -Raw | ConvertFrom-Json
    $t = switch -Wildcard ($s.env.ANTHROPIC_DEFAULT_OPUS_MODEL) {
      "ds/*"  { "deepseek" }
      "cc/*"  { "claude" }
      default { "claude" }
    }
    $c = Test-Profile $t
    if ($c -eq "200") { Write-Host "→ router healthy: $t"; Set-ProfileEnv $t; exit 0 }
    Write-Host "  $t down ($c) → safe-harbor: subscription (OAuth)"
    Set-ProfileEnv "subscription"
  }
  "spawn" {
    # launch a separate instance pinned to target via process env (settings.json untouched);
    # forward remaining args to claude. Open multiple terminals to run vendors in parallel.
    $target = if ($Rest.Count -ge 1) { $Rest[0] } else { "claude" }
    $childArgs = if ($Rest.Count -ge 2) { $Rest[1..($Rest.Count - 1)] } else { @() }
    Spawn-Target $target $childArgs
  }
  "set-key" {
    $prof = if ($Rest.Count -ge 1) { $Rest[0] } else { "claude" }
    Set-ProfileKey $prof
  }
  { $_ -in @("status", "") } {
    Show-Current
    Show-Health
    $names = (Get-ChildItem $Profiles -Filter *.json | ForEach-Object { $_.BaseName }) -join " "
    Write-Host "profiles: $names"
  }
  { $_ -in @("help", "--help", "-h") } {
    @"
ccswitch — swap Claude Code auth (edits only the ``env`` block in ~/.claude/settings.json)

USAGE
  ccswitch [command]

TARGETS (switch-in-place; RESTART Claude Code after — env loads at launch)
  claude              Claude via 9router          (cc/* models)   ⭐ default
  deepseek            DeepSeek via 9router         (ds/* models)
  subscription        remove env block → Claude Code OAuth login  (safe-harbor, no key)
                      aliases: original | direct | clear

  claude + deepseek share ONE 9router base URL AND ONE token
  (fill the same key into both profiles). Router down → both down → subscription.

COMMANDS
  status  (default)   show active target (by model prefix) + health + subscription
  check               probe health of every router profile + verify subscription
  fallback            keep active router if healthy, else drop to subscription
  spawn <target> [..] launch a SEPARATE pinned instance (settings.json untouched)
  set-key [profile]   paste a key (hidden) into a profile, then apply  (default: claude)
  help | -h           this help

KEYS
  ccswitch set-key claude       # then: set-key deepseek with the SAME token
  profiles live at ~/.claude/profiles/*.json  (local, never committed)
"@ | Write-Host
    exit 0
  }
  default { Die "usage: ccswitch [claude|deepseek|subscription|spawn <target>|check|fallback|set-key [profile]|clear|status|help]" }
}
