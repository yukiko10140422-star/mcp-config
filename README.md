# MCP Config

Claude Code で使用する MCP サーバーの設定管理リポジトリ。

## MCPサーバー一覧

| サーバー | タイプ | コマンド/URL | 使用プロジェクト |
|---------|--------|------------|----------------|
| **serena** | stdio | `uvx start-mcp-server` | projectcontact |
| **github** | stdio | `gh mcp-server` | projectcontact |
| **context7** | stdio | `npx @upstash/context7-mcp` | projectcontact |
| **supabase** | stdio | `npx @supabase/mcp-server-supabase` | projectcontact |

## プロジェクト別設定

### projectcontact

| サーバー | 説明 |
|---------|------|
| serena | start-mcp-server |
| github | mcp-server |
| context7 | @upstash/context7-mcp (env: CONTEXT7_API_KEY) |
| supabase | @supabase/mcp-server-supabase |

## セットアップ

### 前提条件

- [uv](https://docs.astral.sh/uv/) (`uvx` コマンド用、Serena に必要)
- [GitHub CLI](https://cli.github.com/) (`gh` コマンド)
- [Node.js](https://nodejs.org/) (`npx` コマンド)

### 使い方

1. `projects/` 配下のプロジェクト別設定を参照
2. `.mcp.json.example` をコピーして `.mcp.json` を作成
3. トークン等を自分の環境に合わせて書き換え

```bash
cp .mcp.json.example /path/to/your/project/.mcp.json
```

## クラウドMCP（claude.ai管理）

以下はclaude.ai側で管理されるため、このリポジトリには含まれません：
- Figma MCP
- Google Calendar MCP
- Canva MCP

---

*自動生成 by sync-mcp.sh*
