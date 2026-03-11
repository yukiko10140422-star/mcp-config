import { readFileSync, writeFileSync, readdirSync, existsSync } from 'fs';
import { join } from 'path';

const [readmePath, historyPath, projectsDir, globalDir] = process.argv.slice(2);

let history = { entries: [] };
try { history = JSON.parse(readFileSync(historyPath, 'utf8')); } catch {}

// グローバル設定を読み込み
let globalServers = {};
const globalMcpPath = join(globalDir, '.mcp.json');
if (existsSync(globalMcpPath)) {
  try {
    const globalConfig = JSON.parse(readFileSync(globalMcpPath, 'utf8'));
    globalServers = globalConfig.mcpServers || globalConfig;
  } catch {}
}

// 全サーバーをプロジェクト別にグループ化（globalを除外）
const byProject = {};
const allServers = new Map();

for (const e of history.entries) {
  if (e.scope === 'global') continue;
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

// グローバルサーバーを「設定不要」「要環境変数」に分類
const noEnvServers = [];
const envServers = [];

for (const [name, config] of Object.entries(globalServers)) {
  const configStr = JSON.stringify(config);
  const envMatches = [...configStr.matchAll(/\$\{([^}]+)\}/g)];
  const entry = { name, config, envVars: envMatches.map(m => m[1]) };
  if (envMatches.length > 0) {
    envServers.push(entry);
  } else {
    noEnvServers.push(entry);
  }
}

function getServerConn(config) {
  let conn = config.command || '';
  if (config.url) conn = config.url;
  if (config.args) {
    const pkg = config.args.find(a => a.startsWith('@') || (!a.startsWith('-') && !a.startsWith('--') && a.includes('-')));
    if (pkg) conn += ' ' + pkg;
  }
  return conn.trim();
}

let md = '# MCP Config\n\n';
md += 'Claude Code で使用する MCP サーバーの設定管理リポジトリ。\n\n';

// グローバルセクション
md += '## グローバルMCPサーバー\n\n';
md += '`~/.claude/.mcp.json` で管理されるサーバー。全プロジェクトで利用可能。\n\n';

md += '### 設定不要（そのまま使える）\n\n';
md += '| サーバー | タイプ | コマンド/URL |\n';
md += '|---------|--------|------------|\n';

for (const s of noEnvServers) {
  const type = s.config.type || (s.config.command ? 'stdio' : 'unknown');
  const conn = getServerConn(s.config);
  md += `| **${s.name}** | ${type} | \`${conn}\` |\n`;
}

md += '\n### 要環境変数（初回接続時に値を設定する）\n\n';
md += '| サーバー | タイプ | 必要な環境変数 |\n';
md += '|---------|--------|--------------|\n';

for (const s of envServers) {
  const type = s.config.type || (s.config.command ? 'stdio' : 'unknown');
  md += `| **${s.name}** | ${type} | \`${s.envVars.join('`, `')}\` |\n`;
}

// プロジェクト別設定
if (Object.keys(byProject).length > 0) {
  md += '\n## プロジェクト別MCPサーバー\n\n';
  md += '| サーバー | タイプ | コマンド/URL | 使用プロジェクト |\n';
  md += '|---------|--------|------------|----------------|\n';

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

  md += '\n';

  for (const [projName, servers] of Object.entries(byProject)) {
    md += `### ${projName}\n\n`;
    md += '| サーバー | 説明 |\n';
    md += '|---------|------|\n';
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
}

md += '## セットアップ\n\n';
md += '### 前提条件\n\n';
md += '- [uv](https://docs.astral.sh/uv/) (`uvx` コマンド用、Serena に必要)\n';
md += '- [GitHub CLI](https://cli.github.com/) (`gh` コマンド)\n';
md += '- [Node.js](https://nodejs.org/) (`npx` コマンド)\n\n';

md += '### 新マシンセットアップ\n\n';
md += '```bash\n';
md += '# 1. リポジトリをクローン\n';
md += 'git clone https://github.com/yukiko10140422-star/mcp-config.git ~/.claude/mcp-config\n\n';
md += '# 2. グローバル設定をデプロイ\n';
md += 'cd ~/.claude/mcp-config\n';
md += './scripts/sync-mcp.sh --deploy\n\n';
md += '# 3. 環境変数を設定（必要なサーバーのみ）\n';
md += '# VERCEL_ACCESS_TOKEN, EBAY_CLIENT_ID 等を設定\n';
md += '```\n\n';

md += '### 使い方\n\n';
md += '```bash\n';
md += '# プロジェクトの.mcp.json変更を同期\n';
md += './scripts/sync-mcp.sh /path/to/project/.mcp.json\n\n';
md += '# グローバル設定を同期（~/.claude/ → リポジトリ）\n';
md += './scripts/sync-mcp.sh --global\n\n';
md += '# グローバル設定をデプロイ（リポジトリ → ~/.claude/）\n';
md += './scripts/sync-mcp.sh --deploy\n';
md += '```\n\n';

md += '## クラウドMCP（claude.ai管理）\n\n';
md += '以下はclaude.ai側で管理されるため、このリポジトリには含まれません：\n';
md += '- Figma MCP\n';
md += '- Google Calendar MCP\n';
md += '- Canva MCP\n\n';
md += '---\n\n';
md += '*自動生成 by sync-mcp.sh*\n';

writeFileSync(readmePath, md);
