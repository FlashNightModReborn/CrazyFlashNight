(() => {
  "use strict";

  const DATA_SCHEMA = "cf7.enemy-portrait-black-matte-candidates.v1";
  const app = document.querySelector("#app");
  const rowTemplate = document.querySelector("#row-template");
  const originalTemplate = document.querySelector("#original-template");
  const candidateTemplate = document.querySelector("#candidate-template");
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
    if (JSON.stringify(Object.keys(value).sort()) !== JSON.stringify([...expected].sort())) throw new Error(`${label} 字段不闭合`);
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
      (choice.status === "refine" && choice.candidateId === null && choice.notes.trim())
    ));
  }

  function completeDecisions(value = decisions) {
    return dataset.items.every((item) => rowComplete(value[item.reviewKey]));
  }

  function validateChoice(item, choice) {
    exactKeys(choice, ["status", "candidateId", "candidateDigest", "outputSupersampleSha256", "master512Sha256", "notes", "updatedAt"], `透明化决定 ${item.reviewKey}`);
    if (!['selected', 'refine'].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt))) throw new Error(`透明化状态或时间非法：${item.reviewKey}`);
    if (typeof choice.notes !== "string" || choice.notes.length > 1000) throw new Error(`透明化备注非法：${item.reviewKey}`);
    if (choice.status === "refine") {
      if (choice.candidateId !== null || choice.candidateDigest !== null || choice.outputSupersampleSha256 !== null || choice.master512Sha256 !== null || !choice.notes.trim()) {
        throw new Error(`继续调参必须清空候选并填写备注：${item.reviewKey}`);
      }
      return;
    }
    const candidate = candidateFor(item, choice.candidateId);
    if (!candidate || choice.candidateDigest !== candidate.candidateDigest || choice.outputSupersampleSha256 !== candidate.outputs.supersample4096.sha256 || choice.master512Sha256 !== candidate.outputs.master512.sha256) {
      throw new Error(`选择了未知或 hash 漂移候选：${item.reviewKey}`);
    }
  }

  function validateImport(value) {
    exactKeys(value, ["schema", "batchId", "sourceDigest", "datasetDigest", "complete", "exportedAt", "choices"], "透明化决定文件");
    if (value.schema !== dataset.decisionSchema || value.batchId !== dataset.batchId || value.sourceDigest !== dataset.sourceDigest || value.datasetDigest !== dataset.datasetDigest) {
      throw new Error("透明化决定属于旧批次或其他来源闭包");
    }
    if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new Error("透明化决定未完整导出");
    exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "透明化决定映射");
    for (const item of dataset.items) validateChoice(item, value.choices[item.reviewKey]);
    return value;
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify({ schema: "cf7.enemy-portrait-black-matte-local.v1", datasetDigest: dataset.datasetDigest, decisions }));
  }

  function restore() {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return;
    try {
      const value = JSON.parse(raw);
      if (value.schema === "cf7.enemy-portrait-black-matte-local.v1" && value.datasetDigest === dataset.datasetDigest) Object.assign(decisions, value.decisions || {});
    } catch { localStorage.removeItem(storageKey); }
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
    document.querySelector("#progress-label").textContent = done === dataset.items.length ? "可导出" : "请选择透明化候选";
    document.querySelector("#progress-bar").style.width = `${100 * done / dataset.items.length}%`;
    exportButton.disabled = saving || done !== dataset.items.length;
  }

  function previewFigure(record, size, alt) {
    const figure = document.createElement("figure");
    const image = document.createElement("img");
    image.src = assetUrl(record);
    image.alt = alt;
    image.dataset.size = String(size);
    const caption = document.createElement("figcaption");
    caption.textContent = `${size}px`;
    figure.append(image, caption);
    return figure;
  }

  function renderDecision(item, row) {
    const choice = decisions[item.reviewKey];
    row.dataset.reviewed = String(rowComplete(choice));
    for (const card of row.querySelectorAll(".matte-card")) card.dataset.selected = String(choice?.status === "selected" && card.dataset.candidateId === choice.candidateId);
    const refine = row.querySelector(".refine-button");
    refine.setAttribute("aria-pressed", String(choice?.status === "refine"));
    const textarea = row.querySelector("textarea");
    if (document.activeElement !== textarea) textarea.value = choice?.notes || "";
    const summary = row.querySelector(".decision-summary");
    if (choice?.status === "selected") {
      const candidate = candidateFor(item, choice.candidateId);
      summary.textContent = `已选：${candidate.roleLabel} · ${candidate.label} · gamma ${candidate.gamma.toFixed(2)}`;
    } else if (choice?.status === "refine") summary.textContent = "现有候选不合适，将按备注继续调参";
    else summary.textContent = "尚未选择";
  }

  function setChoice(item, row, value) {
    decisions[item.reviewKey] = { ...value, updatedAt: new Date().toISOString() };
    persist();
    renderDecision(item, row);
    updateProgress();
  }

  function renderOriginal(item, original) {
    const card = originalTemplate.content.firstElementChild.cloneNode(true);
    card.querySelector(".role-label").textContent = original.roleLabel;
    card.querySelector(".frame-meta").textContent = `${original.framingMode} · ${original.candidateSourceId} / frame ${original.frame}`;
    const link = card.querySelector(".visual");
    link.href = assetUrl(original.master);
    link.querySelector("img").src = assetUrl(original.master);
    link.querySelector("img").alt = `${item.portraitRef} ${original.roleLabel} 原始黑底`;
    const strip = card.querySelector(".preview-strip");
    for (const size of [80, 48, 32]) strip.append(previewFigure(original.previews[String(size)], size, `${item.portraitRef} 原始 ${size}px`));
    return card;
  }

  function renderCandidate(item, row, candidate) {
    const card = candidateTemplate.content.firstElementChild.cloneNode(true);
    card.dataset.candidateId = candidate.candidateId;
    card.querySelector(".candidate-label").textContent = `${candidate.roleLabel} · ${candidate.label}`;
    card.querySelector(".candidate-description").textContent = `${candidate.framingMode} · gamma ${candidate.gamma.toFixed(2)} · ${candidate.description}`;
    card.querySelector(".recommended").hidden = !candidate.recommended;
    for (const link of card.querySelectorAll(".candidate-link, .candidate-link-light")) {
      link.href = assetUrl(candidate.outputs.supersample4096);
      link.querySelector("img").src = assetUrl(candidate.outputs.master512);
      link.querySelector("img").alt = `${item.portraitRef} ${candidate.label}`;
    }
    const strip = card.querySelector(".preview-strip");
    for (const size of [80, 48, 32]) strip.append(previewFigure(candidate.outputs[`preview${size}`], size, `${item.portraitRef} ${candidate.label} ${size}px`));
    const metrics = card.querySelector(".metrics");
    for (const text of [
      `黑底 MAE ${candidate.metrics.blackCompositeMeanAbsoluteError}`,
      `最大误差 ${candidate.metrics.blackCompositeMaximumAbsoluteError}`,
      `全透明 ${(100 * candidate.metrics.transparentPixelFraction).toFixed(1)}%`,
      "4096px 主档",
    ]) {
      const span = document.createElement("span");
      span.textContent = text;
      metrics.append(span);
    }
    card.querySelector(".select-matte").addEventListener("click", () => setChoice(item, row, {
      status: "selected",
      candidateId: candidate.candidateId,
      candidateDigest: candidate.candidateDigest,
      outputSupersampleSha256: candidate.outputs.supersample4096.sha256,
      master512Sha256: candidate.outputs.master512.sha256,
      notes: row.querySelector("textarea").value,
    }));
    return card;
  }

  function renderRow(item) {
    const row = rowTemplate.content.firstElementChild.cloneNode(true);
    row.dataset.reviewKey = item.reviewKey;
    row.querySelector(".review-code").textContent = item.reviewCode;
    row.querySelector(".review-title").textContent = item.portraitRef;
    row.querySelector(".review-meta").textContent = `${item.candidates.length} 个候选 · 同一 frame · 2 种构图 × 3 档透明度`;
    row.querySelector(".human-note").textContent = `上一轮人审：${item.humanDecision.notes}`;
    row.querySelector(".badges").innerHTML = '<span class="badge warning">后处理复议</span><span class="badge">4096px</span><span class="badge">无模型调用</span>';
    const originals = row.querySelector(".original-grid");
    for (const original of item.originals) originals.append(renderOriginal(item, original));
    const candidates = row.querySelector(".candidate-grid");
    for (const candidate of item.candidates) candidates.append(renderCandidate(item, row, candidate));
    row.querySelector(".refine-button").addEventListener("click", () => {
      const notes = row.querySelector("textarea").value.trim() || "现有透明度候选仍不匹配，需要继续调整暗部保留与背景穿透。";
      setChoice(item, row, { status: "refine", candidateId: null, candidateDigest: null, outputSupersampleSha256: null, master512Sha256: null, notes });
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
    message.textContent = "正在保存并校验透明化决定…";
    try {
      const value = validateImport(buildExport());
      if (typeof window.savePortraitBlackMatteReview === "function") {
        const saved = await window.savePortraitBlackMatteReview(value);
        message.textContent = `保存成功：${saved.path}`;
      } else {
        const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "portrait-pilot-black-matte-decisions.json";
        link.click();
        URL.revokeObjectURL(link.href);
        message.textContent = "已导出到浏览器下载目录";
      }
      exportButton.textContent = "已保存";
    } catch (error) {
      saving = false;
      exportButton.textContent = "导出透明化决定";
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
    if (dataset.schema !== DATA_SCHEMA || dataset.productionReady !== false) throw new Error("透明化数据 schema 或状态非法");
    storageKey = `cf7:portrait-black-matte:${dataset.datasetDigest}`;
    restore();
    document.querySelector("#source-digest").textContent = `source ${dataset.sourceDigest.slice(0, 12)}`;
    document.querySelector("#dataset-digest").textContent = `dataset ${dataset.datasetDigest.slice(0, 12)}`;
    document.querySelector("#candidate-count").textContent = `${dataset.counts.candidateCount} candidates`;
    for (const item of dataset.items) app.append(renderRow(item));
    updateProgress();
    app.dataset.ready = "true";
    window.__portraitBlackMatteTest = { dataset, decisions, storageKey, validateImport, completeDecisions, buildExport };
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
    } catch (error) { message.textContent = `导入失败：${error.message}`; }
    finally { importFile.value = ""; }
  });
  window.addEventListener("black-matte-export-saved", (event) => {
    message.textContent = `保存成功：${event.detail}`;
    exportButton.textContent = "已保存";
  });
  load().catch((error) => {
    message.textContent = `页面初始化失败：${error.message}`;
    app.dataset.ready = "error";
  });
})();
