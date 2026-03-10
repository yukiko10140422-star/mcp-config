#!/bin/bash
# MCP設定変更時の自動同期スクリプト
# 1. プロジェクトの.mcp.jsonをプロジェクトリポジトリにcommit & push
# 2. MCP履歴をmcp-configリポジトリに記録
# 3. README.mdを自動更新してpush

FILE="$1"
MCP_REPO="$HOME/.claude/mcp-config"
HISTORY_FILE="$MCP_REPO/mcp-history.json"

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

  local mcp_file="$FILE"
  [ ! -f "$mcp_file" ] && return 0

  local project_dir=$(dirname "$mcp_file")
  local project_name=$(basename "$project_dir")
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
    scope: mcpPath.includes('.claude.json') ? 'global' : 'project',
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

  # プロジェクト別スナップショットも保存
  local projects_dir="$MCP_REPO/projects"
  mkdir -p "$projects_dir"

  local safe_name=$(echo "$project_name" | tr ' ' '-')
  local snapshot="$projects_dir/${safe_name}.mcp.json"
  cp "$mcp_file" "$snapshot"
}

# ---- 3. README.md 自動更新 ----
generate_readme() {
  local readme="$MCP_REPO/README.md"
  local history_w
  history_w=$(cygpath -w "$HISTORY_FILE" 2>/dev/null) || history_w="$HISTORY_FILE"

  local tmpjs=$(mktemp /tmp/gen-readme-XXXXXX.mjs)

  cat > "$tmpjs" << 'NODESCRIPT'
import { readFileSync, writeFileSync, readdirSync } from 'fs';
import { join, basename } from 'path';

const [readmePath, historyPath, projectsDir] = process.argv.slice(2);

let history = { entries: [] };
try { history = JSON.parse(readFileSync(historyPath, 'utf8')); } catch {}

// 全サーバーをプロジェクト別にグループ化
const byProject = {};
const allServers = new Map();

for (const e of history.entries) {
  const key = e.projectName || 'unknown';
  if (!byProject[key]) byProject[key] = {};
  byProject[key][e.serverName] = e;
  allServers.set(e.serverName, e);
}

// プロジェクトスナップショットからも収集
try {
  for (const f of readdirSync(projectsDir)) {
    if (!f.endsWith('.mcp.json')) continue;
    const projName = f.replace('.mcp.json', '');
    const cfg = JSON.parse(readFileSync(join(projectsDir, f), 'utf8'));
    const servers = cfg.mcpServers || cfg;
    if (!byProject[projName]) byProject[projName] = {};
    for (const [name, config] of Object.entries(servers)) {
      if (!byProject[projName][name]) {
        byProject[projName][name] = {
          serverName: name,
          config,
          meta: {
            serverType: config.type || (config.command ? 'stdio' : 'unknown'),
            command: config.command || '',
          }
        };
      }
      if (!allServers.has(name)) {
        allServers.set(name, byProject[projName][name]);
      }
    }
  }
} catch {}

let md = `# MCP Config

Claude Code で使用する MCP サーバーの設定管理リポジトリ。

## MCPサーバー一覧

| サーバー | タイプ | コマンド/URL | 使用プロジェクト |
|---------|--------|------------|----------------|
`;

for (const [name, e] of allServers) {
  const type = e.meta?.serverType || 'unknown';
  let conn = e.meta?.command || '';
  if (e.meta?.url) conn = e.meta.url;
  if (e.meta?.packageName) conn += ' ' + e.meta.packageName;
  const projects = Object.entries(byProject)
    .filter(([_, servers]) => servers[name])
    .map(([p]) => p)
    .join(', ');
  md += `| **${name}** | ${type} | \`${conn.trim()}\` | ${projects} |\n`;
}

md += `
## プロジェクト別設定

`;

for (const [projName, servers] of Object.entries(byProject)) {
  md += `### ${projName}\n\n`;
  md += `| サーバー | 説明 |\n`;
  md += `|---------|------|\n`;
  for (const [name, e] of Object.entries(servers)) {
    let desc = '';
    if (e.meta?.packageName) desc = e.meta.packageName;
    else if (e.meta?.url) desc = e.meta.url;
    else if (e.meta?.command) desc = e.meta.command;
    if (e.meta?.requiredEnvVars?.length > 0) {
      desc += ' (env: ' + e.meta.requiredEnvVars.join(', ') + ')';
    }
    md += `| ${name} | ${desc} |\n`;
  }
  md += '\n';
}

md += `## セットアップ

### 前提条件

- [uv](https://docs.astral.sh/uv/) (\`uvx\` コマンド用、Serena に必要)
- [GitHub CLI](https://cli.github.com/) (\`gh\` コマンド)
- [Node.js](https://nodejs.org/) (\`npx\` コマンド)

### 使い方

1. \`projects/\` 配下のプロジェクト別設定を参照
2. \`.mcp.json.example\` をコピーして \`.mcp.json\` を作成
3. トークン等を自分の環境に合わせて書き換え

\`\`\`bash
cp .mcp.json.example /path/to/your/project/.mcp.json
\`\`\`

## クラウドMCP（claude.ai管理）

以下はclaude.ai側で管理されるため、このリポジトリには含まれません：
- Figma MCP
- Google Calendar MCP
- Canva MCP

---

*自動生成 by sync-mcp.sh*
`;

writeFileSync(readmePath, md);
NODESCRIPT

  local readme_w projects_w
  readme_w=$(cygpath -w "$readme" 2>/dev/null) || readme_w="$readme"
  projects_w=$(cygpath -w "$MCP_REPO/projects" 2>/dev/null) || projects_w="$MCP_REPO/projects"

  node "$tmpjs" "$readme_w" "$history_w" "$projects_w" 2>/dev/null
  rm -f "$tmpjs"
}

# ---- 4. mcp-config リポジトリに commit & push ----
push_mcp_repo() {
  cd "$MCP_REPO" || return 0
  git add -A
  if ! git diff --cached --quiet; then
    local project_name=$(basename "$(dirname "$FILE")")
    git commit -m "MCP設定更新: $project_name"
    git push origin master 2>/dev/null || git push origin main 2>/dev/null
  fi
}

# ---- メイン ----
sync_project_repo
update_mcp_history
generate_readme
push_mcp_repo
