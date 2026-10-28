<#
.SYNOPSIS
  Install the claude-brain skills into ~/.claude/skills on Windows.

.DESCRIPTION
  PowerShell twin of install.sh. Copies skills/windows/* into %USERPROFILE%\.claude\skills and fills:
    {{BRAIN_ABS}}  absolute brain path with forward slashes (C:/Users/<you>/claude-brain)
    ~/claude-brain rewritten only when -BrainDir is given
  Existing skills are backed up to <name>.bak-<timestamp>, never deleted.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
  .\install.ps1 -BrainDir "$env:USERPROFILE\kb\brain" -Yes
  .\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$BrainDir = "",
  [string]$Os = "windows",
  [switch]$Yes,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Skills = @("claude-brain-builder", "brain-architect", "brain-recall", "brain-transcriber")
$Dest   = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME ".claude\skills" }

function Fail([string]$Message) { Write-Error "install: $Message"; exit 1 }

function Confirm-Step([string]$Question) {
  if ($Yes) { return $true }
  $reply = Read-Host "$Question [y/N]"
  return $reply -match "^[yY]"
}

function Resolve-Inputs {
  if (-not $script:BrainDir) { $script:BrainDir = Join-Path $HOME "claude-brain" }
  if ($script:BrainDir.StartsWith("~")) { $script:BrainDir = $HOME + $script:BrainDir.Substring(1) }
  $script:BrainDir = [System.IO.Path]::GetFullPath($script:BrainDir).TrimEnd("\", "/")
}

# Brain path as written in the skills: ~/... when under the home folder, forward slashes always.
function Get-BrainDisplay {
  $homeFull = [System.IO.Path]::GetFullPath($HOME).TrimEnd("\")
  if ($script:BrainDir.StartsWith($homeFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    return "~" + ($script:BrainDir.Substring($homeFull.Length) -replace "\\", "/")
  }
  return ($script:BrainDir -replace "\\", "/")
}

function Write-Rendered([string]$Source, [string]$Target) {
  $text = [System.IO.File]::ReadAllText($Source)
  $text = $text.Replace("{{BRAIN_ABS}}", ($script:BrainDir -replace "\\", "/"))
  $text = $text.Replace("~/claude-brain", (Get-BrainDisplay))
  if ($text -match "\{\{[A-Z_]+\}\}") { Fail "unfilled placeholder left in $Target" }
  [System.IO.File]::WriteAllText($Target, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Test-SameTree([string]$A, [string]$B) {
  $left  = Get-ChildItem -Recurse -File $A | ForEach-Object { $_.FullName.Substring($A.Length) + ":" + (Get-FileHash $_.FullName).Hash }
  $right = Get-ChildItem -Recurse -File $B | ForEach-Object { $_.FullName.Substring($B.Length) + ":" + (Get-FileHash $_.FullName).Hash }
  return -not (Compare-Object @($left) @($right))
}

function Install-Skill([string]$Skill, [string]$Src, [string]$Work) {
  $from   = Join-Path $Src $Skill
  $staged = Join-Path $Work $Skill
  $target = Join-Path $Dest $Skill
  if (-not (Test-Path (Join-Path $from "SKILL.md"))) { Fail "missing $from\SKILL.md" }
  Copy-Item -Recurse $from $staged
  Write-Rendered (Join-Path $from "SKILL.md") (Join-Path $staged "SKILL.md")

  if (Test-Path $target) {
    if (Test-SameTree $staged $target) { Write-Host "  unchanged  $Skill"; return }
    if ($DryRun) { Write-Host "  would replace  $Skill (backup kept)"; return }
    if (-not (Confirm-Step "  $target exists. Replace it (a backup is kept)?")) { Write-Host "  skipped    $Skill"; return }
    $backup = "$target.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Move-Item $target $backup
    Write-Host "  backed up  $Skill"
  } elseif ($DryRun) {
    Write-Host "  would install  $Skill"; return
  }
  Move-Item $staged $target
  Write-Host "  installed  $Skill"
}

if ($Os -notin @("macos", "linux", "windows")) { Fail "-Os must be macos, linux or windows" }
$Src = Join-Path $Repo "skills\$Os"
if (-not (Test-Path $Src)) { Fail "missing $Src (run this from the repo)" }
Resolve-Inputs

Write-Host "Platform:   $Os"
Write-Host "Brain dir:  $BrainDir"
Write-Host "Skills to:  $Dest"
if ($DryRun) { Write-Host "(dry run: nothing will be changed)" } else { New-Item -ItemType Directory -Force $Dest | Out-Null }

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-brain-install-" + [guid]::NewGuid())
New-Item -ItemType Directory $Work | Out-Null
try {
  foreach ($s in $Skills) { Install-Skill $s $Src $Work }
} finally {
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Open Claude Code and say: `"Build my claude brain.`""
Write-Host "Re-run .\install.ps1 after git pull to pick up skill updates."
