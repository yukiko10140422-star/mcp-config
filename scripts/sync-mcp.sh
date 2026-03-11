#!/bin/bash
# MCP設定変更時の自動同期スクリプト
# 1. プロジェクトの.mcp.jsonをプロジェクトリポジトリにcommit & push
# 2. MCP履歴をmcp-configリポジトリに記録
# 3. README.mdを自動更新してpush
# 4. グローバル設定の同期・デプロイ

MCP_REPO="$HOME/.claude/mcp-config"
HISTORY_FILE="$MCP_REPO/mcp-history.json"
CLAUDE_DIR="$HOME/.claude"
GLOBAL_DIR="$MCP_REPO/global"
GLOBAL_FILES=(".mcp.json" "CLAUDE.md" "settings.json")

# ---- コマンドライン引数パーサー ----
MODE="project"
FILE=""
case "${1:-}" in
  --global) MODE="global" ;;
  --deploy) MODE="deploy" ;;
  *)        MODE="project"; FILE="$1" ;;
esac

# ---- 1. プロジェクトリポジトリの .mcp.json を commit & push ----
sync_project_repo() {
  local mcp_dir=$(dirname "$FILE")

  if ! git -C "$mcp_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  cd "$mcp_dir" || return 0

  if git diff --name-only -- .mcp.json 2>/dev/null | grep -q ".mcp.json" || \
     git diff --cached --name-only -- .mcp.json 2>/dev/null | grep -q ".mcp.json"; then
    git add .mcp.json
    git commit -m "MCP設定更新: .mcp.json"
    git push 2>/dev/null
  fi
}

# ---- 2. MCP履歴を記録 ----
update_mcp_history() {
  if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"version":1,"entries":[]}' > "$HISTORY_FILE"
  fi

  local mcp_file="$1"
  local project_dir="$2"
  local project_name="$3"

  [ ! -f "$mcp_file" ] && return 0

  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Windows パス変換
  local history_w mcp_w
  history_w=$(cygpath -w "$HISTORY_FILE" 2>/dev/null) || history_w="$HISTORY_FILE"
  mcp_w=$(cygpath -w "$mcp_file" 2>/dev/null) || mcp_w="$mcp_file"

  local tmpjs=$(mktemp /tmp/sync-mcp-XXXXXX.mjs)

  cat > "$tmpjs" << 'NODESCRIPT'
import { readFileSync, writeFileSync } from 'fs';
const [historyPath, mcpPath, projectDir, projectName, ts] = process.argv.slice(2);

const history = JSON.parse(readFileSync(historyPath, 'utf8'));
const mcpConfig = JSON.parse(readFileSync(mcpPath, 'utf8'));
const servers = mcpConfig.mcpServers || mcpConfig;

for (const [name, config] of Object.entries(servers)) {
  const existing = history.entries.find(e =>
    e.serverName === name &&
    e.project === projectDir &&
    JSON.stringify(e.config) === JSON.stringify(config)
  );
  if (existing) continue;

  const meta = {
    serverType: config.type || (config.command ? 'stdio' : 'unknown'),
  };

  if (config.args) {
    const pkgArg = config.args.find(a =>
      a.startsWith('@') || (!a.startsWith('-') && !a.startsWith('--') && a.includes('-'))
    );
    if (pkgArg) meta.packageName = pkgArg.replace(/@latest$/, '');
  }

  if (config.command) meta.command = config.command;
  if (config.url) meta.url = config.url;

  const configStr = JSON.stringify(config);
  const envMatches = [...configStr.matchAll(/\$\{([^}]+)\}/g)];
  if (envMatches.length > 0) {
    meta.requiredEnvVars = envMatches.map(m => m[1]);
  }

  history.entries.push({
    serverName: name,
    action: 'snapshot',
    timestamp: ts,
    scope: projectName === 'global' ? 'global' : 'project',
    project: projectDir,
    projectName,
    config,
    meta
  });
}

writeFileSync(historyPath, JSON.stringify(history, null, 2));
NODESCRIPT

  node "$tmpjs" "$history_w" "$mcp_w" "$project_dir" "$project_name" "$timestamp" 2>/dev/null
  rm -f "$tmpjs"

  # プロジェクト別スナップショットも保存（global以外）
  if [ "$project_name" != "global" ]; then
    local projects_dir="$MCP_REPO/projects"
    mkdir -p "$projects_dir"

    local safe_name=$(echo "$project_name" | tr ' ' '-')
    local snapshot="$projects_dir/${safe_name}.mcp.json"
    cp "$mcp_file" "$snapshot"
  fi
}

# ---- 3. README.md 自動更新 ----
generate_readme() {
  local readme="$MCP_REPO/README.md"
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local gen_script="$script_dir/generate-readme.mjs"

  local readme_w history_w projects_w global_w
  readme_w=$(cygpath -w "$readme" 2>/dev/null) || readme_w="$readme"
  history_w=$(cygpath -w "$HISTORY_FILE" 2>/dev/null) || history_w="$HISTORY_FILE"
  projects_w=$(cygpath -w "$MCP_REPO/projects" 2>/dev/null) || projects_w="$MCP_REPO/projects"
  global_w=$(cygpath -w "$GLOBAL_DIR" 2>/dev/null) || global_w="$GLOBAL_DIR"

  node "$gen_script" "$readme_w" "$history_w" "$projects_w" "$global_w"
}

# ---- 4. グローバル設定を同期 (ローカル → リポジトリ) ----
sync_global_config() {
  mkdir -p "$GLOBAL_DIR"

  local changed=0
  for f in "${GLOBAL_FILES[@]}"; do
    local src="$CLAUDE_DIR/$f"
    local dst="$GLOBAL_DIR/$f"

    if [ ! -f "$src" ]; then
      echo "スキップ: $src が見つかりません"
      continue
    fi

    if [ -f "$dst" ] && diff --strip-trailing-cr "$src" "$dst" >/dev/null 2>&1; then
      echo "変更なし: $f"
    else
      cp "$src" "$dst"
      echo "コピー: $f → global/$f"
      changed=1
    fi
  done

  if [ "$changed" -eq 0 ]; then
    echo "グローバル設定に変更はありません"
  fi
}

# ---- 5. グローバル設定をデプロイ (リポジトリ → ローカル) ----
deploy_global_config() {
  if [ ! -d "$GLOBAL_DIR" ]; then
    echo "エラー: $GLOBAL_DIR が見つかりません"
    exit 1
  fi

  for f in "${GLOBAL_FILES[@]}"; do
    local src="$GLOBAL_DIR/$f"
    local dst="$CLAUDE_DIR/$f"

    if [ ! -f "$src" ]; then
      echo "スキップ: global/$f が見つかりません"
      continue
    fi

    if [ -f "$dst" ]; then
      if diff --strip-trailing-cr "$src" "$dst" >/dev/null 2>&1; then
        echo "変更なし: $f"
        continue
      fi
      read -p "上書きしますか？ $f [y/N]: " confirm
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "スキップ: $f"
        continue
      fi
    fi

    cp "$src" "$dst"
    echo "デプロイ: global/$f → ~/.claude/$f"
  done

  echo ""
  echo "デプロイ完了！"
  echo ""
  echo "以下の環境変数を手動で設定してください（必要なサーバーのみ）："
  echo "  - VERCEL_ACCESS_TOKEN"
  echo "  - EBAY_CLIENT_ID"
  echo "  - EBAY_CLIENT_SECRET"
  echo "  - EBAY_DEV_ID"
  echo "  - EBAY_REDIRECT_URI"
}

# ---- 6. mcp-config リポジトリに commit & push ----
push_mcp_repo() {
  local commit_msg="$1"
  cd "$MCP_REPO" || return 0
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "$commit_msg"
    git push origin master 2>/dev/null || git push origin main 2>/dev/null
  fi
}

# ---- メイン ----
case "$MODE" in
  project)
    [ -z "$FILE" ] && { echo "Usage: sync-mcp.sh <path>|--global|--deploy"; exit 1; }
    sync_project_repo
    update_mcp_history "$FILE" "$(dirname "$FILE")" "$(basename "$(dirname "$FILE")")"
    generate_readme
    push_mcp_repo "MCP設定更新: $(basename "$(dirname "$FILE")")"
    ;;
  global)
    sync_global_config
    update_mcp_history "$CLAUDE_DIR/.mcp.json" "global" "global"
    generate_readme
    push_mcp_repo "グローバルMCP設定更新"
    ;;
  deploy)
    deploy_global_config
    ;;
esac
