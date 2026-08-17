# Gitgit 网页版

这里是 Gitgit 的 GitHub Pages 网页版。它由无依赖的 HTML、CSS 和 JavaScript 构成，可以直接从 `/docs` 文件夹部署到 GitHub Pages。

## 使用 GitHub Pages 部署

1. 将仓库推送到 GitHub。
2. 打开 **Settings → Pages**。
3. 将来源设置为当前分支和 `/docs` 文件夹。
4. 打开生成的 Pages 地址。

如果需要执行真实的本地 Git 操作，请在仓库根目录运行可选连接器：

```bash
node docs/bridge/server.mjs
```

然后在 Gitgit 的 **设置** 中连接它。没有连接器时，网页会保持浏览器预览模式：可以列出拖入文件夹中的文件，但不会伪称提交或推送已经完成。
