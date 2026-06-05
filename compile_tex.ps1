# Cú pháp:
#   .\compile_tex.ps1 .\paper\main_vi.tex
# Build PDF cạnh file .tex và chuyển artifact LaTeX vào <basename>_artifacts.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TexPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dockerImage = 'texlive/texlive:latest'

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
    '.xdv',
    '.toc',
    '.lof',
    '.lot',
    '.out'
)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Step', 'Success', 'Warning')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $prefix = switch ($Level) {
        'Info' { '[INFO]' }
        'Step' { '[..]' }
        'Success' { '[OK]' }
        'Warning' { '[WARN]' }
    }

    $color = switch ($Level) {
        'Info' { 'Gray' }
        'Step' { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Stop-WithMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    [Console]::Error.WriteLine("[ERROR] $Message")
    exit $ExitCode
}

function Test-DockerImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Image
    )

    try {
        & docker image inspect $Image *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Assert-DockerDaemon {
    Write-Log -Level Step -Message 'Kiểm tra Docker daemon'

    try {
        $dockerInfoOutput = & docker info --format '{{.ServerVersion}}' 2>&1
        $dockerInfoExitCode = $LASTEXITCODE
    } catch {
        Stop-WithMessage -Message "Không truy cập được Docker daemon: $($_.Exception.Message)" -ExitCode 1
    }

    if ($dockerInfoExitCode -ne 0) {
        $detail = ($dockerInfoOutput | Out-String).Trim()

        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "docker info trả exit code $dockerInfoExitCode."
        }

        Stop-WithMessage -Message "Không truy cập được Docker daemon. $detail" -ExitCode $dockerInfoExitCode
    }

    $serverVersion = ($dockerInfoOutput | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($serverVersion)) {
        Write-Log -Level Success -Message 'Docker daemon sẵn sàng.'
    } else {
        Write-Log -Level Success -Message "Docker daemon sẵn sàng (server $serverVersion)."
    }
}

function Confirm-DockerImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Image
    )

    Write-Log -Level Step -Message "Kiểm tra Docker image: $Image"

    if (Test-DockerImage -Image $Image) {
        Write-Log -Level Success -Message "Đã có Docker image local."
        return
    }

    Write-Log -Level Warning -Message "Chưa có Docker image local: $Image"
    $answer = Read-Host "Cho phép pull image này? [y/N]"
    $normalizedAnswer = $answer.Trim().ToLowerInvariant()
    $yesAnswers = @('y', 'yes', 'c', 'co', 'có')

    if ($yesAnswers -notcontains $normalizedAnswer) {
        Stop-WithMessage -Message "Thiếu Docker image '$Image'. Đã hủy vì user không xác nhận pull." -ExitCode 1
    }

    Write-Log -Level Step -Message "Đang pull Docker image: $Image"

    try {
        & docker pull $Image
        $pullExitCode = $LASTEXITCODE
    } catch {
        Stop-WithMessage -Message "Docker pull lỗi: $($_.Exception.Message)" -ExitCode 1
    }

    if ($pullExitCode -ne 0) {
        Stop-WithMessage -Message "Docker pull lỗi với exit code $pullExitCode." -ExitCode $pullExitCode
    }

    if (-not (Test-DockerImage -Image $Image)) {
        Stop-WithMessage -Message "Đã pull xong nhưng vẫn không inspect được Docker image: $Image" -ExitCode 1
    }

    Write-Log -Level Success -Message "Docker image đã sẵn sàng."
}

function Get-LatexmkMode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lines = Get-Content -LiteralPath $Path -TotalCount 20

    foreach ($line in $lines) {
        if ($line -match '^\s*%\s*!TeX\s+program\s*=\s*([A-Za-z0-9_-]+)\s*$') {
            $engine = $Matches[1].ToLowerInvariant()

            switch ($engine) {
                'xelatex' { return '-xelatex' }
                'lualatex' { return '-lualatex' }
                'pdflatex' { return '-pdf' }
                default {
                    Write-Log -Level Warning -Message "Không nhận diện engine '$engine', dùng latexmk -pdf."
                    return '-pdf'
                }
            }
        }
    }

    return '-pdf'
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
    Stop-WithMessage -Message "Không tìm thấy file TeX: $TexPath" -ExitCode 1
}

if (-not (Test-Path -LiteralPath $resolvedTexPath -PathType Leaf)) {
    Stop-WithMessage -Message "Đường dẫn không phải file: $resolvedTexPath" -ExitCode 1
}

if ([System.IO.Path]::GetExtension($resolvedTexPath) -ine '.tex') {
    Stop-WithMessage -Message "Input phải là file .tex: $resolvedTexPath" -ExitCode 1
}

Write-Section -Title 'compile_tex'
Write-Log -Level Info -Message "Input: $resolvedTexPath"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Stop-WithMessage -Message "Không tìm thấy Docker trong PATH." -ExitCode 1
}

$texDirectory = Split-Path -Parent $resolvedTexPath
$texFileName = Split-Path -Leaf $resolvedTexPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texFileName)
$artifactDirectory = Join-Path $texDirectory "${baseName}_artifacts"
$pdfPath = Join-Path $texDirectory "$baseName.pdf"
$latexmkMode = Get-LatexmkMode -Path $resolvedTexPath

Write-Log -Level Info -Message "Output PDF: $pdfPath"
Write-Log -Level Info -Message "Artifact: $artifactDirectory"
Write-Log -Level Info -Message "Latexmk mode: $latexmkMode"

Assert-DockerDaemon
Confirm-DockerImage -Image $dockerImage

$dockerArgs = @(
    'run',
    '--rm',
    '--pull=never',
    '-v',
    "${texDirectory}:/workdir",
    '-w',
    '/workdir',
    $dockerImage,
    'latexmk',
    $latexmkMode,
    '-interaction=nonstopmode',
    '-halt-on-error',
    '-file-line-error',
    $texFileName
)

Write-Section -Title 'Build LaTeX'
try {
    & docker @dockerArgs
    $buildExitCode = $LASTEXITCODE
} catch {
    $buildExitCode = if (($null -ne $LASTEXITCODE) -and ($LASTEXITCODE -ne 0)) { $LASTEXITCODE } else { 1 }
    Write-Log -Level Warning -Message "Docker run lỗi: $($_.Exception.Message)"
}

Write-Section -Title 'Dọn artifact'
try {
    Move-LatexArtifacts `
        -TexDirectory $texDirectory `
        -BaseName $baseName `
        -DestinationDirectory $artifactDirectory `
        -Extensions $artifactExtensions
} catch {
    Stop-WithMessage -Message "Không chuyển được artifact LaTeX: $($_.Exception.Message)" -ExitCode 1
}

if ($buildExitCode -ne 0) {
    Stop-WithMessage -Message "Build LaTeX lỗi với exit code $buildExitCode. Artifact nằm tại: $artifactDirectory" -ExitCode $buildExitCode
}

if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
    Stop-WithMessage -Message "Build LaTeX hoàn tất nhưng không tìm thấy PDF: $pdfPath" -ExitCode 1
}

Write-Log -Level Success -Message "PDF: $pdfPath"
Write-Log -Level Success -Message "Artifact: $artifactDirectory"
exit 0
