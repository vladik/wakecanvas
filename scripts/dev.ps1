$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Mix {
  param([Parameter(Mandatory = $true)][string[]]$MixArguments)

  & mix @MixArguments

  if ($LASTEXITCODE -ne 0) {
    throw "mix $($MixArguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Invoke-Npm {
  & npm install

  if ($LASTEXITCODE -ne 0) {
    throw "npm install failed with exit code $LASTEXITCODE"
  }
}

Push-Location (Join-Path $repositoryRoot 'experiences/living_gallery')
try {
  Invoke-Mix @('deps.get')
  Invoke-Mix @('deps.compile', 'wake_canvas_experience_sdk', '--force')
  Invoke-Mix @('compile', '--force')
  Invoke-Npm
  Invoke-Mix @('assets.setup')
  Invoke-Mix @('assets.build')
}
finally {
  Pop-Location
}

Push-Location (Join-Path $repositoryRoot 'platform')
try {
  Invoke-Mix @('deps.get')
  Invoke-Mix @('deps.compile', 'wake_canvas_experience_sdk', '--force')
  Invoke-Mix @('compile', '--force')
  Invoke-Mix @('ecto.create', '--quiet')
  Invoke-Mix @('ecto.migrate')
  Invoke-Mix @('run', 'priv/repo/seeds.exs')
  Invoke-Mix @('assets.setup')
  Invoke-Mix @('assets.build')
  Invoke-Mix @('phx.server')
}
finally {
  Pop-Location
}
