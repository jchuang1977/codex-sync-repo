---
name: codex-notebooklm
description: Codex 連接 NotebookLM MCP。說「連接 NotebookLM」時載入。
---

# 連接 NotebookLM（Codex 版）

1. `pip install notebooklm-mcp-cli` 或 `uv tool install notebooklm-mcp-cli`
2. `nlm login`（瀏覽器 OAuth）
3. 註冊 MCP：`codex mcp add notebooklm -- nlm mcp`
   或手動編輯 `~/.codex/config.toml`：
```toml
[mcp_servers.notebooklm]
command = "nlm"
args = ["mcp"]
```
4. 重啟 Codex 後驗證：列出筆記本

回報：nlm 版本、登入狀態、MCP 設定、測試結果。
