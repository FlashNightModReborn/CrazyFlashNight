(() => {
  "use strict";

  const DATA_SCHEMA = "cf7.enemy-portrait-frame-reselection-candidates.v1";
  const app = document.querySelector("#app");
  const rowTemplate = document.querySelector("#row-template");
  const frameTemplate = document.querySelector("#frame-template");
  const exportButton = document.querySelector("#export-button");
  const importButton = document.querySelector("#import-button");
  const importFile = document.querySelector("#import-file");
  const message = document.querySelector("#message");
  const decisions = {};
  let dataset;
  let storageKey;
  let saving = false;

  function exactKeys(value, expected, label) {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} 必须是对象`);
    const actual = Object.keys(value).sort();
    const wanted = [...expected].sort();
    if (JSON.stringify(actual) !== JSON.stringify(wanted)) throw new Error(`${label} 字段不闭合`);
  }

  function assetUrl(record) {
    if (!record || typeof record.path !== "string" || record.path.includes("..")) throw new Error("素材路径非法");
    return `/${record.path.replaceAll("\\", "/")}`;
  }

  function candidateFor(item, candidateId) {
    return item.candidates.find((candidate) => candidate.candidateId === candidateId) || null;
  }

  function rowComplete(choice) {
    return Boolean(choice && (
      (choice.status === "selected" && typeof choice.candidateId === "string") ||
      (choice.status === "expand_search" && choice.candidateId === null && choice.notes.trim())
    ));
  }

  function completeDecisions(value = decisions) {
    return dataset.items.every((item) => rowComplete(value[item.reviewKey]));
  }

  function validateChoice(item, choice) {
    exactKeys(choice, ["status", "candidateId", "candidateSha256", "vectorArtifactSha256", "frame", "notes", "updatedAt"], `重选帧决定 ${item.reviewKey}`);
    if (!["selected", "expand_search"].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt))) {
      throw new Error(`重选帧状态或时间非法：${item.reviewKey}`);
    }
    if (typeof choice.notes !== "string" || choice.notes.length > 1000) throw new Error(`重选帧备注非法：${item.reviewKey}`);
    if (choice.status === "expand_search") {
      if (choice.candidateId !== null || choice.candidateSha256 !== null || choice.vectorArtifactSha256 !== null || choice.frame !== null || !choice.notes.trim()) {
        throw new Error(`继续抽帧必须清空候选并填写备注：${item.reviewKey}`);
      }
      return;
    }
    const candidate = candidateFor(item, choice.candidateId);
    if (!candidate || item.rejectedCandidateIds.includes(choice.candidateId)) throw new Error(`选择了未知或已否决帧：${item.reviewKey}`);
    if (
      choice.candidateSha256 !== candidate.artifact.sha256 ||
      choice.vectorArtifactSha256 !== candidate.vectorArtifact.sha256 ||
      choice.frame !== candidate.frame
    ) throw new Error(`候选帧 hash 或帧号不闭合：${item.reviewKey}`);
  }

  function validateImport(value) {
    exactKeys(value, ["schema", "batchId", "sourceDigest", "datasetDigest", "complete", "exportedAt", "choices"], "重选帧决定文件");
    if (
      value.schema !== dataset.decisionSchema ||
      value.batchId !== dataset.batchId ||
      value.sourceDigest !== dataset.sourceDigest ||
      value.datasetDigest !== dataset.datasetDigest
    ) throw new Error("重选帧决定属于旧批次或其他来源闭包");
    if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new Error("重选帧决定未完整导出");
    exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "重选帧决定映射");
    for (const item of dataset.items) validateChoice(item, value.choices[item.reviewKey]);
    return value;
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify({
      schema: "cf7.enemy-portrait-frame-reselection-local.v1",
      datasetDigest: dataset.datasetDigest,
      decisions,
    }));
  }

  function restore() {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return;
    try {
      const value = JSON.parse(raw);
      if (value.schema === "cf7.enemy-portrait-frame-reselection-local.v1" && value.datasetDigest === dataset.datasetDigest) {
        Object.assign(decisions, value.decisions || {});
      }
    } catch {
      localStorage.removeItem(storageKey);
    }
  }

  function buildExport() {
    return {
      schema: dataset.decisionSchema,
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      datasetDigest: dataset.datasetDigest,
      complete: completeDecisions(),
      exportedAt: new Date().toISOString(),
      choices: Object.fromEntries(dataset.items.map((item) => [item.reviewKey, decisions[item.reviewKey]])),
    };
  }

  function updateProgress() {
    const done = dataset.items.filter((item) => rowComplete(decisions[item.reviewKey])).length;
    document.querySelector("#progress-count").textContent = `${done} / ${dataset.items.length}`;
    document.querySelector("#progress-label").textContent = done === dataset.items.length ? "可导出" : "逐项重选帧";
    document.querySelector("#progress-bar").style.width = `${100 * done / dataset.items.length}%`;
    exportButton.disabled = saving || done !== dataset.items.length;
  }

  function renderDecision(item, row) {
    const choice = decisions[item.reviewKey];
    row.dataset.reviewed = String(rowComplete(choice));
    for (const card of row.querySelectorAll(".frame-card")) {
      card.dataset.selected = String(choice?.status === "selected" && card.dataset.candidateId === choice.candidateId);
    }
    const expand = row.querySelector(".expand-search");
    expand.setAttribute("aria-pressed", String(choice?.status === "expand_search"));
    const textarea = row.querySelector("textarea");
    if (document.activeElement !== textarea) textarea.value = choice?.notes || "";
    const summary = row.querySelector(".decision-summary");
    if (choice?.status === "selected") {
      const candidate = candidateFor(item, choice.candidateId);
      summary.textContent = `已选 ${candidate.candidateId} · frame ${candidate.frame}`;
    } else if (choice?.status === "expand_search") summary.textContent = "现有帧均不可用，将继续抽帧";
    else summary.textContent = "尚未选择";
  }

  function setChoice(item, row, value) {
    decisions[item.reviewKey] = { ...value, updatedAt: new Date().toISOString() };
    persist();
    renderDecision(item, row);
    updateProgress();
  }

  function renderRow(item) {
    const row = rowTemplate.content.firstElementChild.cloneNode(true);
    row.dataset.reviewKey = item.reviewKey;
    row.querySelector(".review-code").textContent = item.reviewCode;
    row.querySelector(".review-title").textContent = item.portraitRef;
    row.querySelector(".review-meta").textContent = `${item.category} · ${item.candidates.length} 个候选 · 已否决 ${item.rejectedCandidateIds.join(", ")}`;
    row.querySelector(".human-note").textContent = `上一轮人审：${item.humanDecision.notes}`;
    row.querySelector(".badges").innerHTML = '<span class="badge warning">wrong_pose</span><span class="badge">SVG 原帧</span>';
    const grid = row.querySelector(".source-grid");
    for (const candidate of item.candidates) {
      const card = frameTemplate.content.firstElementChild.cloneNode(true);
      const rejected = item.rejectedCandidateIds.includes(candidate.candidateId);
      card.dataset.candidateId = candidate.candidateId;
      card.dataset.rejected = String(rejected);
      card.querySelector(".source-code").textContent = candidate.candidateId;
      card.querySelector(".source-status").textContent = rejected ? "枪遮挡头部 · 禁选" : "可选";
      const frameMeta = card.querySelector(".frame-meta");
      for (const text of [
        `frame ${candidate.frame}`,
        `PNG ${candidate.width}×${candidate.height}`,
        `SVG ${candidate.vectorCanvasSize[0]}×${candidate.vectorCanvasSize[1]}`,
      ]) {
        const span = document.createElement("span");
        span.textContent = text;
        frameMeta.append(span);
      }
      const vectorLink = card.querySelector(".frame-vector");
      vectorLink.href = assetUrl(candidate.vectorArtifact);
      vectorLink.querySelector("img").src = assetUrl(candidate.vectorArtifact);
      vectorLink.querySelector("img").alt = `${item.portraitRef} frame ${candidate.frame} SVG`;
      const rasterLink = card.querySelector(".frame-raster");
      rasterLink.href = assetUrl(candidate.artifact);
      rasterLink.querySelector("img").src = assetUrl(candidate.artifact);
      rasterLink.querySelector("img").alt = `${item.portraitRef} frame ${candidate.frame} PNG`;
      const button = card.querySelector(".select-frame");
      button.disabled = rejected;
      button.addEventListener("click", () => setChoice(item, row, {
        status: "selected",
        candidateId: candidate.candidateId,
        candidateSha256: candidate.artifact.sha256,
        vectorArtifactSha256: candidate.vectorArtifact.sha256,
        frame: candidate.frame,
        notes: row.querySelector("textarea").value,
      }));
      grid.append(card);
    }
    row.querySelector(".expand-search").addEventListener("click", () => {
      const notes = row.querySelector("textarea").value.trim() || "现有抽样帧均无法清楚露出身份特征，需要扩大帧搜索。";
      setChoice(item, row, {
        status: "expand_search",
        candidateId: null,
        candidateSha256: null,
        vectorArtifactSha256: null,
        frame: null,
        notes,
      });
    });
    row.querySelector("textarea").addEventListener("input", (event) => {
      const current = decisions[item.reviewKey];
      if (!current) return;
      decisions[item.reviewKey] = { ...current, notes: event.target.value, updatedAt: new Date().toISOString() };
      persist();
      renderDecision(item, row);
      updateProgress();
    });
    renderDecision(item, row);
    return row;
  }

  async function exportDecisions() {
    if (saving || !completeDecisions()) return;
    saving = true;
    updateProgress();
    exportButton.textContent = "保存中…";
    message.textContent = "正在保存并校验重选帧决定…";
    try {
      const value = validateImport(buildExport());
      if (typeof window.savePortraitFrameReselection === "function") {
        const saved = await window.savePortraitFrameReselection(value);
        message.textContent = `保存成功：${saved.path}`;
      } else {
        const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "portrait-pilot-frame-reselection.json";
        link.click();
        URL.revokeObjectURL(link.href);
        message.textContent = "已导出到浏览器下载目录";
      }
      exportButton.textContent = "已保存";
    } catch (error) {
      saving = false;
      exportButton.textContent = "导出重选帧决定";
      message.textContent = `保存失败：${error.message}`;
      updateProgress();
    }
  }

  async function load() {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath || dataPath.includes("..")) throw new Error("缺少合法 data 参数");
    const response = await fetch(dataPath, { cache: "no-store" });
    if (!response.ok) throw new Error(`数据加载失败：HTTP ${response.status}`);
    dataset = await response.json();
    if (dataset.schema !== DATA_SCHEMA || dataset.productionReady !== false) throw new Error("重选帧数据 schema 或状态非法");
    storageKey = `cf7:portrait-frame-reselection:${dataset.datasetDigest}`;
    restore();
    document.querySelector("#source-digest").textContent = `source ${dataset.sourceDigest.slice(0, 12)}`;
    document.querySelector("#dataset-digest").textContent = `dataset ${dataset.datasetDigest.slice(0, 12)}`;
    document.querySelector("#candidate-count").textContent = `${dataset.counts.candidateCount} candidates`;
    for (const item of dataset.items) app.append(renderRow(item));
    updateProgress();
    app.dataset.ready = "true";
    window.__portraitFrameReselectionTest = { dataset, decisions, storageKey, validateImport, completeDecisions, buildExport };
  }

  exportButton.addEventListener("click", exportDecisions);
  importButton.addEventListener("click", () => importFile.click());
  importFile.addEventListener("change", async () => {
    try {
      const value = validateImport(JSON.parse(await importFile.files[0].text()));
      Object.keys(decisions).forEach((key) => delete decisions[key]);
      Object.assign(decisions, value.choices);
      persist();
      for (const item of dataset.items) renderDecision(item, app.querySelector(`[data-review-key="${CSS.escape(item.reviewKey)}"]`));
      updateProgress();
      message.textContent = "已导入完整决定";
    } catch (error) {
      message.textContent = `导入失败：${error.message}`;
    } finally {
      importFile.value = "";
    }
  });
  window.addEventListener("frame-reselection-export-saved", (event) => {
    message.textContent = `保存成功：${event.detail}`;
    exportButton.textContent = "已保存";
  });

  load().catch((error) => {
    message.textContent = `页面初始化失败：${error.message}`;
    app.dataset.ready = "error";
  });
})();
