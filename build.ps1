param(
    [string]$OutputDirectory,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$tocPath = Join-Path $root "LootViewer.toc"

if (-not $SkipVerify) {
    & (Join-Path $root "verify.ps1")
}

$tocText = Get-Content -LiteralPath $tocPath -Raw
if ($tocText -notmatch '(?m)^## Version:\s*(\d+\.\d+\.\d+)\s*$') {
    throw "LootViewer.toc does not contain a semantic ## Version value."
}
$version = $Matches[1]

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root "dist"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $root $OutputDirectory
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')

$buildRoot = Join-Path $root ".build"
$packageRoot = Join-Path $buildRoot "LootViewer"
$optionsSourceRoot = Join-Path $root "Options"
$optionsTocPath = Join-Path $optionsSourceRoot "LootViewer_Options.toc"
$optionsPackageRoot = Join-Path $buildRoot "LootViewer_Options"
$archivePath = Join-Path $OutputDirectory "LootViewer-$version.zip"

function Get-TocEntries {
    param([string]$Path)

    return @(
        Get-Content -LiteralPath $Path | ForEach-Object {
            $entry = $_.Trim()
            if ($entry -and -not $entry.StartsWith('#')) {
                $entry
            }
        }
    )
}

function Assert-ChildPath {
    param(
        [string]$Candidate,
        [string]$Parent
    )

    $candidatePath = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $prefix = $parentPath + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidatePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use a path outside the build root: $candidatePath"
    }
}

$tocEntries = Get-TocEntries -Path $tocPath
$optionsTocEntries = Get-TocEntries -Path $optionsTocPath
Assert-ChildPath -Candidate $packageRoot -Parent $root
Assert-ChildPath -Candidate $optionsPackageRoot -Parent $root

foreach ($stagingPath in @($packageRoot, $optionsPackageRoot)) {
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
}
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $optionsPackageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

try {
    Copy-Item -LiteralPath $tocPath -Destination (Join-Path $packageRoot "LootViewer.toc")

    foreach ($entry in $tocEntries) {
        $relativePath = $entry -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $sourcePath = Join-Path $root $relativePath
        $destinationPath = Join-Path $packageRoot $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath

        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    }

    Copy-Item -LiteralPath $optionsTocPath -Destination (Join-Path $optionsPackageRoot "LootViewer_Options.toc")
    foreach ($entry in $optionsTocEntries) {
        $relativePath = $entry -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $sourcePath = Join-Path $optionsSourceRoot $relativePath
        $destinationPath = Join-Path $optionsPackageRoot $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    }

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open(
        $archivePath,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        foreach ($stagingPath in @($packageRoot, $optionsPackageRoot)) {
            Get-ChildItem -LiteralPath $stagingPath -File -Recurse | ForEach-Object {
                $relativePath = $_.FullName.Substring($buildRoot.Length).TrimStart([char[]]'\/').Replace('\', '/')
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive,
                    $_.FullName,
                    $relativePath,
                    [System.IO.Compression.CompressionLevel]::Optimal
                ) | Out-Null
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $actualEntries = @(
            $archive.Entries |
                Where-Object { -not $_.FullName.EndsWith('/') } |
                ForEach-Object { $_.FullName.Replace('\', '/') } |
                Sort-Object
        )
    }
    finally {
        $archive.Dispose()
    }

    $expectedEntries = @(
        "LootViewer/LootViewer.toc"
        $tocEntries | ForEach-Object { "LootViewer/$($_.Replace('\', '/'))" }
        "LootViewer_Options/LootViewer_Options.toc"
        $optionsTocEntries | ForEach-Object { "LootViewer_Options/$($_.Replace('\', '/'))" }
    ) | Sort-Object

    $differences = @(Compare-Object -ReferenceObject $expectedEntries -DifferenceObject $actualEntries)
    if ($differences.Count -gt 0) {
        $detail = ($differences | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
        throw "Release archive contents do not match the TOC: $detail"
    }
}
finally {
    foreach ($stagingPath in @($packageRoot, $optionsPackageRoot)) {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
    }
    if ((Test-Path -LiteralPath $buildRoot) -and -not (Get-ChildItem -LiteralPath $buildRoot -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $buildRoot -Force
    }
}

Write-Host "LootViewer package created: $archivePath" -ForegroundColor Green
