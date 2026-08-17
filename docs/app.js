const STORAGE = {
  bridgeUrl: "pushdock.bridgeUrl",
  repositories: "pushdock.repositories",
  activity: "pushdock.activity",
  settings: "pushdock.settings"
};

const defaults = {
  bridgeUrl: "http://127.0.0.1:4387",
  fetchBeforeSync: true,
  confirmBeforePush: true,
  commitTemplate: "更新 {repository}"
};

const state = {
  view: "dashboard",
  bridgeUrl: localStorage.getItem(STORAGE.bridgeUrl) || defaults.bridgeUrl,
  bridgeOnline: false,
  repositories: readJSON(STORAGE.repositories, []),
  activity: readJSON(STORAGE.activity, []),
  settings: { ...defaults, ...readJSON(STORAGE.settings, {}) },
  selectedId: null,
  repository: null,
  status: null,
  preview: null,
  logs: [],
  operation: "idle",
  syncing: false,
  retryPushAvailable: false,
  conflictFiles: [],
  commitMessage: ""
};

if (state.settings.commitTemplate === "Update {repository}") state.settings.commitTemplate = defaults.commitTemplate;

const $ = (id) => document.getElementById(id);
const all = (selector) => [...document.querySelectorAll(selector)];

function readJSON(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key) || "null") ?? fallback; } catch { return fallback; }
}

function writeJSON(key, value) { localStorage.setItem(key, JSON.stringify(value)); }

function escapeHTML(value = "") {
  return String(value).replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char]));
}

function friendlyTime(value) {
  if (!value) return "尚未记录";
  const date = new Date(value);
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return "刚刚";
  if (seconds < 3600) return `${Math.round(seconds / 60)} 分钟前`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} 小时前`;
  return date.toLocaleDateString("zh-CN", { month: "short", day: "numeric" });
}

function compactPath(value) {
  if (!value) return "—";
  if (value.length < 52) return value;
  return `${value.slice(0, 22)}…${value.slice(-26)}`;
}

function addLog(title, detail = "", kind = "") {
  state.logs.push({ time: new Date(), title, detail, kind });
  renderLogs();
}

function showToast(title, message, kind = "") {
  const toast = document.createElement("div");
  toast.className = "toast";
  toast.innerHTML = `<strong>${escapeHTML(title)}</strong><p>${escapeHTML(message)}</p>`;
  $("toastStack").append(toast);
  setTimeout(() => toast.remove(), 5200);
}

function friendlyError(error) {
  if (error?.friendly) return error;
  return { friendly: error?.message || "网页无法连接本地 Git 连接器。", recovery: "启动连接器后重试。", technical: error?.stack || "" };
}

async function bridgeRequest(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeout || 15000);
  try {
    const response = await fetch(`${state.bridgeUrl}${path}`, {
      ...options,
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
      signal: controller.signal
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw { ...data.error, status: response.status };
    return data;
  } catch (error) {
    if (error.name === "AbortError") throw { friendly: "本地 Git 连接器响应超时。", recovery: "请确认连接器正在 Mac 上运行。", code: "timeout" };
    throw friendlyError(error);
  } finally {
    clearTimeout(timeout);
  }
}

async function checkBridge(showFeedback = false) {
  try {
    await bridgeRequest("/health", { timeout: 2500 });
    state.bridgeOnline = true;
    $("bridgeUrl").value = state.bridgeUrl;
    if (showFeedback) showToast("连接器已连接", "现在可以执行真实的本地 Git 操作。", "success");
  } catch {
    state.bridgeOnline = false;
    if (showFeedback) showToast("连接器未连接", "网页仍可使用浏览器预览模式。", "error");
  }
  renderBridgeState();
  render();
  if (state.bridgeOnline && state.repository && !state.preview && !state.status) inspectPath(state.repository.path);
}

async function chooseWithBridge() {
  if (!state.bridgeOnline) {
    showToast("请连接本地 Git 连接器", "静态 GitHub Pages 网页无法自行打开系统文件夹选择器。", "error");
    openView("settings");
    return;
  }
  try {
    addLog("正在打开系统文件夹选择器…");
    const result = await bridgeRequest("/pick", { method: "POST", body: "{}" });
    if (result.cancelled) return;
    await inspectPath(result.path);
  } catch (error) {
    handleOperationError(error, "无法选择仓库");
  }
}

async function inspectPath(path) {
  if (!path) return;
  state.preview = null;
  state.status = null;
  state.operation = "checking";
  render();
  try {
    addLog("正在检查仓库…");
    const result = await bridgeRequest("/inspect", { method: "POST", body: JSON.stringify({ path }) });
    setRepository(result.repository, result.status);
    state.operation = "idle";
    addLog("已识别 Git 仓库", result.repository.path, "success");
  } catch (error) {
    state.operation = "error";
    handleOperationError(error, "这不是 Git 仓库");
  }
  render();
}

function setRepository(repository, status) {
  state.repository = repository;
  state.status = status;
  state.selectedId = repository.id || repository.path;
  const existing = state.repositories.findIndex((item) => item.id === state.selectedId || item.path === repository.path);
  const saved = { ...repository, id: existing >= 0 ? state.repositories[existing].id : state.selectedId, lastOpened: new Date().toISOString() };
  state.selectedId = saved.id;
  state.repository = saved;
  state.commitMessage = saved.lastCommitMessage || state.settings.commitTemplate.replace("{repository}", saved.name);
  if (existing >= 0) state.repositories[existing] = saved;
  else state.repositories.unshift(saved);
  writeJSON(STORAGE.repositories, state.repositories.slice(0, 20));
}

async function selectRepository(repository) {
  state.selectedId = repository.id;
  state.repository = repository;
  state.preview = null;
  state.status = null;
  state.commitMessage = repository.lastCommitMessage || state.settings.commitTemplate.replace("{repository}", repository.name);
  state.operation = "checking";
  render();
  if (state.bridgeOnline) await inspectPath(repository.path);
  else {
    state.operation = "idle";
    showToast("连接器未连接", "连接本地 Git 连接器后，才能检查这个已保存的项目。", "error");
    render();
  }
}

function handlePreviewFiles(fileList) {
  const files = [...fileList].filter((file) => !file.webkitRelativePath.includes("/.git/"));
  if (!files.length) return;
  const firstPath = files[0].webkitRelativePath || files[0].name;
  const rootName = firstPath.split("/")[0] || files[0].name;
  state.preview = { name: rootName, count: files.length, files: files.slice(0, 120).map((file) => ({ name: file.name, path: file.webkitRelativePath || file.name, size: file.size })) };
  state.repository = { id: `preview:${rootName}`, name: rootName, path: "浏览器文件夹预览", branch: null };
  state.status = null;
  state.selectedId = state.repository.id;
  state.operation = "idle";
  addLog("浏览器文件夹预览已准备好", `网页可以读取 ${files.length} 个文件。`);
  render();
}

function statusSummary() {
  if (!state.repository) return { title: "不打开终端，直接同步项目。", subtitle: "选择一个本地 Git 仓库，查看真实分支、文件变更和远程状态。", eyebrow: "本地工作区" };
  if (state.preview) return { title: "当前仅为文件夹预览。", subtitle: "浏览器可以列出文件，但真实 Git 信息需要本地连接器。", eyebrow: "浏览器预览" };
  if (state.operation === "conflict") return { title: "需要处理冲突。", subtitle: "请手动解决冲突文件。Gitgit 已在推送前安全停止。", eyebrow: "变基冲突" };
  if (state.syncing) return { title: "同步正在进行。", subtitle: "本地 Git 连接器正在 Mac 上执行安全 Git 流程。", eyebrow: "本地操作" };
  if (state.status?.isDetachedHead) return { title: "当前处于 Detached HEAD。", subtitle: "请先切换到一个分支，再进行推送。", eyebrow: "需要分支" };
  if (state.status?.behind > 0) return { title: "检测到远程变更。", subtitle: "远程分支领先，Gitgit 会先变基本地提交，再进行推送。", eyebrow: "远程领先" };
  if (state.status?.changes?.length) return { title: "检测到本地变更。", subtitle: "检查工作区，然后将这些变更安全同步到远程仓库。", eyebrow: "工作区有变更" };
  if (state.status?.ahead > 0) return { title: "本地提交等待推送。", subtitle: "本地分支领先远程分支，可以直接推送。", eyebrow: "本地领先" };
  return { title: "当前已是最新状态。", subtitle: "工作区和远程跟踪状态都很干净。", eyebrow: "仓库已准备好" };
}

function syncValue() {
  if (!state.status) return "—";
  if (!state.status.ahead && !state.status.behind) return "已是最新";
  return [state.status.ahead ? `${state.status.ahead} 个领先` : "", state.status.behind ? `${state.status.behind} 个落后` : ""].filter(Boolean).join(" · ");
}

function render() {
  const summary = statusSummary();
  $("statusEyebrow").textContent = summary.eyebrow;
  $("dashboardTitle").innerHTML = summary.title === "不打开终端，直接同步项目。" ? "不打开终端，<br /><i>直接同步项目。</i>" : escapeHTML(summary.title);
  $("dashboardSubtitle").textContent = summary.subtitle;
  $("crumbRepository").textContent = state.repository?.name || "工作区";
  $("crumbView").textContent = ({ dashboard: "仪表盘", activity: "活动记录", settings: "设置" })[state.view] || "仪表盘";
  $("syncButtonLabel").textContent = state.syncing ? "同步中…" : state.retryPushAvailable ? "重试推送" : "同步并推送";
  if (document.activeElement !== $("commitInput")) $("commitInput").value = commitMessage();
  $("syncButton").disabled = state.syncing || !state.repository || !!state.preview || !state.bridgeOnline || state.status?.isDetachedHead || state.operation === "conflict";
  $("chooseButton").textContent = state.bridgeOnline ? "通过连接器选择" : "选择文件夹预览";
  $("statRepository").textContent = state.repository?.name || "—";
  $("statPath").textContent = state.repository?.path ? compactPath(state.repository.path) : "尚未选择文件夹";
  $("statBranch").textContent = state.status?.branch || (state.preview ? "预览" : "—");
  $("statChanges").textContent = state.preview ? `${state.preview.count} 个文件` : state.status ? `${state.status.changes.length} 个文件` : "—";
  $("statChangeHint").textContent = state.preview ? "浏览器可见文件" : "工作区";
  $("statRemote").textContent = state.repository?.remoteName || (state.preview ? "需要连接器" : "—");
  $("statSync").textContent = state.preview ? "不是 Git 状态" : syncValue();
  $("factRemote").textContent = displayRemote(state.repository?.remoteURL);
  $("factPath").textContent = state.repository?.path || "—";
  $("factCommit").textContent = state.repository?.lastCommitMessage || "暂无 Gitgit 记录";
  $("factSync").textContent = state.repository?.lastPush ? friendlyTime(state.repository.lastPush) : "尚未同步";
  $("addRemoteButton").classList.toggle("is-hidden", !state.repository || !!state.repository.remoteURL || !!state.preview);
  $("previewCallout").classList.toggle("is-hidden", !state.preview && state.bridgeOnline);
  $("conflictPanel").classList.toggle("is-hidden", state.operation !== "conflict");
  $("conflictFiles").innerHTML = state.conflictFiles.length ? state.conflictFiles.map((file) => `<span>${escapeHTML(file)}</span>`).join("") : "<span>请查看执行日志中的冲突文件</span>";
  renderRunway();
  renderChanges();
  renderActivity();
  renderRepoList();
  renderBridgeState();
  renderViews();
  renderDsStoreNote();
  renderUser();
}

function displayRemote(value) {
  if (!value) return state.preview ? "预览模式不可用" : "未配置远程仓库";
  let clean = value.replace(/^https?:\/\/[^@]+@/i, "https://••••@");
  clean = clean.replace(/^git@/, "").replace(":", "/").replace(/^ssh:\/\//, "");
  return clean.replace(/\.git$/, "");
}

function renderViews() {
  $("dashboardView").classList.toggle("is-hidden", state.view !== "dashboard");
  $("activityView").classList.toggle("is-hidden", state.view !== "activity");
  $("settingsView").classList.toggle("is-hidden", state.view !== "settings");
  all(".nav-item").forEach((button) => button.classList.toggle("is-active", button.dataset.view === state.view));
}

function renderRepoList() {
  const list = $("repoList");
  if (!state.repositories.length) { list.innerHTML = `<div class="repo-empty">还没有保存的项目。<br />选择一个文件夹开始。</div>`; return; }
  list.innerHTML = state.repositories.map((repository) => {
    const selected = repository.id === state.selectedId;
    const warning = selected && state.status?.behind > 0;
    return `<button class="repo-item ${selected ? "is-selected" : ""}" data-repo-id="${escapeHTML(repository.id)}"><span class="repo-dot ${warning ? "is-warning" : ""}"></span><span><strong>${escapeHTML(repository.name)}</strong><small>${escapeHTML(repository.branch || "连接后查看")}</small></span><time>${friendlyTime(repository.lastOpened)}</time></button>`;
  }).join("");
  all("[data-repo-id]").forEach((button) => button.addEventListener("click", () => {
    const repository = state.repositories.find((item) => item.id === button.dataset.repoId);
    if (repository) selectRepository(repository);
  }));
}

function renderBridgeState() {
  const dot = $("bridgeStatus").querySelector(".status-dot");
  dot.className = `status-dot ${state.bridgeOnline ? "" : "is-muted"}`;
  $("bridgeStatus").querySelector("strong").textContent = state.bridgeOnline ? "连接器已连接" : "连接器未连接";
  $("bridgeStatus").querySelector("small").textContent = state.bridgeOnline ? "可执行真实 Git" : "预览模式";
  $("bridgeButtonText").textContent = state.bridgeOnline ? "连接器" : "连接";
  $("settingsBridgePill").textContent = state.bridgeOnline ? "已连接" : "未连接";
  $("settingsBridgePill").classList.toggle("is-online", state.bridgeOnline);
}

function renderUser() {
  const name = state.repository?.gitUserName || "Git 用户";
  const email = state.repository?.gitUserEmail || (state.preview ? "浏览器预览" : "连接本地 Git");
  $("userName").textContent = name;
  $("userEmail").textContent = email;
  $("userAvatar").textContent = name.split(/\s+/).map((part) => part[0]).slice(0, 2).join("").toUpperCase() || "G";
}

function renderRunway() {
  const stage = state.operation === "idle" ? (state.status?.changes?.length ? "check" : "check") : state.operation;
  const order = ["check", "stage", "commit", "rebase", "push"];
  const index = order.indexOf(stage);
  all(".runway-step").forEach((step) => {
    const stepIndex = order.indexOf(step.dataset.stage);
    step.classList.toggle("is-current", step.dataset.stage === stage && state.syncing);
    step.classList.toggle("is-done", state.syncing && stepIndex < index || state.operation === "success" && stepIndex <= 4);
    step.classList.toggle("is-error", state.operation === "conflict" && step.dataset.stage === "rebase" || state.operation === "error" && step.dataset.stage === "push");
  });
  $("runwayHint").textContent = state.syncing ? stageLabel(stage) : state.operation === "success" ? "同步成功" : state.operation === "conflict" ? "请手动解决冲突" : state.preview ? "仅支持浏览器预览" : state.bridgeOnline ? "准备执行安全同步" : "连接本地连接器以同步";
}

function stageLabel(stage) { return ({ check: "正在检查仓库…", stage: "正在暂存本地变更…", commit: "正在创建提交…", rebase: "正在变基本地提交…", push: "正在推送到远程…" }[stage] || "正在处理…"); }

function renderChanges() {
  const list = $("changesList");
  if (state.preview) {
    list.innerHTML = state.preview.files.length ? state.preview.files.map((file) => changeRow({ file: file.name, relativePath: file.path, status: "preview" })).join("") : emptyPanel("没有可见文件", "浏览器没有读取到这个文件夹中的文件。");
    $("changesNote").textContent = "浏览器文件预览";
    return;
  }
  const changes = state.status?.changes || [];
  $("changesNote").textContent = state.status ? "所有本地变更" : "等待仓库";
  list.innerHTML = changes.length ? changes.map(changeRow).join("") : emptyPanel(state.status ? "工作区干净" : "尚未选择仓库", state.status ? "没有需要提交的本地变更。" : "选择一个仓库，或连接本地连接器。");
}

function changeRow(change) {
  const status = (change.status || "preview").toLowerCase();
  const label = { modified: "已修改", added: "已添加", deleted: "已删除", renamed: "已重命名", untracked: "新增", conflicted: "冲突", preview: "预览" }[status] || status;
  const iconClass = status === "added" || status === "untracked" ? "is-added" : status === "deleted" || status === "conflicted" ? "is-deleted" : "";
  const icon = { modified: "M", added: "A", deleted: "D", renamed: "R", untracked: "+", conflicted: "!", preview: "·" }[status] || "·";
  return `<div class="change-row"><span class="change-icon ${iconClass}">${icon}</span><div class="change-name"><strong>${escapeHTML(change.file || change.relativePath)}</strong><small>${escapeHTML(change.relativePath || "")}</small></div><span class="change-status">${label}</span></div>`;
}

function emptyPanel(title, message) { return `<div class="panel-empty"><div><strong>${escapeHTML(title)}</strong><p>${escapeHTML(message)}</p></div></div>`; }

function renderDsStoreNote() {
  const found = !!state.status?.changes?.some((change) => change.file === ".DS_Store" || change.relativePath === ".DS_Store");
  $("dsStoreNote").classList.toggle("is-hidden", !found);
}

function renderActivity() {
  const scoped = state.activity.filter((item) => !state.repository || item.repositoryId === state.repository.id || item.repositoryName === state.repository.name).slice(0, 5);
  const html = scoped.length ? scoped.map(activityRow).join("") : `<div class="activity-empty">暂无活动。完成同步后，记录会显示在这里。</div>`;
  $("recentActivityList").innerHTML = html;
  $("activityPageList").innerHTML = state.activity.length ? state.activity.map(activityRow).join("") : `<div class="activity-empty">暂无活动。同步历史只保存在当前浏览器中。</div>`;
}

function activityRow(item) {
  return `<div class="activity-row"><span class="activity-symbol">${item.result === "Success" ? "✓" : "·"}</span><div><strong>${escapeHTML(item.commitMessage)}</strong><small>${escapeHTML(item.repositoryName)} · ${escapeHTML(item.branch || "Detached HEAD")}</small></div><time>${friendlyTime(item.timestamp)}</time></div>`;
}

function renderLogs() {
  $("logStream").innerHTML = state.logs.length ? state.logs.map((log) => `<div class="log-line ${log.kind ? `is-${log.kind}` : ""}"><span class="log-time">${new Date(log.time).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" })}</span>${escapeHTML(log.title)}${log.detail ? `\n  ${escapeHTML(log.detail)}` : ""}</div>`).join("") : `<div class="log-line">暂无日志。</div>`;
  $("logStream").scrollTop = $("logStream").scrollHeight;
}

function openView(view) {
  state.view = view;
  render();
}

function openDialog(id) { $(id).showModal(); }
function closeDialog(id) { $(id).close(); }

function prepareReview() {
  $("reviewTitle").textContent = state.repository ? `同步 ${state.repository.name}` : "准备同步";
  const rows = [
    ["分支", state.status?.branch || "—"],
    ["变更", `${state.status?.changes?.length || 0} 个文件`],
    ["提交", commitMessage()],
    ["远程", state.repository?.remoteName || "—"]
  ];
  $("reviewFacts").innerHTML = rows.map(([key, value]) => `<div class="review-fact"><span>${escapeHTML(key)}</span><strong>${escapeHTML(value)}</strong></div>`).join("");
  openDialog("reviewModal");
}

function commitMessage() {
  return state.commitMessage || state.repository?.lastCommitMessage || state.settings.commitTemplate.replace("{repository}", state.repository?.name || "仓库");
}

function updateStage(stage) {
  state.operation = stage;
  renderRunway();
  render();
  addLog(stageLabel(stage));
}

async function syncRepository() {
  if (!state.repository || state.preview || !state.bridgeOnline || state.syncing) {
    showToast("请连接本地 Git 连接器", "网页不能自行运行 Git。启动连接器后，通过连接器选择仓库。", "error");
    return;
  }
  state.syncing = true;
  state.retryPushAvailable = false;
  state.logs = [];
  closeDialog("reviewModal");
  render();
  const started = Date.now();
  try {
    updateStage("check");
    updateStage("stage");
    updateStage("commit");
    const result = await bridgeRequest("/sync", { method: "POST", body: JSON.stringify({ path: state.repository.path, message: commitMessage(), fetchBeforeSync: state.settings.fetchBeforeSync }) });
    updateStage(result.didCreateCommit ? "rebase" : "push");
    if (result.didPush) result.repository.lastPush = new Date().toISOString();
    result.repository.lastCommitMessage = commitMessage();
    setRepository(result.repository, result.status);
    state.operation = "success";
    state.syncing = false;
    state.retryPushAvailable = false;
    (result.steps || []).forEach((step) => addLog(step, "", "success"));
    addLog(result.didPush ? "推送完成" : "已是最新状态", `${Math.round((Date.now() - started) / 1000)} 秒`, "success");
    const history = { repositoryId: result.repository.id, repositoryName: result.repository.name, branch: result.repository.branch, commitMessage: commitMessage(), timestamp: new Date().toISOString(), result: result.didPush ? "Success" : "Up to date", commitHash: result.commitHash };
    state.activity.unshift(history);
    state.activity = state.activity.slice(0, 100);
    writeJSON(STORAGE.activity, state.activity);
    showToast(result.didPush ? "同步成功" : "已是最新状态", result.didPush ? `${result.repository.name} 已推送到 ${result.repository.remoteName}。` : "无需新的远程操作。", "success");
  } catch (error) {
    state.syncing = false;
    state.operation = error.code === "rebase-conflict" ? "conflict" : "error";
    state.conflictFiles = error.conflictFiles || [];
    state.retryPushAvailable = !!error.retryable;
    addLog(error.friendly || "Git 操作失败", error.recovery || error.technical || "", "error");
    handleOperationError(error, error.code === "rebase-conflict" ? "检测到变基冲突" : "同步已安全停止");
  }
  render();
}

function handleOperationError(error, title) {
  const parsed = friendlyError(error);
  showToast(title, `${parsed.friendly}${parsed.recovery ? ` ${parsed.recovery}` : ""}`, "error");
  if (parsed.technical) addLog("技术细节", parsed.technical, "error");
}

async function refreshRepository() {
  if (!state.repository || state.preview) { showToast("没有可刷新的仓库", "请先通过本地 Git 连接器选择一个仓库。", "error"); return; }
  if (!state.bridgeOnline) { await checkBridge(true); return; }
  try { await inspectPath(state.repository.path); } catch (error) { handleOperationError(error, "刷新失败"); }
}

async function addRemote() {
  if (!state.bridgeOnline || !state.repository) { showToast("请连接本地 Git 连接器", "添加远程仓库需要本机 Git 环境。", "error"); return; }
  const name = $("remoteNameInput").value.trim() || "origin";
  const url = $("remoteUrlInput").value.trim();
  if (!url) { showToast("需要远程 URL", "请输入 HTTPS 或 SSH 远程地址。", "error"); return; }
  try {
    await bridgeRequest("/remote", { method: "POST", body: JSON.stringify({ path: state.repository.path, name, url }) });
    closeDialog("remoteModal");
    showToast("远程仓库已添加", `${name} 已为当前仓库配置。`, "success");
    await inspectPath(state.repository.path);
  } catch (error) { handleOperationError(error, "无法添加远程仓库"); }
}

async function ignoreDSStore() {
  if (!state.bridgeOnline || !state.repository) return;
  try {
    await bridgeRequest("/gitignore", { method: "POST", body: JSON.stringify({ path: state.repository.path }) });
    showToast(".gitignore 已更新", ".DS_Store 不会再进入后续提交。", "success");
    await inspectPath(state.repository.path);
  } catch (error) { handleOperationError(error, "无法更新 .gitignore"); }
}

async function abortRebase() {
  if (!state.bridgeOnline || !state.repository) return;
  if (!window.confirm("确定中止当前变基吗？本地提交和文件会保留，只会移除变基状态。")) return;
  try {
    await bridgeRequest("/abort-rebase", { method: "POST", body: JSON.stringify({ path: state.repository.path }) });
    state.operation = "idle";
    state.conflictFiles = [];
    showToast("变基已中止", "仓库已准备好重新检查状态。", "success");
    await inspectPath(state.repository.path);
  } catch (error) { handleOperationError(error, "无法中止变基"); }
}

function saveSettings() {
  state.bridgeUrl = $("bridgeUrl").value.trim().replace(/\/$/, "") || defaults.bridgeUrl;
  state.settings.fetchBeforeSync = $("fetchBeforeSync").checked;
  state.settings.confirmBeforePush = $("confirmBeforePush").checked;
  state.settings.commitTemplate = $("commitTemplate").value.trim() || defaults.commitTemplate;
  localStorage.setItem(STORAGE.bridgeUrl, state.bridgeUrl);
  writeJSON(STORAGE.settings, state.settings);
  checkBridge(true);
}

function wireEvents() {
  $("chooseButton").addEventListener("click", () => state.bridgeOnline ? chooseWithBridge() : $("folderPicker").click());
  $("addRepositoryButton").addEventListener("click", chooseWithBridge);
  $("refreshButton").addEventListener("click", refreshRepository);
  $("syncButton").addEventListener("click", () => state.settings.confirmBeforePush ? prepareReview() : syncRepository());
  $("confirmSyncButton").addEventListener("click", syncRepository);
  $("logsButton").addEventListener("click", () => { renderLogs(); openDialog("logsModal"); });
  $("bridgeButton").addEventListener("click", () => openView("settings"));
  $("calloutConnectButton").addEventListener("click", () => openView("settings"));
  $("saveBridgeButton").addEventListener("click", saveSettings);
  $("addRemoteButton").addEventListener("click", () => openDialog("remoteModal"));
  $("saveRemoteButton").addEventListener("click", addRemote);
  $("ignoreDsStoreButton").addEventListener("click", ignoreDSStore);
  $("abortRebaseButton").addEventListener("click", abortRebase);
  $("folderPicker").addEventListener("change", (event) => handlePreviewFiles(event.target.files));
  $("commitInput").addEventListener("input", (event) => { state.commitMessage = event.target.value; });
  all(".nav-item").forEach((button) => button.addEventListener("click", () => openView(button.dataset.view)));
  all("[data-view-link]").forEach((button) => button.addEventListener("click", () => openView(button.dataset.viewLink)));
  all("[data-close-dialog]").forEach((button) => button.addEventListener("click", () => closeDialog(button.dataset.closeDialog)));
  ["dragenter", "dragover"].forEach((eventName) => document.addEventListener(eventName, (event) => { event.preventDefault(); $("dropOverlay").classList.remove("is-hidden"); }));
  ["dragleave", "drop"].forEach((eventName) => document.addEventListener(eventName, (event) => { event.preventDefault(); if (eventName === "drop") handlePreviewFiles(event.dataTransfer.files); $("dropOverlay").classList.add("is-hidden"); }));
  ["fetchBeforeSync", "confirmBeforePush", "commitTemplate"].forEach((id) => $(id).addEventListener("change", () => { state.settings.fetchBeforeSync = $("fetchBeforeSync").checked; state.settings.confirmBeforePush = $("confirmBeforePush").checked; state.settings.commitTemplate = $("commitTemplate").value; writeJSON(STORAGE.settings, state.settings); }));
}

function initialise() {
  $("bridgeUrl").value = state.bridgeUrl;
  $("fetchBeforeSync").checked = state.settings.fetchBeforeSync;
  $("confirmBeforePush").checked = state.settings.confirmBeforePush;
  $("commitTemplate").value = state.settings.commitTemplate;
  $("commitInput").value = commitMessage();
  wireEvents();
  render();
  checkBridge();
  if (state.repositories[0]) selectRepository(state.repositories[0]);
}

initialise();
