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

foreach ($project in $projects) {
  $projectPath = Join-Path $repositoryRoot $project
  Push-Location $projectPath

  try {
    Invoke-Mix @('deps.get')
    Invoke-Mix @('format', '--check-formatted')
    Invoke-Mix @('compile', '--warnings-as-errors')
    Invoke-Mix @('test')
  }
  finally {
    Pop-Location
  }
}
