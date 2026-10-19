[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'dist'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$version = (Select-String -Path (Join-Path $repoRoot 'platform\mix.exs') -Pattern 'version: "([^"]+)"').Matches[0].Groups[1].Value
$archivePath = Join-Path $OutputDirectory "wakecanvas-$version-windows-x64.zip"
$stagingRoot = Join-Path $repoRoot ('.tmp\windows-release-' + [Guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $stagingRoot 'WakeCanvas'

if ((Test-Path -LiteralPath $archivePath) -and -not $Force) {
    throw "Release archive already exists: $archivePath (use -Force to replace it)"
}

function Invoke-Mix {
    param([string]$WorkingDirectory, [string[]]$Arguments)
    Push-Location $WorkingDirectory
    try {
        & mix @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "mix $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

try {
    $env:MIX_ENV = 'prod'

    $livingGallery = Join-Path $repoRoot 'experiences\living_gallery'
    Push-Location $livingGallery
    try {
        & npm ci --ignore-scripts
        if ($LASTEXITCODE -ne 0) {
            throw "npm ci failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
    Invoke-Mix $livingGallery @('deps.get', '--only', 'prod')
    Invoke-Mix $livingGallery @('assets.setup')
    Invoke-Mix $livingGallery @('assets.deploy')

    $platform = Join-Path $repoRoot 'platform'
    Invoke-Mix $platform @('deps.get', '--only', 'prod')
    Invoke-Mix $platform @('assets.setup')
    Invoke-Mix $platform @('assets.deploy')
    Invoke-Mix $platform @('release', 'wake_canvas', '--overwrite')

    New-Item -ItemType Directory -Force -Path $bundleRoot | Out-Null
    $releaseRoot = Join-Path $platform '_build\prod\rel\wake_canvas'
    Copy-Item -Path (Join-Path $releaseRoot '*') -Destination $bundleRoot -Recurse -Force
    Copy-Item -Path (Join-Path $repoRoot 'packaging\windows\*') -Destination $bundleRoot -Force

    $packagesRoot = Join-Path $bundleRoot 'packages'
    New-Item -ItemType Directory -Force -Path $packagesRoot | Out-Null
    $packagePath = Join-Path $packagesRoot 'living-gallery-0.1.0.wakecanvas'
    Invoke-Mix $livingGallery @('wakecanvas.package', '--output', $packagePath)
    Invoke-Mix $platform @('wakecanvas.package.verify', $packagePath)

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -Path $bundleRoot -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    Write-Host "Built $archivePath"
    Write-Host "SHA-256 $hash"
} finally {
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp'))
    $resolvedStage = [IO.Path]::GetFullPath($stagingRoot)
    if ($resolvedStage.StartsWith($expectedParent + [IO.Path]::DirectorySeparatorChar) -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
