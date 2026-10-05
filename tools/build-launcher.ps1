param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/launcher.c'
if (Test-Path -LiteralPath $OutputFile) { throw 'Output exists; choose a new build path.' }
& $Compiler -O2 -Wall -Wextra -Werror -municode -mwindows $source -o $OutputFile -luser32 -lgdi32
if ($LASTEXITCODE -ne 0) { throw 'Windows ARM64 launcher compilation failed.' }
Get-FileHash -Algorithm SHA256 -LiteralPath $OutputFile
