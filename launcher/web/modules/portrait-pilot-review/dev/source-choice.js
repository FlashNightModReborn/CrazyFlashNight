(() => {
  "use strict";

  const DATA_SCHEMA = "cf7.enemy-portrait-source-choice-candidates.v1";
  const app = document.querySelector("#app");
  const rowTemplate = document.querySelector("#row-template");
  const sourceTemplate = document.querySelector("#source-template");
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

  function validateImport(value) {
    exactKeys(value, ["schema", "batchId", "sourceDigest", "manifestDigest", "complete", "exportedAt", "choices"], "选源决定文件");
    if (
      value.schema !== dataset.decisionSchema ||
      value.batchId !== dataset.batchId ||
      value.sourceDigest !== dataset.sourceDigest ||
      value.manifestDigest !== dataset.manifestDigest
    ) throw new Error("选源决定属于旧批次或其他来源闭包");
    if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new Error("选源决定未完整导出");
    exactKeys(value.choices, dataset.items.map((item) => item.reviewKey), "选源决定映射");
    for (const item of dataset.items) {
      const choice = value.choices[item.reviewKey];
      exactKeys(choice, ["status", "sourceCandidateKey", "notes", "updatedAt"], `选源决定 ${item.reviewKey}`);
      if (!["selected", "manual_maintenance"].includes(choice.status) || Number.isNaN(Date.parse(choice.updatedAt))) {
        throw new Error(`选源状态或时间非法：${item.reviewKey}`);
      }
      if (typeof choice.notes !== "string" || choice.notes.length > 1000) throw new Error(`选源备注非法：${item.reviewKey}`);
      const source = choice.sourceCandidateKey === null
        ? null
        : item.sources.find((candidate) => candidate.sourceCandidateKey === choice.sourceCandidateKey);
      if (choice.status === "selected" && (!source || source.renderable !== true)) throw new Error(`必须选择可渲染来源：${item.reviewKey}`);
      if (choice.status === "manual_maintenance" && (choice.sourceCandidateKey !== null || !choice.notes.trim())) {
        throw new Error(`人工维护必须填写备注：${item.reviewKey}`);
      }
    }
    return value;
  }

  function rowComplete(choice) {
    return Boolean(choice && (
      (choice.status === "selected" && typeof choice.sourceCandidateKey === "string") ||
      (choice.status === "manual_maintenance" && choice.sourceCandidateKey === null && choice.notes.trim())
    ));
  }

  function completeDecisions(value = decisions) {
    return dataset.items.every((item) => rowComplete(value[item.reviewKey]));
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify({
      schema: "cf7.enemy-portrait-source-choice-local.v1",
      manifestDigest: dataset.manifestDigest,
      decisions,
    }));
  }

  function restore() {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return;
    try {
      const value = JSON.parse(raw);
      if (value.schema === "cf7.enemy-portrait-source-choice-local.v1" && value.manifestDigest === dataset.manifestDigest) {
        Object.assign(decisions, value.decisions || {});
      }
    } catch {
      localStorage.removeItem(storageKey);
    }
  }

  function updateProgress() {
    const done = dataset.items.filter((item) => rowComplete(decisions[item.reviewKey])).length;
    document.querySelector("#progress-count").textContent = `${done} / ${dataset.items.length}`;
    document.querySelector("#progress-label").textContent = done === dataset.items.length ? "可导出" : "逐项选择来源";
    document.querySelector("#progress-bar").style.width = `${100 * done / dataset.items.length}%`;
    exportButton.disabled = saving || done !== dataset.items.length;
  }

  function renderDecision(item, row) {
    const choice = decisions[item.reviewKey];
    row.dataset.reviewed = String(rowComplete(choice));
    for (const card of row.querySelectorAll(".source-card")) {
      card.dataset.selected = String(choice?.status === "selected" && card.dataset.sourceKey === choice.sourceCandidateKey);
    }
    const manualButton = row.querySelector(".manual-button");
    manualButton.setAttribute("aria-pressed", String(choice?.status === "manual_maintenance"));
    const textarea = row.querySelector("textarea");
    if (textarea.value !== (choice?.notes || "")) textarea.value = choice?.notes || "";
    const summary = row.querySelector(".decision-summary");
    if (!choice) summary.textContent = "尚未选择";
    else if (choice.status === "manual_maintenance") summary.textContent = choice.notes.trim() ? "已转人工维护" : "请填写人工维护原因";
    else summary.textContent = `已选 ${choice.sourceCandidateKey}`;
  }

  function setDecision(item, row, status, sourceCandidateKey) {
    decisions[item.reviewKey] = {
      status,
      sourceCandidateKey,
      notes: row.querySelector("textarea").value,
      updatedAt: new Date().toISOString(),
    };
    persist();
    renderDecision(item, row);
    updateProgress();
  }

  function buildSourceCard(item, source) {
    const fragment = sourceTemplate.content.cloneNode(true);
    const card = fragment.querySelector(".source-card");
    card.dataset.sourceKey = source.sourceCandidateKey;
    card.dataset.renderable = String(source.renderable);
    card.querySelector(".source-code").textContent = source.sourceCode;
    card.querySelector(".source-status").textContent = source.renderable ? (source.orphan ? "orphan · 可定位" : "可自动定位") : "不可自动定位";
    card.querySelector(".source-swf").textContent = source.swf;
    card.querySelector(".source-symbol").textContent = source.symbolName || "symbolName 缺失（orphan）";
    const strategy = card.querySelector(".source-strategy");
    if (source.renderable) {
      strategy.textContent = source.renderStrategy === "first_frame_named_man_instance"
        ? `内部 man · sprite ${source.renderCharacterId} · ${source.renderDeclaredFrameCount} 帧`
        : `root fallback · sprite ${source.renderCharacterId} · ${source.renderDeclaredFrameCount} 帧`;
      if (source.renderStrategyWarning) strategy.textContent += " · 注意外层 UI 干扰";
      const gif = card.querySelector(".gif-link");
      gif.href = assetUrl(source.ffdecGif);
      for (const frame of source.frames) {
        const link = document.createElement("a");
        link.href = assetUrl(frame.artifact);
        link.target = "_blank";
        link.rel = "noreferrer";
        link.title = `${source.sourceCode} · frame ${frame.frame}`;
        const image = document.createElement("img");
        image.src = assetUrl(frame.artifact);
        image.alt = `${item.portraitRef} ${source.sourceCode} 第 ${frame.frame} 帧`;
        image.loading = "lazy";
        link.append(image);
        card.querySelector(".frame-strip").append(link);
      }
    } else {
      strategy.textContent = "资产映射只保留 orphan 事实，没有可绑定的 symbolName。";
      const blocked = card.querySelector(".unrenderable-message");
      blocked.hidden = false;
      blocked.textContent = "无法用 linkage/库路径自动定位。若必须保留这一来源，需要在 CS6 中人工确认并维护映射。";
      card.querySelector(".select-source").disabled = true;
    }
    return card;
  }

  function renderRows() {
    for (const item of dataset.items) {
      const fragment = rowTemplate.content.cloneNode(true);
      const row = fragment.querySelector(".source-review-row");
      row.dataset.reviewKey = item.reviewKey;
      row.querySelector(".review-code").textContent = item.reviewCode;
      row.querySelector(".review-title").textContent = item.portraitRef;
      row.querySelector(".review-meta").textContent = `${item.reviewKey} · 输出仍为 default`;
      const badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = item.sourceClassification;
      row.querySelector(".badges").append(badge);
      const grid = row.querySelector(".source-grid");
      for (const source of item.sources) {
        const card = buildSourceCard(item, source);
        card.querySelector(".select-source").addEventListener("click", () => setDecision(item, row, "selected", source.sourceCandidateKey));
        grid.append(card);
      }
      row.querySelector(".manual-button").addEventListener("click", () => setDecision(item, row, "manual_maintenance", null));
      row.querySelector("textarea").addEventListener("input", (event) => {
        const choice = decisions[item.reviewKey];
        if (!choice) return;
        choice.notes = event.target.value;
        choice.updatedAt = new Date().toISOString();
        persist();
        renderDecision(item, row);
        updateProgress();
      });
      app.append(row);
      renderDecision(item, row);
    }
  }

  function buildExport() {
    if (!completeDecisions()) throw new Error("仍有未完成来源裁决");
    const value = {
      schema: dataset.decisionSchema,
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      manifestDigest: dataset.manifestDigest,
      complete: true,
      exportedAt: new Date().toISOString(),
      choices: Object.fromEntries(dataset.items.map((item) => [item.reviewKey, decisions[item.reviewKey]])),
    };
    return validateImport(value);
  }

  async function exportDecisions() {
    if (saving) return;
    saving = true;
    exportButton.disabled = true;
    exportButton.textContent = "保存中…";
    try {
      const value = buildExport();
      if (typeof window.savePortraitSourceChoiceDecisions === "function") {
        const saved = await window.savePortraitSourceChoiceDecisions(value);
        message.textContent = `保存成功：${saved.path}；归档：${saved.archivePath}`;
      } else {
        const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "portrait-pilot-source-choice-decisions.json";
        link.click();
        URL.revokeObjectURL(link.href);
        message.textContent = "已交给浏览器下载；请保留完整 JSON。";
      }
      exportButton.textContent = "已保存（可再次导出）";
    } catch (error) {
      message.textContent = `保存失败：${error.message}`;
      exportButton.textContent = "导出选源决定";
    } finally {
      saving = false;
      updateProgress();
    }
  }

  async function importDecisions(file) {
    const value = validateImport(JSON.parse(await file.text()));
    for (const key of Object.keys(decisions)) delete decisions[key];
    Object.assign(decisions, value.choices);
    persist();
    for (const item of dataset.items) {
      const row = [...app.querySelectorAll(".source-review-row")].find((entry) => entry.dataset.reviewKey === item.reviewKey);
      renderDecision(item, row);
    }
    updateProgress();
    message.textContent = `已导入 ${dataset.items.length} 条当前批决定。`;
  }

  async function start() {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath || !dataPath.startsWith("/tmp/portrait-pilot/") || dataPath.includes("..") || !dataPath.endsWith("/source-choice-data.json")) {
      throw new Error("缺少受约束的 source-choice-data 路径");
    }
    dataset = await fetch(dataPath, { cache: "no-store" }).then((response) => {
      if (!response.ok) throw new Error(`加载 source choice data 失败：HTTP ${response.status}`);
      return response.json();
    });
    if (dataset.schema !== DATA_SCHEMA || dataset.productionReady !== false || dataset.gates?.productionWrites !== false) {
      throw new Error("source choice data schema 或安全门非法");
    }
    storageKey = `cf7-portrait-source-choice:${dataset.manifestDigest}`;
    restore();
    document.querySelector("#source-digest").textContent = `source ${dataset.sourceDigest.slice(0, 12)}…`;
    document.querySelector("#manifest-digest").textContent = `manifest ${dataset.manifestDigest.slice(0, 12)}…`;
    document.querySelector("#candidate-count").textContent = `${dataset.counts.identityCount} identities · ${dataset.counts.sourceCandidateCount} sources`;
    renderRows();
    updateProgress();
    app.dataset.ready = "true";
    window.__portraitSourceChoiceTest = { dataset, storageKey, decisions, validateImport, completeDecisions, buildExport };
  }

  exportButton.addEventListener("click", exportDecisions);
  importButton.addEventListener("click", () => importFile.click());
  importFile.addEventListener("change", async () => {
    if (!importFile.files?.[0]) return;
    try {
      await importDecisions(importFile.files[0]);
    } catch (error) {
      message.textContent = `导入失败：${error.message}`;
    } finally {
      importFile.value = "";
    }
  });
  window.addEventListener("source-choice-export-saved", (event) => { message.textContent = `选源决定已保存：${event.detail}`; });
  start().catch((error) => {
    message.textContent = error.message;
    app.dataset.ready = "error";
  });
})();
