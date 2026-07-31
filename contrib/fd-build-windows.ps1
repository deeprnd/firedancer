param(
    [string]$Arch = '',
    [string]$Compiler = 'clang'
)

$ErrorActionPreference = 'Stop'

if (-not $Arch) {
    $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }
}

bash contrib/fd-build-windows.sh $Arch $Compiler
