"use strict";

(() => {
  const app = document.getElementById("app");
  const template = document.getElementById("card-template");
  const searchInput = document.getElementById("search");
  const filterSelect = document.getElementById("filter");
  const exportButton = document.getElementById("export-button");
  const importButton = document.getElementById("import-button");
  const importFile = document.getElementById("import-file");
  const message = document.getElementById("message");
  const statusLabels = new Map();
  let dataset = null;
  let decisions = {};
  let storageKey = null;
  let exportInFlight = false;

  function setMessage(text, isError = false) {
    message.textContent = text || "";
    message.dataset.kind = text ? (isError ? "error" : "success") : "";
  }

  function artifactUrl(record) {
    if (!record || typeof record.path !== "string" || record.path.includes("..")) return null;
    return `/${record.path.split("/").map(encodeURIComponent).join("/")}`;
  }

  function exactKeys(object, keys) {
    if (!object || typeof object !== "object" || Array.isArray(object)) return false;
    return JSON.stringify(Object.keys(object).sort()) === JSON.stringify([...keys].sort());
  }

  function validDecision(item, decision, requireComplete) {
    if (!decision || !exactKeys(decision, ["status", "notes", "updatedAt"])) return false;
    if (!item.allowedStatuses.includes(decision.status) || typeof decision.notes !== "string") return false;
    if (typeof decision.updatedAt !== "string" || Number.isNaN(Date.parse(decision.updatedAt))) return false;
    if (requireComplete && decision.status !== "pass" && !decision.notes.trim()) return false;
    return true;
  }

  function completeDecisionMap(candidate) {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return false;
    const expected = dataset.items.map((item) => item.reviewKey).sort();
    const actual = Object.keys(candidate).sort();
    if (JSON.stringify(expected) !== JSON.stringify(actual)) return false;
    return dataset.items.every((item) => validDecision(item, candidate[item.reviewKey], true));
  }

  function validateImport(value) {
    if (!exactKeys(value, ["schema", "batchId", "sourceDigest", "reviewDigest", "complete", "exportedAt", "decisions"])) {
      throw new Error("决定文件字段不闭合");
    }
    if (
      value.schema !== dataset.decisionSchema ||
      value.batchId !== dataset.batchId ||
      value.sourceDigest !== dataset.sourceDigest ||
      value.reviewDigest !== dataset.reviewDigest
    ) {
      throw new Error("决定文件属于旧批次或其他证据摘要");
    }
    if (value.complete !== true || !completeDecisionMap(value.decisions)) {
      throw new Error("决定文件不完整、含未知审核键或备注门未通过");
    }
    return value.decisions;
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify({
      schema: "cf7.portrait-pilot-review-local.v1",
      sourceDigest: dataset.sourceDigest,
      reviewDigest: dataset.reviewDigest,
      decisions,
    }));
  }

  function loadLocal() {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return {};
    try {
      const value = JSON.parse(raw);
      if (
        !exactKeys(value, ["schema", "sourceDigest", "reviewDigest", "decisions"]) ||
        value.schema !== "cf7.portrait-pilot-review-local.v1" ||
        value.sourceDigest !== dataset.sourceDigest ||
        value.reviewDigest !== dataset.reviewDigest ||
        !value.decisions || typeof value.decisions !== "object"
      ) return {};
      return Object.fromEntries(dataset.items
        .filter((item) => validDecision(item, value.decisions[item.reviewKey], false))
        .map((item) => [item.reviewKey, value.decisions[item.reviewKey]]));
    } catch {
      return {};
    }
  }

  function badge(text, kind = "") {
    const element = document.createElement("span");
    element.className = `badge ${kind}`.trim();
    element.textContent = text;
    return element;
  }

  function imageElement(record, alt) {
    const image = document.createElement("img");
    image.src = artifactUrl(record);
    image.alt = alt;
    image.loading = "lazy";
    return image;
  }

  function addReferencePanel(container, item) {
    const panel = document.createElement("section");
    panel.className = "visual-panel";
    const title = document.createElement("h3");
    title.textContent = "旧头像参考";
    panel.append(title);
    if (item.oldReference) {
      const wrap = document.createElement("div");
      wrap.className = "master-wrap";
      wrap.append(imageElement(item.oldReference, `${item.portraitRef} 旧头像参考`));
      panel.append(wrap);
    } else {
      const empty = document.createElement("div");
      empty.className = "empty-reference";
      empty.textContent = "没有旧头像；按同类可读性判断";
      panel.append(empty);
    }
    container.append(panel);
  }

  function addProposalPanel(container, item, role, label) {
    const proposal = item.proposals[role];
    const panel = document.createElement("section");
    panel.className = "visual-panel";
    const title = document.createElement("h3");
    title.textContent = label;
    panel.append(title);
    if (!proposal) {
      const empty = document.createElement("div");
      empty.className = "empty-reference";
      empty.textContent = `来源门已阻断：${item.sourceClassification}`;
      panel.append(empty);
      container.append(panel);
      return;
    }
    const wrap = document.createElement("div");
    wrap.className = "master-wrap";
    wrap.append(imageElement(proposal.master, `${item.portraitRef} ${label}`));
    panel.append(wrap);
    const previews = document.createElement("div");
    previews.className = "preview-row";
    for (const size of [80, 48, 32]) {
      const figure = document.createElement("figure");
      const preview = imageElement(proposal.previews[String(size)], `${size}px 预览`);
      preview.width = size;
      preview.height = size;
      const caption = document.createElement("figcaption");
      caption.textContent = `${size}px`;
      figure.append(preview, caption);
      previews.append(figure);
    }
    panel.append(previews);
    const facts = document.createElement("p");
    facts.className = "visual-facts";
    const featureFacts = proposal.featureLabel
      ? ` · feature=${proposal.featureLabel} · mode=${proposal.framingMode} · safe=${proposal.geometry?.safeMarginVerified === true}`
      : "";
    facts.textContent = `${proposal.candidateId} · frame ${proposal.frame}${featureFacts} · confidence ${proposal.confidence} · ${proposal.flags.join(", ")}`;
    panel.append(facts);
    container.append(panel);
  }

  function updateProgress() {
    const reviewed = dataset.items.filter((item) => validDecision(item, decisions[item.reviewKey], true)).length;
    document.getElementById("progress-count").textContent = `${reviewed} / ${dataset.items.length}`;
    document.getElementById("progress-label").textContent = reviewed === dataset.items.length ? "可以导出完整决定" : "进度只保存在当前证据摘要下";
    document.getElementById("progress-bar").style.width = `${(reviewed / dataset.items.length) * 100}%`;
    exportButton.disabled = !completeDecisionMap(decisions);
  }

  function applyVisibility() {
    const query = searchInput.value.trim().toLocaleLowerCase("zh-CN");
    const filter = filterSelect.value;
    for (const card of app.querySelectorAll(".review-card")) {
      const item = dataset.items.find((row) => row.reviewKey === card.dataset.reviewKey);
      const decision = decisions[item.reviewKey];
      const searchable = `${item.portraitRef} ${item.variantKey} ${item.category} ${item.reviewKey}`.toLocaleLowerCase("zh-CN");
      const matchesQuery = !query || searchable.includes(query);
      const reviewed = validDecision(item, decision, true);
      const disagreement = item.comparison && (
        !item.comparison.candidateAgreement ||
        item.comparison.framingAgreement === false ||
        (typeof item.comparison.cropIoU === "number" && item.comparison.cropIoU < 0.8) ||
        (typeof item.comparison.featureIoU === "number" && item.comparison.featureIoU < 0.65) ||
        (typeof item.comparison.mustIncludeIoU === "number" && item.comparison.mustIncludeIoU < 0.65)
      );
      const matchesFilter = filter === "all" ||
        (filter === "pending" && !reviewed) ||
        (filter === "reviewed" && reviewed) ||
        (filter === "risk" && item.risks.length > 0) ||
        (filter === "disagreement" && disagreement) ||
        (filter === "blocked" && item.blocked);
      card.hidden = !(matchesQuery && matchesFilter);
    }
  }

  function syncCard(card, item) {
    const decision = decisions[item.reviewKey];
    card.dataset.reviewed = String(validDecision(item, decision, true));
    for (const button of card.querySelectorAll(".status-buttons button")) {
      button.classList.toggle("selected", Boolean(decision && decision.status === button.dataset.status));
    }
    const textarea = card.querySelector("textarea");
    if (document.activeElement !== textarea) textarea.value = decision?.notes || "";
    textarea.classList.toggle("invalid", Boolean(decision && decision.status !== "pass" && !decision.notes.trim()));
  }

  function renderCard(item) {
    const fragment = template.content.cloneNode(true);
    const card = fragment.querySelector(".review-card");
    card.dataset.reviewKey = item.reviewKey;
    card.dataset.blocked = String(item.blocked);
    fragment.querySelector(".review-code").textContent = item.reviewCode;
    fragment.querySelector(".review-title").textContent = `${item.portraitRef} · ${item.variantKey}`;
    fragment.querySelector(".review-meta").textContent = `${item.category} · ${item.reviewKey}`;
    fragment.querySelector(".review-notes").textContent = item.notes;
    const humanFeedback = fragment.querySelector(".human-feedback");
    if (item.humanFeedback) {
      humanFeedback.hidden = false;
      humanFeedback.textContent = `上一轮人工反馈：${item.humanFeedback.notes}`;
    }
    const badges = fragment.querySelector(".badges");
    badges.append(badge(item.sourceClassification, item.blocked ? "blocked" : ""));
    if (item.comparison) {
      badges.append(badge(item.comparison.candidateAgreement ? "A/B 同帧" : "A/B 不同帧", item.comparison.candidateAgreement ? "" : "risk"));
      if (typeof item.comparison.cropIoU === "number") {
        badges.append(badge(`crop IoU ${item.comparison.cropIoU}`, item.comparison.cropIoU >= 0.8 ? "" : "risk"));
      }
      if (typeof item.comparison.featureIoU === "number") {
        badges.append(badge(`feature IoU ${item.comparison.featureIoU}`, item.comparison.featureIoU >= 0.65 ? "" : "risk"));
        badges.append(badge(`context IoU ${item.comparison.mustIncludeIoU}`, item.comparison.mustIncludeIoU >= 0.65 ? "" : "risk"));
        badges.append(badge(item.comparison.framingAgreement ? "A/B 同构图模式" : "A/B 构图模式分歧", item.comparison.framingAgreement ? "" : "risk"));
      }
    }
    for (const risk of item.risks) badges.append(badge(risk, "risk"));

    const visualGrid = fragment.querySelector(".visual-grid");
    addReferencePanel(visualGrid, item);
    addProposalPanel(visualGrid, item, "proposal", "Luna A 提案");
    addProposalPanel(visualGrid, item, "independent_review", "Luna B 独立复核");

    const strip = fragment.querySelector(".candidate-strip");
    for (const candidate of item.candidates) {
      const figure = document.createElement("figure");
      figure.append(imageElement(candidate.artifact, `${candidate.candidateId} frame ${candidate.frame}`));
      const caption = document.createElement("figcaption");
      caption.textContent = `${candidate.candidateId} · frame ${candidate.frame}`;
      figure.append(caption);
      strip.append(figure);
    }
    if (item.candidates.length === 0) fragment.querySelector(".candidate-context").hidden = true;

    const buttons = fragment.querySelector(".status-buttons");
    for (const status of dataset.statuses.filter((status) => item.allowedStatuses.includes(status.value))) {
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.status = status.value;
      button.textContent = status.label;
      button.addEventListener("click", () => {
        const previous = decisions[item.reviewKey];
        decisions[item.reviewKey] = {
          status: status.value,
          notes: previous?.notes || "",
          updatedAt: new Date().toISOString(),
        };
        persist();
        syncCard(card, item);
        updateProgress();
        applyVisibility();
      });
      buttons.append(button);
    }
    const textarea = fragment.querySelector("textarea");
    textarea.addEventListener("input", () => {
      const previous = decisions[item.reviewKey];
      if (!previous) return;
      decisions[item.reviewKey] = { ...previous, notes: textarea.value, updatedAt: new Date().toISOString() };
      persist();
      syncCard(card, item);
      updateProgress();
    });
    syncCard(card, item);
    return fragment;
  }

  async function exportDecisions() {
    if (exportInFlight) return;
    if (!completeDecisionMap(decisions)) {
      setMessage("决定尚未覆盖全部审核行，不能导出。", true);
      return;
    }
    exportInFlight = true;
    exportButton.disabled = true;
    exportButton.textContent = "正在保存…";
    setMessage("正在写入 canonical 决定和版本化归档…", false);
    const value = {
      schema: dataset.decisionSchema,
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      reviewDigest: dataset.reviewDigest,
      complete: true,
      exportedAt: new Date().toISOString(),
      decisions,
    };
    try {
      if (typeof window.savePortraitReviewDecisions === "function") {
        const saved = await window.savePortraitReviewDecisions(value);
        setMessage(`保存成功：${saved.path}；归档：${saved.archivePath}`, false);
        exportButton.textContent = "已保存 ✓（可再次导出）";
        return;
      }
      const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = "portrait-pilot-review-decisions.json";
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 0);
      setMessage("浏览器下载已触发；请核对下载文件非空。", false);
      exportButton.textContent = "已触发下载 ✓（可再次导出）";
    } catch (error) {
      exportButton.textContent = "导出完整决定";
      throw error;
    } finally {
      exportInFlight = false;
      exportButton.disabled = !completeDecisionMap(decisions);
    }
  }

  async function importDecisions(file) {
    const value = JSON.parse(await file.text());
    decisions = validateImport(value);
    persist();
    renderAll();
    setMessage("完整决定已导入，并与当前 source/review digest 对齐。", false);
  }

  function renderAll() {
    app.replaceChildren(...dataset.items.map(renderCard));
    updateProgress();
    applyVisibility();
    app.dataset.ready = "true";
  }

  async function boot() {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath || !dataPath.startsWith("/tmp/portrait-pilot/") || dataPath.includes("..") || !dataPath.endsWith("/review-data.json")) {
      throw new Error("缺少受约束的 review-data 路径");
    }
    const response = await fetch(dataPath, { cache: "no-store" });
    if (!response.ok) throw new Error(`review-data 加载失败：HTTP ${response.status}`);
    dataset = await response.json();
    if (
      !["cf7.portrait-pilot-review-data.v1", "cf7.portrait-pilot-review-data.v2"].includes(dataset.schema) ||
      dataset.partial !== false ||
      !dataset.counts ||
      dataset.items.length < 1 ||
      dataset.items.length !== dataset.counts.total ||
      dataset.counts.eligible + dataset.counts.blocked !== dataset.counts.total
    ) {
      throw new Error("review-data schema、partial 或行数非法");
    }
    for (const status of dataset.statuses) statusLabels.set(status.value, status.label);
    storageKey = `cf7-portrait-pilot-review:${dataset.reviewDigest}`;
    decisions = loadLocal();
    document.getElementById("source-digest").textContent = `source ${dataset.sourceDigest}`;
    document.getElementById("review-digest").textContent = `review ${dataset.reviewDigest}`;
    document.getElementById("contact-sheet-link").href = artifactUrl(dataset.fullContactSheet);
    renderAll();
    window.__portraitReviewTest = {
      get dataset() { return dataset; },
      get decisions() { return decisions; },
      get storageKey() { return storageKey; },
      validateImport,
      completeDecisionMap,
    };
  }

  searchInput.addEventListener("input", applyVisibility);
  filterSelect.addEventListener("change", applyVisibility);
  exportButton.addEventListener("click", () => {
    exportDecisions().catch((error) => setMessage(`导出失败：${error.message}`, true));
  });
  importButton.addEventListener("click", () => importFile.click());
  importFile.addEventListener("change", async () => {
    try {
      if (importFile.files[0]) await importDecisions(importFile.files[0]);
    } catch (error) {
      setMessage(error.message, true);
    } finally {
      importFile.value = "";
    }
  });
  window.addEventListener("review-export-saved", (event) => setMessage(`决定已保存：${event.detail}`, false));
  boot().catch((error) => {
    app.dataset.ready = "error";
    setMessage(error.message, true);
  });
})();
