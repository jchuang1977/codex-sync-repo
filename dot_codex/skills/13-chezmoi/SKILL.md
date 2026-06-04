---
name: codex-chezmoi
description: Codex 用 chezmoi 同步設定到多台電腦。說「同步 Codex 設定」「chezmoi」時載入。
---

# 用 chezmoi 同步 Codex 設定

## 安裝 chezmoi
Windows：`winget install twpayne.chezmoi`
其他：https://chezmoi.io/install/

## 納管安全設定
```bash
chezmoi add ~/.codex/AGENTS.md
chezmoi add ~/.codex/skills/xxx
```

⚠️ 不要同步 entire `~/.codex/`（auth.json、logs、state 會洩漏）

## 推送
```bash
chezmoi cd
git status --short
git add dot_codex/AGENTS.md dot_codex/skills/<本次修改的skill>
git commit -m "..."
git push
```

## 另一台電腦同步
```bash
chezmoi init <repo-url>
chezmoi apply
# 之後：chezmoi update
```

另一台仍需手動：Codex 登入、Obsidian 路徑、GitHub 登入。
