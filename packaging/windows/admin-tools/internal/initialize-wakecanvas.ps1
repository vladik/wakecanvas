$ErrorActionPreference = 'Stop'
$ManagementCode = ''
$OpenManagement = $false
$NonInteractive = $false
$Force = $false

for ($index = 0; $index -lt $args.Count; $index++) {
    switch ($args[$index]) {
        '--management-code' {
            if ($index + 1 -ge $args.Count) { throw '--management-code requires a value.' }
            $index++
            $ManagementCode = $args[$index]
        }
        '--open-management' { $OpenManagement = $true }
        '--non-interactive' { $NonInteractive = $true }
        '--force' { $Force = $true }
        '--help' {
            Write-Host 'Usage: initialize-wakecanvas.cmd [--management-code 123456 | --open-management] [--non-interactive] [--force]'
            exit 0
        }
        default { throw "Unknown option: $($args[$index])" }
    }
}

if ($ManagementCode -and $ManagementCode -notmatch '^\d{6}$') {
    throw '--management-code must contain exactly six digits.'
}

$installRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$dataRoot = Join-Path $installRoot 'data'
$configRoot = Join-Path $dataRoot 'config'
$codePath = Join-Path $configRoot 'management_code'

New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'instances') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'packages') | Out-Null

if ((Test-Path -LiteralPath $codePath) -and -not $Force) {
    Write-Host "WakeCanvas is already initialized at $dataRoot"
    Write-Host 'Use -Force to replace the management-code configuration.'
    exit 0
}

if ($OpenManagement) {
    $selectedCode = ''
} elseif ($ManagementCode) {
    $selectedCode = $ManagementCode
} elseif (-not $NonInteractive) {
    do {
        $selectedCode = Read-Host 'Choose a 6-digit management code'
    } until ($selectedCode -match '^\d{6}$')
} else {
    $bytes = New-Object byte[] 4
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    $number = [BitConverter]::ToUInt32($bytes, 0) % 1000000
    $selectedCode = $number.ToString('D6')
}

$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($codePath, $selectedCode + [Environment]::NewLine, $utf8WithoutBom)

Write-Host "WakeCanvas data directory: $dataRoot"
if ($selectedCode) {
    Write-Host "Management code: $selectedCode"
    Write-Host 'Keep this code available to workshop operators.'
} else {
    Write-Warning 'Management views are open because no code was configured.'
}
