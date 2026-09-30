param(
    [Parameter(Mandatory=$true)][string]$PayloadDirectory,
    [Parameter(Mandatory=$true)][string]$Launcher,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$Python
)
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path $PSScriptRoot -Parent
& $Python -B (Join-Path $PSScriptRoot 'check-publication.py')
if ($LASTEXITCODE -ne 0) { throw 'Source publication gate failed.' }
if (Test-Path -LiteralPath $Destination) { throw 'Candidate destination exists; refusing overwrite.' }
$pins=[regex]::Matches([IO.File]::ReadAllText((Join-Path $sourceRoot 'installer/verify-payload.sh')), '(?m)^([0-9a-f]{64}) ([^\r\n ]+)$')
if ($pins.Count -ne 7) { throw 'Expected exactly seven pinned components.' }
foreach ($pin in $pins) {
    $file=Join-Path $PayloadDirectory $pin.Groups[2].Value
    if ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Payload links are not accepted.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne $pin.Groups[1].Value) { throw "Incorrect payload: $file" }
}
if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) { throw 'Compiled launcher is missing.' }
$null=New-Item -ItemType Directory -Path $Destination
$kit=Join-Path (Resolve-Path $Destination).Path 'Thor-Forever'
$null=New-Item -ItemType Directory -Path $kit
foreach ($name in @('installer','tuning.conf','docs','notices','LICENSE','LICENSING.md','START-HERE.md','Install-Thor-Forever.cmd')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination $kit -Recurse
}
$null=New-Item -ItemType Directory -Path (Join-Path $kit 'payload')
foreach ($pin in $pins) { Copy-Item -LiteralPath (Join-Path $PayloadDirectory $pin.Groups[2].Value) -Destination (Join-Path $kit 'payload') }
Copy-Item -LiteralPath $Launcher -Destination (Join-Path $kit 'Thor-Forever.exe')
# Packaging normalization only: scripts use Android LF and Windows CMD CRLF.
foreach ($file in Get-ChildItem -LiteralPath $kit -Recurse -File) {
    if ($file.Extension -in @('.sh','.cmd')) {
        $text=[IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n")
        if ($file.Extension -eq '.cmd') { $text=$text.Replace("`n","`r`n") }
        [IO.File]::WriteAllText($file.FullName,$text,[Text.UTF8Encoding]::new($false))
    }
}
$manifest=@('PRIVATE RELEASE CANDIDATE - NOT APPROVED FOR PUBLIC BINARY DISTRIBUTION')
foreach ($file in Get-ChildItem -LiteralPath $kit -Recurse -File | Sort-Object FullName) {
    $relative=$file.FullName.Substring($kit.Length+1).Replace('\','/')
    $manifest+=((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()+'  '+$relative)
}
[IO.File]::WriteAllLines((Join-Path $kit 'CANDIDATE-SHA256.txt'),$manifest,[Text.UTF8Encoding]::new($false))
Write-Output "Private candidate prepared at $kit. No upload performed."
