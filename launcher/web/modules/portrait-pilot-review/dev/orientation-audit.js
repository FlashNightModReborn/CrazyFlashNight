(() => {
  "use strict";

  const app = document.getElementById("app");
  const template = document.getElementById("card-template");
  const exportButton = document.getElementById("export");
  const message = document.getElementById("message");
  let dataset;
  let decisions = {};
  let storageKey;
  let currentFilter = "all";
  let exportInFlight = false;

  function setMessage(text, error = false) {
    message.textContent = text;
    message.classList.toggle("error", error);
  }

  function imageUrl(record) {
    if (!record || typeof record.path !== "string" || !record.path.startsWith("launcher/web/")) {
      throw new Error("头像 artifact 路径非法");
    }
    return `/${record.path}`;
  }

  function labelDirection(value) {
    return ({
      left: "当前朝左",
      right: "当前朝右",
      frontal_or_symmetric: "正面 / 对称",
      ambiguous: "方向不明确",
    })[value] || value;
  }

  function loadLocal() {
    try {
      const value = JSON.parse(localStorage.getItem(storageKey) || "{}");
      if (!value || typeof value !== "object" || Array.isArray(value)) return {};
      return Object.fromEntries(Object.entries(value).filter(([key, row]) =>
        dataset.items.some((item) => item.reviewKey === key) &&
        row && ["keep", "flip_x"].includes(row.action) && typeof row.updatedAt === "string"));
    } catch (_error) {
      return {};
    }
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify(decisions));
  }

  function selectedCount() {
    return dataset.items.filter((item) => decisions[item.reviewKey]).length;
  }

  function complete() {
    return selectedCount() === dataset.items.length;
  }

  function applyFilter() {
    for (const card of app.querySelectorAll(".audit-card")) {
      const item = dataset.items.find((row) => row.reviewKey === card.dataset.reviewKey);
      const pending = !decisions[item.reviewKey];
      card.hidden = !(
        currentFilter === "all" ||
        (currentFilter === "flip" && item.disposition === "human_review_flip_candidate") ||
        (currentFilter === "disagreed" && item.disposition !== "human_review_flip_candidate") ||
        (currentFilter === "pending" && pending)
      );
    }
  }

  function updateProgress() {
    const selected = selectedCount();
    document.getElementById("progress-count").textContent = `${selected} / ${dataset.items.length}`;
    document.getElementById("progress-label").textContent = complete() ? "可以导出完整裁决" : "逐项选择当前或镜像";
    document.getElementById("progress-bar").style.width = `${selected / dataset.items.length * 100}%`;
    exportButton.disabled = !complete() || exportInFlight;
    applyFilter();
  }

  function syncCard(card, item) {
    const decision = decisions[item.reviewKey];
    card.dataset.decision = decision?.action || "";
    for (const button of card.querySelectorAll(".orientation-choice")) {
      button.setAttribute("aria-checked", String(button.dataset.action === decision?.action));
    }
    card.querySelector(".decision-state").textContent = decision
      ? decision.action === "keep" ? "已裁决：保持当前方向" : "已裁决：使用镜像方向"
      : "尚未裁决；模型建议只作参考";
  }

  function choose(card, item, action) {
    decisions[item.reviewKey] = { action, updatedAt: new Date().toISOString() };
    persist();
    syncCard(card, item);
    updateProgress();
    setMessage(`${item.portraitRef} 已选择${action === "keep" ? "保持当前" : "使用镜像"}。`);
  }

  function renderItem(item) {
    const fragment = template.content.cloneNode(true);
    const card = fragment.querySelector(".audit-card");
    card.dataset.reviewKey = item.reviewKey;
    fragment.querySelector(".review-code").textContent = item.reviewCode;
    fragment.querySelector(".review-title").textContent = `${item.portraitRef} · ${item.variantKey}`;
    fragment.querySelector(".provenance").textContent = `既有发布方向 ${item.currentProductionOrientationAction} · ${item.orientationSource}`;
    const badge = fragment.querySelector(".risk-badge");
    const flipCandidate = item.disposition === "human_review_flip_candidate";
    badge.textContent = flipCandidate ? "A/B 建议翻转" : "A/B 分歧或模糊";
    badge.classList.toggle("disagreed", !flipCandidate);
    for (const [selector, model] of [[".model-a", item.proposal], [".model-b", item.independentReview]]) {
      const row = fragment.querySelector(selector);
      row.querySelector(".model-direction").textContent = `${labelDirection(model.currentDirection)} · ${(model.confidence * 100).toFixed(0)}%`;
      row.querySelector(".model-landmark").textContent = model.landmark;
      row.querySelector(".model-landmark").title = model.landmark;
    }
    const url = imageUrl(item.png);
    for (const image of fragment.querySelectorAll("img")) image.src = url;
    app.append(fragment);
    const mounted = app.lastElementChild;
    for (const button of mounted.querySelectorAll(".orientation-choice")) {
      button.addEventListener("click", () => choose(mounted, item, button.dataset.action));
      button.addEventListener("keydown", (event) => {
        if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
        const action = event.key === "ArrowLeft" ? "keep" : "flip_x";
        choose(mounted, item, action);
        mounted.querySelector(`.orientation-choice[data-action="${action}"]`).focus();
        event.preventDefault();
      });
    }
    syncCard(mounted, item);
  }

  function exportValue() {
    if (!complete()) throw new Error("尚有未裁决头像，不能导出");
    return {
      schema: dataset.decisionSchema,
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      modelReportDigest: dataset.modelReportDigest,
      reviewDigest: dataset.reviewDigest,
      complete: true,
      exportedAt: new Date().toISOString(),
      decisions: dataset.items.map((item) => ({
        reviewKey: item.reviewKey,
        action: decisions[item.reviewKey].action,
        updatedAt: decisions[item.reviewKey].updatedAt,
      })),
    };
  }

  async function exportDecisions() {
    if (exportInFlight) return;
    const value = exportValue();
    exportInFlight = true;
    updateProgress();
    exportButton.textContent = "正在导出…";
    try {
      if (typeof window.savePortraitOrientationDecisions === "function") {
        const saved = await window.savePortraitOrientationDecisions(value);
        setMessage(`保存成功：${saved.path}；归档：${saved.archivePath}`);
        exportButton.textContent = "已保存 ✓（可再次导出）";
      } else {
        const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "portrait-orientation-human-decisions.json";
        link.click();
        setTimeout(() => URL.revokeObjectURL(link.href), 0);
        setMessage("浏览器下载已触发；文件名 portrait-orientation-human-decisions.json。请完成后告诉我“已经导出”。");
        exportButton.textContent = "已触发下载 ✓（可再次导出）";
      }
    } finally {
      exportInFlight = false;
      updateProgress();
    }
  }

  async function boot() {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath || !dataPath.startsWith("/tmp/portrait-pilot/") || dataPath.includes("..") || !dataPath.endsWith("/orientation-human-review-data.json")) {
      throw new Error("缺少受约束的方向复核 data 路径");
    }
    const response = await fetch(dataPath, { cache: "no-store" });
    if (!response.ok) throw new Error(`方向复核数据加载失败：HTTP ${response.status}`);
    dataset = await response.json();
    if (dataset.schema !== "cf7.portrait-orientation-human-review-data.v1" || dataset.partial !== false || dataset.items?.length !== 39) {
      throw new Error("方向复核数据 schema、partial 或行数非法");
    }
    storageKey = `cf7-portrait-orientation-review:${dataset.reviewDigest}`;
    decisions = loadLocal();
    dataset.items.forEach(renderItem);
    for (const button of document.querySelectorAll(".filter")) {
      button.addEventListener("click", () => {
        currentFilter = button.dataset.filter;
        document.querySelectorAll(".filter").forEach((entry) => entry.classList.toggle("selected", entry === button));
        applyFilter();
      });
    }
    exportButton.addEventListener("click", () => exportDecisions().catch((error) => setMessage(error.message, true)));
    window.addEventListener("orientation-review-export-saved", (event) => setMessage(`方向裁决已保存：${event.detail}`));
    updateProgress();
    app.dataset.ready = "true";
    setMessage("39 个方向风险项已载入。左右方向只影响呈现，不改变构图与选帧。");
    window.__portraitOrientationAudit = { get dataset() { return dataset; }, get decisions() { return decisions; }, exportValue };
  }

  boot().catch((error) => {
    app.dataset.ready = "error";
    setMessage(error.message, true);
  });
})();
