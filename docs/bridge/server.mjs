#!/usr/bin/env node

import http from "node:http";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";

const PORT = Number(process.env.PUSHDock_PORT || 4387);
const HOST = "127.0.0.1";
const GIT = process.env.GIT_BIN || "/usr/bin/git";
const LARGE_FILE_LIMIT = 95 * 1024 * 1024;

function redact(value = "") {
  return value.replace(/(https?:\/\/)[^@\s]+@/gi, "$1••••@");
}

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
  });
  res.end(body);
}

function friendlyError(command, result, extra = {}) {
  const details = redact([result?.stdout, result?.stderr].filter(Boolean).join("\n").trim());
  const lower = details.toLowerCase();
  if (extra.code) return { code: extra.code, friendly: extra.friendly, recovery: extra.recovery, technical: details, conflictFiles: extra.conflictFiles || [], retryable: !!extra.retryable };
  if (lower.includes("not a git repository")) return { code: "not-repository", friendly: "这不是 Git 仓库。", recovery: "请选择包含 Git 仓库的文件夹。", technical: details };
  if (lower.includes("permission denied (publickey)") || lower.includes("authentication failed") || lower.includes("could not read username")) return { code: "authentication", friendly: "GitHub 身份验证失败。", recovery: "请在终端完成现有 SSH 或 HTTPS 身份验证，然后重试。", technical: details, retryable: true };
  if (lower.includes("could not resolve host") || lower.includes("network is unreachable") || lower.includes("failed to connect") || lower.includes("connection timed out")) return { code: "network", friendly: "网络连接不可用。", recovery: "本地提交是安全的，请检查网络后重试。", technical: details, retryable: true };
  if (lower.includes("non-fast-forward") || lower.includes("fetch first") || lower.includes("rejected")) return { code: "push-rejected", friendly: "远程变更需要先同步。", recovery: "Gitgit 会先 Fetch 并变基一次，然后重试推送。", technical: details, retryable: true };
  return { code: "process-failed", friendly: "Git 无法完成这次操作。", recovery: "打开执行日志查看技术细节。", technical: `$ git ${command}\n${details}` };
}

function runProcess(executable, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { cwd, env: process.env });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", reject);
    child.on("close", (status) => resolve({ status: status ?? -1, stdout, stderr }));
  });
}

async function runGit(cwd, args, { allowFailure = false } = {}) {
  let result;
  try { result = await runProcess(GIT, args, cwd); }
  catch (error) { throw { code: "git-unavailable", friendly: "这台 Mac 上没有可用的 Git。", recovery: "安装 Xcode Command Line Tools，然后重启连接器。", technical: error.message }; }
  if (result.status !== 0 && !allowFailure) throw friendlyError(args.join(" "), result);
  return result;
}

async function validateRepository(inputPath) {
  const candidate = path.resolve(String(inputPath || ""));
  const result = await runGit(candidate, ["rev-parse", "--is-inside-work-tree"]);
  if (result.stdout.trim() !== "true") throw { code: "not-repository", friendly: "这不是 Git 仓库。", recovery: "请选择包含 Git 仓库的文件夹。", technical: redact(result.stderr) };
  const rootResult = await runGit(candidate, ["rev-parse", "--show-toplevel"]);
  return path.resolve(rootResult.stdout.trim());
}

async function gitDirectory(root) {
  const dotGit = path.join(root, ".git");
  const info = await fs.lstat(dotGit).catch(() => null);
  if (!info) return null;
  if (info.isDirectory()) return dotGit;
  const contents = await fs.readFile(dotGit, "utf8").catch(() => "");
  if (!contents.startsWith("gitdir:")) return null;
  return path.resolve(root, contents.slice(7).trim());
}

async function repositoryState(root) {
  const result = await runGit(root, ["status", "--porcelain=v2", "-b"]);
  const lines = result.stdout.split(/\r?\n/).filter(Boolean);
  let branch = null;
  let upstream = null;
  let ahead = 0;
  let behind = 0;
  const changes = [];
  for (const line of lines) {
    if (line.startsWith("# branch.head ")) { const value = line.slice(14); branch = value === "(detached)" ? null : value; continue; }
    if (line.startsWith("# branch.upstream ")) { upstream = line.slice("# branch.upstream ".length); continue; }
    if (line.startsWith("# branch.ab ")) {
      for (const value of line.slice(12).split(" ")) { if (value.startsWith("+")) ahead = Number(value.slice(1)) || 0; if (value.startsWith("-")) behind = Number(value.slice(1)) || 0; }
      continue;
    }
    if (line.startsWith("#")) continue;
    if (line.startsWith("? ")) { const relativePath = line.slice(2); changes.push({ file: path.basename(relativePath), relativePath, status: "untracked" }); continue; }
    if (line.startsWith("u ")) { const relativePath = line.split(" ").at(-1); changes.push({ file: path.basename(relativePath), relativePath, status: "conflicted" }); continue; }
    const parts = line.split(" ");
    if (parts.length < 9) continue;
    const xy = parts[1];
    const relativePath = parts.slice(8).join(" ").split("\t")[0];
    const status = xy.includes("R") ? "renamed" : xy.includes("D") ? "deleted" : xy.includes("A") ? "added" : "modified";
    changes.push({ file: path.basename(relativePath), relativePath, status });
  }
  const gitDir = await gitDirectory(root);
  const isRebasing = !!gitDir && (await exists(path.join(gitDir, "rebase-merge")) || await exists(path.join(gitDir, "rebase-apply")));
  const isMerging = !!gitDir && await exists(path.join(gitDir, "MERGE_HEAD"));
  return { branch, upstream, ahead, behind, isClean: changes.length === 0, isDetachedHead: !branch, isRebasing, isMerging, changes };
}

async function exists(file) { return !!(await fs.stat(file).catch(() => null)); }

async function snapshot(root) {
  const status = await repositoryState(root);
  const remotes = (await runGit(root, ["remote"])).stdout.split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
  const remoteName = remotes.includes("origin") ? "origin" : remotes[0] || null;
  let remoteURL = null;
  if (remoteName) remoteURL = (await runGit(root, ["remote", "get-url", remoteName])).stdout.trim();
  const userName = (await runGit(root, ["config", "--get", "user.name"], { allowFailure: true })).stdout.trim();
  const userEmail = (await runGit(root, ["config", "--get", "user.email"], { allowFailure: true })).stdout.trim();
  const repository = { id: root, name: path.basename(root), path: root, remoteURL, remoteName, branch: status.branch, gitUserName: userName || null, gitUserEmail: userEmail || null, lastPush: null, lastCommitMessage: null };
  return { repository, status };
}

async function conflictFiles(root) {
  const result = await runGit(root, ["diff", "--name-only", "--diff-filter=U"], { allowFailure: true });
  return result.stdout.split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
}

async function ensureNoBlockedState(root, status) {
  if (status.isDetachedHead) throw { code: "detached-head", friendly: "当前仓库处于 Detached HEAD 状态。", recovery: "请先切换到一个分支，再进行推送。", technical: "git branch --show-current returned no branch." };
  if (status.isRebasing) throw { code: "rebase-in-progress", friendly: "当前已有变基操作正在进行。", recovery: "请解决冲突或中止变基，然后刷新 Gitgit。", technical: "rebase metadata exists in .git" };
  if (status.isMerging) throw { code: "merge-in-progress", friendly: "当前已有合并操作正在进行。", recovery: "请在本机 Git 环境中完成或中止合并，然后刷新 Gitgit。", technical: "MERGE_HEAD exists in .git" };
}

async function checkLargeFiles(root, changes) {
  const found = [];
  for (const change of changes) {
    if (change.status === "deleted") continue;
    const info = await fs.stat(path.join(root, change.relativePath)).catch(() => null);
    if (info?.size > LARGE_FILE_LIMIT) found.push(`${change.relativePath} (${Math.round(info.size / 1048576)} MB)`);
  }
  if (found.length) throw { code: "large-file", friendly: `检测到大文件：${found.join(", ")}。`, recovery: "请将它从提交中移除，或使用 Git LFS。", technical: "GitHub may reject files larger than 100 MB." };
}

async function syncRepository({ path: inputPath, message, fetchBeforeSync = true }) {
  const root = await validateRepository(inputPath);
  let current = await snapshot(root);
  await ensureNoBlockedState(root, current.status);
  if (!current.repository.remoteName || !current.repository.remoteURL) throw { code: "no-remote", friendly: "尚未配置远程仓库。", recovery: "请先添加远程仓库，再进行推送。", technical: "git remote returned no usable remote." };
  if (!String(message || "").trim()) throw { code: "invalid-commit", friendly: "同步前请输入提交信息。", recovery: "输入简短的提交说明后重试。", technical: "Empty commit messages are not allowed." };
  await checkLargeFiles(root, current.status.changes);
  const steps = ["Repository checked"];
  const staged = await runGit(root, ["add", "-A"]);
  const stagedCheck = await runGit(root, ["diff", "--cached", "--quiet"], { allowFailure: true });
  let didCreateCommit = false;
  let commitHash = null;
  if (stagedCheck.status !== 0) {
    await runGit(root, ["commit", "-m", String(message).trim()]);
    commitHash = (await runGit(root, ["rev-parse", "HEAD"])).stdout.trim();
    didCreateCommit = true;
    steps.push(`Created local commit ${commitHash.slice(0, 7)}`);
  } else steps.push("Working tree clean; no empty commit created");
  if (fetchBeforeSync) { await runGit(root, ["fetch", "--prune", current.repository.remoteName]); steps.push(`Fetched ${current.repository.remoteName}`); }
  current = await snapshot(root);
  if (current.status.behind > 0) {
    try { await runGit(root, ["pull", "--rebase", current.repository.remoteName, current.status.branch]); steps.push("Rebased local commits"); }
    catch (error) {
      const files = await conflictFiles(root);
      if (files.length || (await repositoryState(root)).isRebasing) throw { code: "rebase-conflict", friendly: "检测到变基冲突。", recovery: "解决冲突文件后刷新仓库。", technical: error.technical || "git pull --rebase reported a conflict.", conflictFiles: files };
      throw error;
    }
  }
  current = await snapshot(root);
  if (!(didCreateCommit || current.status.ahead > 0)) return { ...current, didCreateCommit, didPush: false, commitHash, steps, duration: 0 };
  const pushArgs = current.status.upstream ? ["push", current.repository.remoteName, current.status.branch] : ["push", "-u", current.repository.remoteName, current.status.branch];
  let didPush = false;
  let lastError = null;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try { await runGit(root, pushArgs); didPush = true; steps.push(attempt ? "Push completed after safe retry" : "Push completed"); break; }
    catch (error) {
      lastError = error;
      if (attempt === 1 || error.code !== "push-rejected") throw error;
      await runGit(root, ["fetch", "--prune", current.repository.remoteName]);
      current = await snapshot(root);
      if (current.status.behind > 0) {
        try { await runGit(root, ["pull", "--rebase", current.repository.remoteName, current.status.branch]); }
        catch (rebaseError) { const files = await conflictFiles(root); throw { code: "rebase-conflict", friendly: "检测到变基冲突。", recovery: "解决冲突文件后刷新仓库。", technical: rebaseError.technical || "Retry rebase reported a conflict.", conflictFiles: files }; }
      }
    }
  }
  if (!didPush && lastError) throw lastError;
  return { ...(await snapshot(root)), didCreateCommit, didPush, commitHash, steps, duration: 0 };
}

async function pickFolder() {
  const result = await runProcess("/usr/bin/osascript", ["-e", 'POSIX path of (choose folder with prompt "Choose a Git repository")'], process.cwd());
  if (result.status !== 0) return { cancelled: true };
  return { path: result.stdout.trim(), cancelled: false };
}

async function addDSStore(root) {
  const file = path.join(root, ".gitignore");
  const current = await fs.readFile(file, "utf8").catch(() => "");
  const entries = current.split(/\r?\n/).map((item) => item.trim());
  if (!entries.includes(".DS_Store")) await fs.writeFile(file, `${current}${current && !current.endsWith("\n") ? "\n" : ""}.DS_Store\n`, "utf8");
}

async function readBody(req) {
  let body = "";
  for await (const chunk of req) body += chunk;
  return body ? JSON.parse(body) : {};
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") return json(res, 204, {});
  try {
    const body = req.method === "POST" ? await readBody(req) : {};
    if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true, service: "Gitgit 本地 Git 连接器", version: "1.0" });
    if (req.method === "POST" && req.url === "/pick") return json(res, 200, await pickFolder());
    if (req.method === "POST" && req.url === "/inspect") { const root = await validateRepository(body.path); return json(res, 200, await snapshot(root)); }
    if (req.method === "POST" && req.url === "/sync") return json(res, 200, await syncRepository(body));
    if (req.method === "POST" && req.url === "/remote") { const root = await validateRepository(body.path); await runGit(root, ["remote", "add", body.name || "origin", body.url]); return json(res, 200, { ok: true }); }
    if (req.method === "POST" && req.url === "/gitignore") { const root = await validateRepository(body.path); await addDSStore(root); return json(res, 200, { ok: true }); }
    if (req.method === "POST" && req.url === "/abort-rebase") { const root = await validateRepository(body.path); await runGit(root, ["rebase", "--abort"]); return json(res, 200, { ok: true }); }
    return json(res, 404, { error: { code: "not-found", friendly: "未找到连接器接口。" } });
  } catch (error) {
    const payload = error?.friendly ? error : { friendly: error.message || "本地 Git 连接器执行失败。", technical: error.stack || String(error) };
    return json(res, 400, { error: payload });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Gitgit 本地 Git 连接器运行于 http://${HOST}:${PORT}`);
});
