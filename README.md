# MCP Config

Claude Code で使用する MCP サーバーの設定管理リポジトリ。

## 含まれるMCPサーバー

| サーバー | 説明 |
|---------|------|
| **serena** | LSPベースのセマンティックコード理解（シンボル検索・編集） |
| **github** | GitHub CLI 経由の GitHub 操作 |
| **supabase** | Supabase DB 直接アクセス |

## セットアップ

### 前提条件

- [uv](https://docs.astral.sh/uv/) (`uvx` コマンド用、Serena に必要)
- [GitHub CLI](https://cli.github.com/) (`gh` コマンド)
- [Node.js](https://nodejs.org/) (`npx` コマンド)

### 使い方

1. `.mcp.json.example` をコピーして `.mcp.json` を作成
2. トークン等を自分の環境に合わせて書き換え
3. プロジェクトルートに `.mcp.json` を配置

```bash
cp .mcp.json.example /path/to/your/project/.mcp.json
# トークンを編集
```

## クラウドMCP（claude.ai管理）

以下はclaude.ai側で管理されるため、このリポジトリには含まれません：
- Figma MCP
- Google Calendar MCP
- Canva MCP
