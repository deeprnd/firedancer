param(
    [string]$AptPackages = '',
    [switch]$InstallGnuMake,
    [switch]$InstallGitleaks,
    [string]$GitleaksVersion = '8.30.1',
    [switch]$InstallKcov
)

$ErrorActionPreference = 'Stop'

function Install-ChocoPackage {
    param([string]$Name)
    choco install $Name -y --no-progress
}

function Add-ToGitHubPath {
    param([string]$Value)
    if (-not $env:GITHUB_PATH) {
        return
    }
    Add-Content -Path $env:GITHUB_PATH -Value $Value
}

function Get-GitleaksAssetName {
    param([string]$Version)

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        return "gitleaks_${Version}_windows_arm64.zip"
    }
    return "gitleaks_${Version}_windows_x64.zip"
}

if ($AptPackages) {
    throw "setup-public-gh-runner: apt-packages is Linux-only. Windows jobs must use explicit native bootstrap steps instead of apt package names: '$AptPackages'"
}

if ($InstallKcov) {
    throw 'setup-public-gh-runner: kcov is not supported on Windows runners'
}

if ($InstallGnuMake) {
    Install-ChocoPackage -Name 'make'
}

Install-ChocoPackage -Name 'strawberryperl'

$bootstrapPaths = @(
    'C:\ProgramData\chocolatey\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\usr\bin',
    'C:\Program Files\CMake\bin',
    'C:\Program Files\LLVM\bin',
    'C:\Strawberry\perl\bin',
    'C:\Strawberry\c\bin'
)
foreach ($pathEntry in $bootstrapPaths) {
    if (Test-Path $pathEntry) {
        Add-ToGitHubPath -Value $pathEntry
    }
}

if ($InstallGitleaks) {
    $asset = Get-GitleaksAssetName -Version $GitleaksVersion
    $root = Join-Path $env:RUNNER_TEMP 'gitleaks'
    $zipPath = Join-Path $root 'gitleaks.zip'

    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Invoke-WebRequest -Uri "https://github.com/gitleaks/gitleaks/releases/download/v${GitleaksVersion}/${asset}" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $root -Force
    Add-ToGitHubPath -Value $root
}
