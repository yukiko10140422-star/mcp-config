# Claude Config & Skills Watcher (FileSystemWatcher + Register-ObjectEvent)
# ~/.claude/ の設定ファイル変更 → sync-mcp.sh --global
# ~/.claude/plugins/marketplaces/local/ のスキル変更 → sync-skills.sh

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$watchFiles = @(".mcp.json", "CLAUDE.md", "settings.json")
$syncMcpScript = Join-Path $claudeDir "mcp-config" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "sync-mcp.sh"
$skillsDir = Join-Path $claudeDir "plugins\marketplaces\local"
$syncSkillsScript = Join-Path $skillsDir "scripts" | Join-Path -ChildPath "sync-skills.sh"
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

if (-not (Test-Path $syncMcpScript)) {
    Write-Error "sync-mcp.sh が見つかりません: $syncMcpScript"
    exit 1
}

# Unix パスに変換
$syncMcpUnix = & $gitBash -c "cygpath '$($syncMcpScript -replace '\\','/')'" 2>$null
if (-not $syncMcpUnix) {
    $syncMcpUnix = $syncMcpScript.Replace('\', '/').Replace('C:', '/c')
}

$syncSkillsUnix = ""
if (Test-Path $syncSkillsScript) {
    $syncSkillsUnix = & $gitBash -c "cygpath '$($syncSkillsScript -replace '\\','/')'" 2>$null
    if (-not $syncSkillsUnix) {
        $syncSkillsUnix = $syncSkillsScript.Replace('\', '/').Replace('C:', '/c')
    }
}

# --- ウォッチャー #1: 設定ファイル ---
$configWatcher = New-Object System.IO.FileSystemWatcher
$configWatcher.Path = $claudeDir
$configWatcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$configWatcher.EnableRaisingEvents = $true

# --- ウォッチャー #2: スキルディレクトリ ---
$skillsWatcher = $null
if (Test-Path $skillsDir) {
    $skillsWatcher = New-Object System.IO.FileSystemWatcher
    $skillsWatcher.Path = $skillsDir
    $skillsWatcher.IncludeSubdirectories = $true
    $skillsWatcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor
                                   [System.IO.NotifyFilters]::FileName -bor
                                   [System.IO.NotifyFilters]::DirectoryName
    $skillsWatcher.EnableRaisingEvents = $true
}

# 共通: デバウンス・状態変数
$script:pendingConfig = $false
$script:pendingSkills = $false
$script:lastConfigTrigger = [DateTime]::MinValue
$script:lastSkillsTrigger = [DateTime]::MinValue
$script:syncing = $false

# イベントアクション
$configAction = {
    if ($script:syncing) { return }
    $name = $Event.SourceEventArgs.Name
    if ($watchFiles -contains $name) {
        $script:pendingConfig = $true
    }
}

$skillsAction = {
    if ($script:syncing) { return }
    $path = $Event.SourceEventArgs.FullPath
    # .git 配下の変更は無視（無限ループ防止）
    if ($path -match '[\\/]\.git[\\/]') { return }
    $script:pendingSkills = $true
}

# イベント登録
Register-ObjectEvent $configWatcher "Changed" -Action $configAction | Out-Null
Register-ObjectEvent $configWatcher "Created" -Action $configAction | Out-Null
Register-ObjectEvent $configWatcher "Renamed" -Action $configAction | Out-Null

if ($skillsWatcher) {
    Register-ObjectEvent $skillsWatcher "Changed" -Action $skillsAction | Out-Null
    Register-ObjectEvent $skillsWatcher "Created" -Action $skillsAction | Out-Null
    Register-ObjectEvent $skillsWatcher "Deleted" -Action $skillsAction | Out-Null
    Register-ObjectEvent $skillsWatcher "Renamed" -Action $skillsAction | Out-Null
}

Write-Host "Claude Config & Skills Watcher started (debounce ${debounceSeconds}s)"
Write-Host "  Config watch: $claudeDir ($($watchFiles -join ', '))"
if ($skillsWatcher) {
    Write-Host "  Skills watch: $skillsDir (recursive)"
}
Write-Host "Watching..."

try {
    while ($true) {
        Start-Sleep -Seconds 1

        $now = [DateTime]::Now

        # 設定ファイル同期
        if ($script:pendingConfig) {
            $elapsed = ($now - $script:lastConfigTrigger).TotalSeconds
            if ($elapsed -ge $debounceSeconds) {
                $script:syncing = $true
                $script:pendingConfig = $false
                $script:lastConfigTrigger = $now

                Write-Host "[$($now.ToString('HH:mm:ss'))] Config changed -> running sync-mcp.sh --global..."
                try {
                    $proc = Start-Process -FilePath $gitBash `
                        -ArgumentList "-l", "-c", "`"$syncMcpUnix --global`"" `
                        -NoNewWindow -Wait -PassThru
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Config sync complete (exit: $($proc.ExitCode))"
                } catch {
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Config sync error: $_"
                }

                $script:syncing = $false
            }
        }

        # スキル同期
        if ($script:pendingSkills) {
            $elapsed = ($now - $script:lastSkillsTrigger).TotalSeconds
            if ($elapsed -ge $debounceSeconds) {
                $script:syncing = $true
                $script:pendingSkills = $false
                $script:lastSkillsTrigger = $now

                Write-Host "[$($now.ToString('HH:mm:ss'))] Skills changed -> running sync-skills.sh..."
                try {
                    $proc = Start-Process -FilePath $gitBash `
                        -ArgumentList "-l", "-c", "`"$syncSkillsUnix`"" `
                        -NoNewWindow -Wait -PassThru
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Skills sync complete (exit: $($proc.ExitCode))"
                } catch {
                    Write-Host "[$($now.ToString('HH:mm:ss'))] Skills sync error: $_"
                }

                $script:syncing = $false
            }
        }
    }
} finally {
    $configWatcher.Dispose()
    if ($skillsWatcher) { $skillsWatcher.Dispose() }
    Get-EventSubscriber | Unregister-Event
    Write-Host "Claude Config & Skills Watcher stopped"
}
