param(
  [Parameter(Mandatory = $true)][string]$ExperiencePath,
  [string]$App,
  [string]$EntryModule
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$experienceRoot = (Resolve-Path -LiteralPath $ExperiencePath).Path
$manifestPath = Join-Path $experienceRoot 'wakecanvas-experience.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Experience manifest was not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if (-not $App) { $App = [string]$manifest.otpApplication }
if (-not $EntryModule) { $EntryModule = [string]$manifest.entryModule }

if ($App -ne [string]$manifest.otpApplication) {
  throw "App '$App' does not match manifest otpApplication '$($manifest.otpApplication)'."
}

if ($EntryModule -ne [string]$manifest.entryModule) {
  throw "EntryModule '$EntryModule' does not match manifest entryModule '$($manifest.entryModule)'."
}

if ($App -notmatch '^[a-z][a-z0-9_]*$') {
  throw 'App must be a valid lower-case OTP application name.'
}

if ($EntryModule -notmatch '^[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)*$') {
  throw 'EntryModule must be a fully qualified Elixir module name.'
}

Push-Location $experienceRoot
try {
  & mix deps.get
  if ($LASTEXITCODE -ne 0) { throw 'mix deps.get failed' }

  & mix help assets.build *> $null
  if ($LASTEXITCODE -eq 0) {
    & mix assets.build
    if ($LASTEXITCODE -ne 0) { throw 'mix assets.build failed' }
  }

  & mix compile --force
  if ($LASTEXITCODE -ne 0) { throw 'mix compile failed' }
}
finally {
  Pop-Location
}

$ebin = Join-Path $experienceRoot "_build/dev/lib/$App/ebin"

if (-not (Test-Path -LiteralPath $ebin -PathType Container)) {
  throw "Compiled Experience ebin directory was not found: $ebin"
}

$env:WAKECANVAS_DEV_EXPERIENCE_EBIN = $ebin
$env:WAKECANVAS_DEV_EXPERIENCE_ENTRY_MODULE = $EntryModule

Write-Host "Starting WakeCanvas with $($manifest.experienceId) from $experienceRoot"
Write-Host 'Restart this command after recompiling Experience server modules or browser assets.'

& (Join-Path $repositoryRoot 'scripts/dev.ps1')
