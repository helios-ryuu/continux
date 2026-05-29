# Usage:
#   .\compile.ps1 .\paper\main_vi.tex
# Builds the PDF next to the .tex file and moves LaTeX artifacts to <basename>_artifacts.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TexPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$artifactExtensions = @(
    '.aux',
    '.bbl',
    '.bcf',
    '.bcf-SAVE-ERROR',
    '.blg',
    '.fdb_latexmk',
    '.fls',
    '.log',
    '.run.xml',
    '.synctex.gz',
    '.toc',
    '.lof',
    '.lot',
    '.out'
)

function Stop-WithMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    [Console]::Error.WriteLine($Message)
    exit $ExitCode
}

function Move-LatexArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TexDirectory,

        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$Extensions
    )

    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null

    foreach ($extension in $Extensions) {
        $artifactPath = Join-Path $TexDirectory "$BaseName$extension"

        if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
            Move-Item -LiteralPath $artifactPath -Destination $DestinationDirectory -Force
        }
    }
}

try {
    $resolvedTexPath = (Resolve-Path -LiteralPath $TexPath -ErrorAction Stop).ProviderPath
} catch {
    Stop-WithMessage -Message "TeX file not found: $TexPath" -ExitCode 1
}

if (-not (Test-Path -LiteralPath $resolvedTexPath -PathType Leaf)) {
    Stop-WithMessage -Message "Path is not a file: $resolvedTexPath" -ExitCode 1
}

if ([System.IO.Path]::GetExtension($resolvedTexPath) -ine '.tex') {
    Stop-WithMessage -Message "Input must be a .tex file: $resolvedTexPath" -ExitCode 1
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Stop-WithMessage -Message "Docker is required but was not found in PATH." -ExitCode 1
}

$texDirectory = Split-Path -Parent $resolvedTexPath
$texFileName = Split-Path -Leaf $resolvedTexPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texFileName)
$artifactDirectory = Join-Path $texDirectory "${baseName}_artifacts"
$pdfPath = Join-Path $texDirectory "$baseName.pdf"

$dockerArgs = @(
    'run',
    '--rm',
    '-v',
    "${texDirectory}:/workdir",
    '-w',
    '/workdir',
    'texlive/texlive',
    'latexmk',
    '-pdf',
    '-interaction=nonstopmode',
    '-halt-on-error',
    '-file-line-error',
    $texFileName
)

& docker @dockerArgs
$buildExitCode = $LASTEXITCODE

try {
    Move-LatexArtifacts `
        -TexDirectory $texDirectory `
        -BaseName $baseName `
        -DestinationDirectory $artifactDirectory `
        -Extensions $artifactExtensions
} catch {
    Stop-WithMessage -Message "Failed to move LaTeX artifacts: $($_.Exception.Message)" -ExitCode 1
}

if ($buildExitCode -ne 0) {
    Stop-WithMessage -Message "LaTeX build failed with exit code $buildExitCode. Artifacts are in: $artifactDirectory" -ExitCode $buildExitCode
}

if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
    Stop-WithMessage -Message "LaTeX build finished but PDF was not found: $pdfPath" -ExitCode 1
}

Write-Host "PDF: $pdfPath"
Write-Host "Artifacts: $artifactDirectory"
exit 0
