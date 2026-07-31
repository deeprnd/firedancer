param()

$ErrorActionPreference = 'Stop'

if (Get-Command zstd -ErrorAction SilentlyContinue) {
    Write-Host 'zstd already installed'
    exit 0
}

choco install zstandard -y --no-progress
