# MCP Config

Claude Code で使用する MCP サーバーの設定管理リポジトリ。

## グローバルMCPサーバー

`~/.claude/.mcp.json` で管理されるサーバー。全プロジェクトで利用可能。

### 設定不要（そのまま使える）

| サーバー | タイプ | コマンド/URL |
|---------|--------|------------|
| **serena** | stdio | `uvx serena-cli` |
| **github** | stdio | `gh` |
| **context7** | stdio | `npx @upstash/context7-mcp` |
| **playwright** | stdio | `npx @playwright/mcp@latest` |
| **supabase** | http | `https://mcp.supabase.com/mcp` |

### 要環境変数（初回接続時に値を設定する）

| サーバー | タイプ | 必要な環境変数 |
|---------|--------|--------------|
| **vercel** | stdio | `VERCEL_ACCESS_TOKEN` |
| **ebay-public-api** | stdio | `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET` |
| **ebay-mcp** | stdio | `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_DEV_ID`, `EBAY_REDIRECT_URI` |

## プロジェクト別MCPサーバー

| サーバー | タイプ | コマンド/URL | 使用プロジェクト |
|---------|--------|------------|----------------|
| **serena** | stdio | `uvx start-mcp-server` | projectcontact |
| **github** | stdio | `gh` | projectcontact, ebay-dashboard |
| **context7** | stdio | `npx @upstash/context7-mcp` | projectcontact, ebay-dashboard |
| **supabase** | http | `` | projectcontact, ebay-dashboard |
| **playwright** | stdio | `npx @playwright/mcp` | ebay-dashboard |
| **vercel** | stdio | `npx @vercel/mcp` | ebay-dashboard |

### projectcontact

| サーバー | 説明 |
|---------|------|
| serena | start-mcp-server |
| github | mcp-server |
| context7 | @upstash/context7-mcp (env: CONTEXT7_API_KEY) |
| supabase | @supabase/mcp-server-supabase |

### ebay-dashboard

| サーバー | 説明 |
|---------|------|
| supabase |  |
| github | gh |
| context7 | @upstash/context7-mcp |
| playwright | @playwright/mcp |
| vercel | @vercel/mcp (env: VERCEL_ACCESS_TOKEN) |

## セットアップ

### 前提条件

- [uv](https://docs.astral.sh/uv/) (`uvx` コマンド用、Serena に必要)
- [GitHub CLI](https://cli.github.com/) (`gh` コマンド)
- [Node.js](https://nodejs.org/) (`npx` コマンド)

### 新マシンセットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/yukiko10140422-star/mcp-config.git ~/.claude/mcp-config

# 2. グローバル設定をデプロイ
cd ~/.claude/mcp-config
./scripts/sync-mcp.sh --deploy

# 3. 環境変数を設定（必要なサーバーのみ）
# VERCEL_ACCESS_TOKEN, EBAY_CLIENT_ID 等を設定
```

### 使い方

```bash
# プロジェクトの.mcp.json変更を同期
./scripts/sync-mcp.sh /path/to/project/.mcp.json

# グローバル設定を同期（~/.claude/ → リポジトリ）
./scripts/sync-mcp.sh --global

# グローバル設定をデプロイ（リポジトリ → ~/.claude/）
./scripts/sync-mcp.sh --deploy
```

## クラウドMCP（claude.ai管理）

以下はclaude.ai側で管理されるため、このリポジトリには含まれません：
- Figma MCP
- Google Calendar MCP
- Canva MCP

---

*自動生成 by sync-mcp.sh*
