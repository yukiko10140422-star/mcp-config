# ~/.claude/ 設定ファイルの変更監視 & 自動同期
# FileSystemWatcher で .mcp.json, CLAUDE.md, settings.json を監視
# 変更検知 → 5秒デバウンス → sync-mcp.sh --global を実行

$watchDir = Join-Path $env:USERPROFILE ".claude"
$watchFiles = @(".mcp.json", "CLAUDE.md", "settings.json")
$syncScript = Join-Path $watchDir "mcp-config\scripts\sync-mcp.sh"

# Git Bash のパスを検出
$gitBash = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBash) {
    Write-Error "Git Bash が見つかりません"
    exit 1
}

if (-not (Test-Path $syncScript)) {
    Write-Error "sync-mcp.sh が見つかりません: $syncScript"
    exit 1
}

Write-Host "Claude Config Watcher 起動"
Write-Host "  監視ディレクトリ: $watchDir"
Write-Host "  監視ファイル: $($watchFiles -join ', ')"

# FileSystemWatcher 作成
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $watchDir
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $false  # ポーリング方式で制御

# デバウンス用
$lastTrigger = [DateTime]::MinValue
$debounceSeconds = 5

Write-Host "監視開始..."

try {
    while ($true) {
        $result = $watcher.WaitForChanged(
            [System.IO.WatcherChangeTypes]::Changed -bor [System.IO.WatcherChangeTypes]::Created,
            1000  # 1秒タイムアウト
        )

        if ($result.TimedOut) { continue }

        # 対象ファイルかチェック
        if ($result.Name -notin $watchFiles) { continue }

        # デバウンス: 前回のトリガーから5秒以内なら無視
        $now = Get-Date
        if (($now - $lastTrigger).TotalSeconds -lt $debounceSeconds) { continue }

        $lastTrigger = $now
        Write-Host "[$($now.ToString('HH:mm:ss'))] 変更検知: $($result.Name)"

        # 少し待ってからファイルの書き込み完了を確認
        Start-Sleep -Seconds 2

        Write-Host "[$($now.ToString('HH:mm:ss'))] sync-mcp.sh --global を実行中..."
        try {
            $syncScriptUnix = $syncScript -replace '\\', '/'
            & $gitBash -l -c "$syncScriptUnix --global"
            Write-Host "[$($now.ToString('HH:mm:ss'))] 同期完了"
        } catch {
            Write-Host "[$($now.ToString('HH:mm:ss'))] 同期エラー: $_"
        }
    }
} finally {
    $watcher.Dispose()
    Write-Host "Watcher 終了"
}
