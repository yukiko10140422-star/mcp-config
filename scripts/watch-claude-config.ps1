# Claude Config Watcher (FileSystemWatcher + debounce)
# ~/.claude/ の設定ファイル変更を検知し sync-mcp.sh --global を自動実行する

$watchDir = Join-Path $env:USERPROFILE ".claude"
$watchFiles = @(".mcp.json", "CLAUDE.md", "settings.json")
$syncScript = Join-Path $watchDir "mcp-config" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "sync-mcp.sh"
$debounceSeconds = 5

# Git Bash を検出
$gitBash = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBash) {
    Write-Error "Git Bash が見つかりません"
    exit 1
}

if (-not (Test-Path $syncScript)) {
    Write-Error "sync-mcp.sh が見つかりません: $syncScript"
    exit 1
}

# Unix パスに変換
$syncScriptUnix = & $gitBash -c "cygpath '$($syncScript -replace '\\','/')'" 2>$null
if (-not $syncScriptUnix) {
    $syncScriptUnix = $syncScript.Replace('\', '/').Replace('C:', '/c')
}

Write-Host "Claude Config Watcher started (FileSystemWatcher, debounce ${debounceSeconds}s)"
Write-Host "  Watch dir: $watchDir"
Write-Host "  Watch files: $($watchFiles -join ', ')"

# FileSystemWatcher の作成
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $watchDir
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $false

$lastTrigger = [DateTime]::MinValue

try {
    $watcher.EnableRaisingEvents = $true
    Write-Host "Watching..."

    while ($true) {
        $result = $watcher.WaitForChanged(
            [System.IO.WatcherChangeTypes]::Changed -bor
            [System.IO.WatcherChangeTypes]::Created -bor
            [System.IO.WatcherChangeTypes]::Renamed,
            2000  # 2秒タイムアウト
        )

        if (-not $result.TimedOut) {
            $changedFile = $result.Name
            if ($watchFiles -contains $changedFile) {
                $now = [DateTime]::Now
                $elapsed = ($now - $lastTrigger).TotalSeconds

                if ($elapsed -ge $debounceSeconds) {
                    $lastTrigger = $now
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Changed: $changedFile -> running sync-mcp.sh --global..."

                    try {
                        $proc = Start-Process -FilePath $gitBash `
                            -ArgumentList "-l", "-c", "`"$syncScriptUnix --global`"" `
                            -NoNewWindow -Wait -PassThru

                        Write-Host "[$($now.ToString('HH:mm:ss'))] Sync complete (exit: $($proc.ExitCode))"
                    } catch {
                        Write-Host "[$($now.ToString('HH:mm:ss'))] Sync error: $_"
                    }
                } else {
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Debounce: $changedFile (wait $([math]::Ceiling($debounceSeconds - $elapsed))s)"
                }
            }
        }
    }
} finally {
    $watcher.Dispose()
    Write-Host "Claude Config Watcher stopped"
}
