$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$projects = @(
  'experiences/sdk',
  'experiences/living_gallery',
  'platform'
)

function Invoke-Mix {
  param([Parameter(Mandatory = $true)][string[]]$MixArguments)

  & mix @MixArguments

  if ($LASTEXITCODE -ne 0) {
    throw "mix $($MixArguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Invoke-Npm {
  param([Parameter(Mandatory = $true)][string[]]$NpmArguments)

  & npm @NpmArguments

  if ($LASTEXITCODE -ne 0) {
    throw "npm $($NpmArguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

foreach ($project in $projects) {
  $projectPath = Join-Path $repositoryRoot $project
  Push-Location $projectPath

  try {
    Invoke-Mix @('deps.get')
    if ($project -eq 'experiences/living_gallery') {
      Invoke-Npm @('ci', '--ignore-scripts')
      Invoke-Mix @('assets.build')
    }
    Invoke-Mix @('format', '--check-formatted')
    Invoke-Mix @('compile', '--warnings-as-errors')
    Invoke-Mix @('test')
  }
  finally {
    Pop-Location
  }
}

Push-Location (Join-Path $repositoryRoot 'packages/media')
try {
  Invoke-Npm @('test')
}
finally {
  Pop-Location
}
