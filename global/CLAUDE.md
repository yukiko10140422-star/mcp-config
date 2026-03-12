# Global Rules

## 言語
- ユーザーとのやりとりは常に日本語で行う
- コミットメッセージも日本語で書く

## セッション管理
- セッション開始時: プロジェクトの CLAUDE.md を読み、ルール・進捗・前回の状態を確認する
- セッション終了時: CLAUDE.md や進捗ドキュメントに指示があれば更新してから終了する

## Git ワークフロー
- commit 前にビルド確認（`npx next build` 等）を行い、エラーがないことを確認する
- commit 後は push まで自動で行う（毎回確認不要）
- バージョン変更を伴う commit 時は `gh release create` で GitHub Release を作成する

## 安全ルール
- .env ファイルは絶対にコミットしない
- ファイル削除や破壊的操作は事前に確認を取る

## MCP サーバー

設定ファイル: `~/.claude.json`（`mcpServers` セクション）
環境変数が未設定のサーバーは接続時にエラーになるため、初回利用時にオーナーへ確認すること。

### グローバル（全プロジェクト共通）
| サーバー | 用途 | 備考 |
|---------|------|------|
| serena | コード解析・ナビゲーション | `uvx --from git+https://github.com/oraios/serena` |
| github | GitHub操作 | `gh mcp`（`shuymn/gh-mcp` 拡張） |
| context7 | ライブラリドキュメント検索 | |
| playwright | ブラウザ自動操作・テスト | |
| supabase | Supabase操作（HTTP型） | 初回ブラウザ認証が必要 |
| ebay-mcp | eBay操作（フル機能） | 環境変数要設定 |
| ebay-public-api | eBay公開API | 環境変数要設定 |
| vercel | Vercel操作 | プロジェクトごとにトークン設定推奨 |

### プロジェクト別設定の方法
Vercel等、プロジェクト固有のトークンが必要なサーバーは各プロジェクトの `.claude/.mcp.json` に設定する。
グローバルは未接続のまま残し、プロジェクト単位で上書き可能。

### 要環境変数（初回接続時にオーナーへ値を確認する）
| サーバー | 必要な環境変数 |
|---------|--------------|
| vercel | `VERCEL_ACCESS_TOKEN`（プロジェクトごとに設定推奨） |
| ebay-public-api | `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET` |
| ebay-mcp | `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_DEV_ID`, `EBAY_REDIRECT_URI` |
