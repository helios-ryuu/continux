<# 
file-update.ps1 — Đồng bộ thư mục local Windows sang máy SSH
Chạy trên : Windows PowerShell
Mục đích  : Copy thay đổi từ local sang remote, bỏ qua file không đổi
Cú pháp   : .\scripts\file-update.ps1
           .\scripts\file-update.ps1 -RunDefault `
              [-SourceDir D:\project\continux] [-Target imac] [-RemoteDir ~/continux] `
              [-Port 22] [-IdentityFile C:\path\id_ed25519] [-DryRun] [-Delete] [-NoAgent]
#>

[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$Target = "imac",
    [string]$RemoteDir = "~/continux",
    [int]$Port = 22,
    [string]$IdentityFile,
    [switch]$RunDefault,
    [switch]$DryRun,
    [switch]$Delete,
    [switch]$Multiplex,
    [switch]$NoAgent
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    $scriptPath = ".\scripts\file-update.ps1"
    Write-Host ""
    Write-Host "file-update.ps1 — Đồng bộ repo Windows sang máy SSH"
    Write-Host ""
    Write-Host "Cách chạy:"
    Write-Host "  $scriptPath -RunDefault"
    Write-Host "  $scriptPath -SourceDir D:\project\continux -Target imac -RemoteDir ~/continux"
    Write-Host "  $scriptPath -Target helios@100.x.x.x -RemoteDir /home/helios/continux -Port 22 -IdentityFile C:\Users\Helios\.ssh\id_ed25519"
    Write-Host "  $scriptPath -DryRun"
    Write-Host "  $scriptPath -Delete"
    Write-Host "  $scriptPath -RunDefault -NoAgent"
    Write-Host "  $scriptPath -RunDefault -Multiplex"
    Write-Host ""
    Write-Host "Tham số:"
    Write-Host "  -RunDefault    Chạy với mặc định: SourceDir=repo hiện tại, Target=imac, RemoteDir=~/continux"
    Write-Host "  -SourceDir     Thư mục local cần đồng bộ"
    Write-Host "  -Target        SSH alias hoặc user@host"
    Write-Host "  -RemoteDir     Thư mục đích trên máy remote"
    Write-Host "  -Port          SSH port, mặc định 22"
    Write-Host "  -IdentityFile  SSH private key nếu không dùng key mặc định"
    Write-Host "  -DryRun        Chỉ hiển thị thay đổi, không copy/xoá"
    Write-Host "  -Delete        Xoá file remote không còn tồn tại ở local"
    Write-Host "  -NoAgent       Không tự gọi ssh-agent/ssh-add"
    Write-Host "  -Multiplex     Thử bật SSH multiplexing nếu OpenSSH hỗ trợ"
    Write-Host ""
    Write-Host "Ghi chú: passphrase của SSH key sẽ được ssh/scp hỏi trực tiếp trong terminal."
    Write-Host "Nếu không muốn nhập passphrase nhiều lần: Start-Service ssh-agent; ssh-add C:\Users\Helios\.ssh\id_ed25519"
    Write-Host ""
}

if ($PSBoundParameters.Count -eq 0) {
    Show-Usage
    exit 0
}

function Get-RelativeUnixPath {
    param(
        [Parameter(Mandatory=$true)][string]$Base,
        [Parameter(Mandatory=$true)][string]$Path
    )

    $relative = [System.IO.Path]::GetRelativePath($Base, $Path)
    return ($relative -replace "\\", "/")
}

function Quote-RemoteSingle {
    param([Parameter(Mandatory=$true)][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Join-RemotePath {
    param(
        [Parameter(Mandatory=$true)][string]$Base,
        [Parameter(Mandatory=$true)][string]$Relative
    )
    return ($Base.TrimEnd("/") + "/" + $Relative.TrimStart("/"))
}

function Convert-RemotePathToShellExpression {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ($Path -eq "~") {
        return '$HOME'
    }
    if ($Path.StartsWith("~/")) {
        return '$HOME/' + (Quote-RemoteSingle $Path.Substring(2))
    }
    return Quote-RemoteSingle $Path
}

function Write-Step {
    param([Parameter(Mandatory=$true)][string]$Message)
    Write-Host (">>> [{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Assert-NativeCommand {
    param([Parameter(Mandatory=$true)][string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action thất bại (exit code $LASTEXITCODE)."
    }
}

function Ensure-SshAgentKey {
    param([string]$KeyPath)

    if ($NoAgent) {
        Write-Host ">>> SSH key: bỏ qua ssh-agent (-NoAgent)"
        return
    }
    if (-not (Get-Command ssh-add -ErrorAction SilentlyContinue)) {
        Write-Host ">>> SSH key: không tìm thấy ssh-add, bỏ qua ssh-agent"
        return
    }
    if ([string]::IsNullOrWhiteSpace($KeyPath)) {
        $defaultKey = Join-Path $HOME ".ssh\id_ed25519"
        if (Test-Path -LiteralPath $defaultKey) {
            $KeyPath = $defaultKey
        } else {
            Write-Host ">>> SSH key: không tìm thấy key mặc định $defaultKey, bỏ qua ssh-agent"
            return
        }
    }

    $resolvedKey = (Resolve-Path $KeyPath).Path

    $service = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        try {
            Start-Service ssh-agent -ErrorAction Stop
        } catch {
            Write-Host ">>> SSH key: không start được ssh-agent. Chạy thủ công: Start-Service ssh-agent"
            return
        }
    }

    $loadedKeys = @(& ssh-add -l 2>$null)
    if ($LASTEXITCODE -eq 0 -and ($loadedKeys -join "`n") -match [regex]::Escape($resolvedKey)) {
        Write-Host ">>> SSH key: đã có trong ssh-agent"
        return
    }

    Write-Step "Đang nạp SSH key vào ssh-agent. Nhập passphrase một lần nếu được hỏi."
    & ssh-add $resolvedKey
    Assert-NativeCommand "Nạp SSH key vào ssh-agent"
}

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $ProjectDir = (Resolve-Path $SourceDir).Path
}

$ManifestLocal = Join-Path $env:TEMP "continux-local-manifest.tsv"
$ManifestRemote = Join-Path $env:TEMP "continux-remote-manifest.tsv"

$SshArgs = @()
$ScpArgs = @()
if ($Port -ne 22) {
    $SshArgs += @("-p", "$Port")
    $ScpArgs += @("-P", "$Port")
}
if (-not [string]::IsNullOrWhiteSpace($IdentityFile)) {
    $IdentityPath = (Resolve-Path $IdentityFile).Path
    $SshArgs += @("-i", $IdentityPath)
    $ScpArgs += @("-i", $IdentityPath)
}

Ensure-SshAgentKey -KeyPath $IdentityFile

if ($Multiplex) {
    $controlName = "continux-ssh-{0}.sock" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
    $controlPath = (Join-Path $env:TEMP $controlName) -replace "\\", "/"
    $muxArgs = @(
        "-o", "ControlMaster=auto",
        "-o", "ControlPersist=5m",
        "-o", "ControlPath=$controlPath"
    )
    $SshArgs += $muxArgs
    $ScpArgs += $muxArgs
}

$ExcludeDirs = @(
    ".git",
    ".idea",
    ".vscode",
    "data",
    "scripts\k3s-check"
)

$ExcludeFiles = @(
    ".DS_Store",
    "Thumbs.db"
)

$ExcludePatterns = @(
    "*.log"
)

Write-Host ">>> Source : $ProjectDir"
Write-Host ">>> Target : ${Target}:${RemoteDir}"
if ($DryRun) { Write-Host ">>> Mode   : dry-run" }
if ($Delete) { Write-Host ">>> Delete : enabled for remote files not present locally" }
if ($Multiplex) {
    Write-Host ">>> SSH    : multiplexing enabled (experimental)"
} else {
    Write-Host ">>> SSH    : multiplexing disabled"
}
if ($NoAgent) {
    Write-Host ">>> Agent  : disabled"
} else {
    Write-Host ">>> Agent  : enabled (ssh-add nếu cần)"
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "Không tìm thấy ssh trong PATH."
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    throw "Không tìm thấy scp trong PATH."
}
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    throw "Không tìm thấy tar trong PATH."
}

Write-Step "Đang resolve đường dẫn remote. Nếu SSH key có passphrase, nhập passphrase ở prompt bên dưới."
Write-Progress -Activity "Chuẩn bị remote" -Status "Resolve ${Target}:${RemoteDir}" -PercentComplete 0
$remoteDirExpr = Convert-RemotePathToShellExpression $RemoteDir
$remoteResolveScript = "mkdir -p $remoteDirExpr && cd $remoteDirExpr && pwd -P"
$remoteResolveOutput = @(& ssh @SshArgs $Target $remoteResolveScript)
Assert-NativeCommand "Resolve đường dẫn remote"
$RemoteAbsDir = ($remoteResolveOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
if ([string]::IsNullOrWhiteSpace($RemoteAbsDir)) {
    throw "Không resolve được đường dẫn remote: ${Target}:${RemoteDir}"
}
$RemoteAbsDir = $RemoteAbsDir.Trim()
Write-Progress -Activity "Chuẩn bị remote" -Completed
Write-Step "Remote đã sẵn sàng: ${Target}:${RemoteAbsDir}"

Write-Step "Đang quét file local..."
Write-Progress -Activity "Quét file local" -Status "Đang liệt kê file cần đồng bộ" -PercentComplete 0
$files = @(Get-ChildItem -LiteralPath $ProjectDir -File -Recurse | Where-Object {
    $full = $_.FullName
    $relWin = [System.IO.Path]::GetRelativePath($ProjectDir, $full)
    $parts = $relWin -split [regex]::Escape([System.IO.Path]::DirectorySeparatorChar)
    $excluded = $false

    foreach ($dir in $ExcludeDirs) {
        $dirParts = $dir -split "\\"
        if ($parts.Length -ge $dirParts.Length) {
            $prefix = ($parts[0..($dirParts.Length - 1)] -join "\")
            if ($prefix -ieq $dir) {
                $excluded = $true
                break
            }
        }
    }

    if ($excluded) { return $false }

    if ($ExcludeFiles -contains $_.Name) { $excluded = $true }

    foreach ($pattern in $ExcludePatterns) {
        if ($_.Name -like $pattern) {
            $excluded = $true
            break
        }
    }

    return (-not $excluded)
})
Write-Progress -Activity "Quét file local" -Completed
Write-Step "Tìm thấy $($files.Count) file local sau khi loại trừ."

Write-Step "Đang tính SHA-256 cho file local..."
$localItems = @()
$hashIndex = 0
$hashTotal = [Math]::Max($files.Count, 1)
foreach ($file in $files) {
    $hashIndex++
    $rel = Get-RelativeUnixPath -Base $ProjectDir -Path $file.FullName
    $percent = [Math]::Min(100, [int](($hashIndex / $hashTotal) * 100))
    Write-Progress -Activity "Tính hash local" -Status "$hashIndex/$($files.Count) $rel" -PercentComplete $percent
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $localItems += [PSCustomObject]@{
        Relative = $rel
        FullName = $file.FullName
        Hash = $hash
    }
}
Write-Progress -Activity "Tính hash local" -Completed
Write-Step "Đã tính hash local."

$localRows = foreach ($item in $localItems) {
    "$($item.Hash)`t$($item.Relative)"
}

$localRows | Sort-Object | Set-Content -LiteralPath $ManifestLocal -Encoding UTF8

$remoteScriptTemplate = @'
cd $RemoteAbsDirExpr 2>/dev/null || exit 0
find . -type f \
  ! -path './.git/*' \
  ! -path './.idea/*' \
  ! -path './.vscode/*' \
  ! -path './data/*' \
  ! -path './scripts/k3s-check/*' \
  ! -name '*.log' \
  ! -name '.DS_Store' \
  ! -name 'Thumbs.db' \
  -print0 | while IFS= read -r -d '' f; do
    rel="${f#./}"
    hash="$(sha256sum "$f" | awk '{print $1}')"
    printf '%s\t%s\n' "$hash" "$rel"
  done
'@

$remoteScript = $remoteScriptTemplate.Replace('$RemoteAbsDirExpr', (Quote-RemoteSingle $RemoteAbsDir))

Write-Step "Đang đọc danh sách file remote và tính hash remote..."
Write-Progress -Activity "Đọc remote" -Status "Đang lấy danh sách file và hash từ ${Target}:${RemoteAbsDir}" -PercentComplete 0
& ssh @SshArgs $Target $remoteScript | Set-Content -LiteralPath $ManifestRemote -Encoding UTF8
Assert-NativeCommand "Đọc danh sách file remote"
Write-Progress -Activity "Đọc remote" -Completed

$remoteMap = @{}
if (Test-Path $ManifestRemote) {
    Get-Content -LiteralPath $ManifestRemote | ForEach-Object {
        if ($_ -match "^(?<hash>[a-f0-9]{64})\t(?<path>.+)$") {
            $remoteMap[$Matches.path] = $Matches.hash
        }
    }
}
Write-Step "Tìm thấy $($remoteMap.Count) file remote sau khi loại trừ."

Write-Step "Đang so sánh local với remote..."
$changed = @()
$localPathSet = New-Object 'System.Collections.Generic.HashSet[string]'
$compareIndex = 0
$compareTotal = [Math]::Max($localItems.Count, 1)
foreach ($item in $localItems) {
    $compareIndex++
    $rel = $item.Relative
    $percent = [Math]::Min(100, [int](($compareIndex / $compareTotal) * 100))
    Write-Progress -Activity "So sánh thay đổi" -Status "$compareIndex/$($localItems.Count) $rel" -PercentComplete $percent
    [void]$localPathSet.Add($rel)
    if (-not $remoteMap.ContainsKey($rel) -or $remoteMap[$rel] -ne $item.Hash) {
        $changed += [PSCustomObject]@{
            Relative = $rel
            FullName = $item.FullName
        }
    }
}
Write-Progress -Activity "So sánh thay đổi" -Completed
Write-Step "So sánh hoàn tất."

$deleted = @()
if ($Delete) {
    foreach ($remotePath in $remoteMap.Keys) {
        if (-not $localPathSet.Contains($remotePath)) {
            $deleted += $remotePath
        }
    }
}

if ($changed.Count -eq 0 -and $deleted.Count -eq 0) {
    Write-Host "✓ Không có thay đổi. Không sao chép."
    Remove-Item -LiteralPath $ManifestLocal,$ManifestRemote -ErrorAction SilentlyContinue
    exit 0
}

Write-Host ">>> Có $($changed.Count) file thay đổi và $($deleted.Count) file cần xoá trên remote."

if ($changed.Count -gt 0) {
    if ($DryRun) {
        foreach ($item in $changed) {
            Write-Host "  COPY $($item.Relative)"
        }
    } else {
        Write-Step "Đang đóng gói $($changed.Count) file thay đổi thành tar..."
        $syncId = [guid]::NewGuid().ToString("N")
        $stageDir = Join-Path $env:TEMP "continux-sync-stage-$syncId"
        $archiveLocal = Join-Path $env:TEMP "continux-sync-$syncId.tar"
        $remoteArchive = "/tmp/continux-sync-$syncId.tar"

        try {
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

            $copyIndex = 0
            $copyTotal = [Math]::Max($changed.Count, 1)
            foreach ($item in $changed) {
                $copyIndex++
                $copyPercent = [Math]::Min(100, [int](($copyIndex / $copyTotal) * 100))
                Write-Progress -Activity "Chuẩn bị gói upload" -Status "$copyIndex/$($changed.Count) $($item.Relative)" -PercentComplete $copyPercent
                $relativeWin = $item.Relative -replace "/", [System.IO.Path]::DirectorySeparatorChar
                $stagePath = Join-Path $stageDir $relativeWin
                $stageParent = Split-Path -Parent $stagePath
                if (-not [string]::IsNullOrWhiteSpace($stageParent)) {
                    New-Item -ItemType Directory -Path $stageParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $item.FullName -Destination $stagePath -Force
            }
            Write-Progress -Activity "Chuẩn bị gói upload" -Completed

            Write-Progress -Activity "Tạo tar" -Status $archiveLocal -PercentComplete 0
            & tar -cf $archiveLocal -C $stageDir .
            Assert-NativeCommand "Tạo tar local"
            Write-Progress -Activity "Tạo tar" -Completed

            Write-Step "Đang upload tar lên remote..."
            Write-Progress -Activity "Upload tar" -Status "${Target}:${remoteArchive}" -PercentComplete 0
            $scpArchiveTarget = "${Target}:$remoteArchive"
            & scp @ScpArgs $archiveLocal $scpArchiveTarget
            Assert-NativeCommand "Upload tar"
            Write-Progress -Activity "Upload tar" -Completed

            Write-Step "Đang giải nén tar vào ${Target}:${RemoteAbsDir}..."
            Write-Progress -Activity "Giải nén remote" -Status $RemoteAbsDir -PercentComplete 0
            $extractScript = "mkdir -p $(Quote-RemoteSingle $RemoteAbsDir) && tar -xf $(Quote-RemoteSingle $remoteArchive) -C $(Quote-RemoteSingle $RemoteAbsDir) && rm -f $(Quote-RemoteSingle $remoteArchive)"
            & ssh @SshArgs $Target $extractScript
            Assert-NativeCommand "Giải nén tar trên remote"
            Write-Progress -Activity "Giải nén remote" -Completed
        } finally {
            Remove-Item -LiteralPath $stageDir,$archiveLocal -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
if ($changed.Count -gt 0) {
    Write-Step "Copy hoàn tất."
}

if ($deleted.Count -gt 0) {
    Write-Step "Đang xoá $($deleted.Count) file remote không còn tồn tại ở local..."
}
$deleteIndex = 0
$deleteTotal = [Math]::Max($deleted.Count, 1)
foreach ($rel in $deleted) {
    $deleteIndex++
    $deletePercent = [Math]::Min(100, [int](($deleteIndex / $deleteTotal) * 100))
    Write-Progress -Activity "Xoá file remote" -Status "$deleteIndex/$($deleted.Count) $rel" -PercentComplete $deletePercent
    $remotePath = Join-RemotePath -Base $RemoteAbsDir -Relative $rel
    if ($DryRun) {
        Write-Host "  DELETE $rel"
        continue
    }
    & ssh @SshArgs $Target "rm -f $(Quote-RemoteSingle $remotePath)"
    Assert-NativeCommand "Xoá file remote $rel"
    Write-Host "  deleted $rel"
}
Write-Progress -Activity "Xoá file remote" -Completed
if ($deleted.Count -gt 0) {
    Write-Step "Xoá remote hoàn tất."
}

Remove-Item -LiteralPath $ManifestLocal,$ManifestRemote -ErrorAction SilentlyContinue
if ($DryRun) {
    Write-Host "✓ Dry-run hoàn tất. Chưa copy/xoá gì."
} else {
    Write-Host "✓ Đồng bộ hoàn tất."
}
