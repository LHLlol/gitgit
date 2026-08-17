# Gitgit 本地 Git 连接器

Gitgit 的 GitHub Pages 版本是浏览器界面。浏览器不能执行 `/usr/bin/git`、打开系统文件夹选择器，也不能复用 macOS 的 SSH/Keychain 凭据。这个可选本地组件只负责补足这些能力边界。

## 环境要求

- macOS
- Node.js 18+
- `/usr/bin/git` 可用

## 启动

From the repository root:

```bash
node docs/bridge/server.mjs
```

连接器只监听 `http://127.0.0.1:4387`。打开已部署的 Gitgit 页面，进入“设置”，保留默认连接器地址，然后点击“测试并保存”。

连接器不依赖 npm，也不会保存凭据。Git 参数通过数组传给 `child_process.spawn`，不会拼接成 Shell 字符串。

## 接口

- `GET /health` — 检查连接状态。
- `POST /pick` — 打开 macOS 系统文件夹选择器。
- `POST /inspect` — 读取仓库根目录、分支、远程、用户、状态、ahead/behind 和冲突状态。
- `POST /sync` — 执行安全的 `add → commit → fetch → pull --rebase → push` 流程，并最多重试一次推送。
- `POST /remote` — 添加用户明确指定的远程仓库。
- `POST /gitignore` — 用户明确点击后，将 `.DS_Store` 加入 `.gitignore`。
- `POST /abort-rebase` — 只在用户明确确认后中止变基。

连接器不会提供 reset、clean、force-push、Token 保存或仓库删除能力。
