"use strict";

(async function boot() {
  const app = document.querySelector("#app");
  const list = document.querySelector("#review-list");
  const loadError = document.querySelector("#load-error");
  const resolvedCount = document.querySelector("#resolved-count");
  const totalCount = document.querySelector("#total-count");
  const focusCount = document.querySelector("#focus-count");
  const saveButton = document.querySelector("#save-decisions");
  const commitTitle = document.querySelector("#commit-title");
  const commitDetail = document.querySelector("#commit-detail");
  const toast = document.querySelector("#save-toast");
  const rowViews = new Map();
  let dataset;
  let filter = "all";
  let toastTimer = null;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function localPilotPath(value, suffix, label) {
    if (
      typeof value !== "string" ||
      !value.startsWith("/tmp/portrait-pilot/") ||
      value.includes("..") ||
      value.includes("\\") ||
      value.includes("%") ||
      value.includes("?") ||
      value.includes("#") ||
      value.includes("//") ||
      value.includes("\u0000") ||
      (suffix && !value.endsWith(suffix))
    ) {
      throw new Error(`${label} 路径非法`);
    }
    return value;
  }

  function artifactUrl(record) {
    const path = record && typeof record.path === "string" ? record.path : "";
    localPilotPath(`/${path}`, "", "候选 artifact");
    return `/${path.split("/").map(encodeURIComponent).join("/")}`;
  }

  function showToast(message, error = false) {
    clearTimeout(toastTimer);
    toast.hidden = false;
    toast.textContent = message;
    toast.style.borderColor = error ? "rgba(255,114,111,.65)" : "rgba(85,214,204,.55)";
    toast.style.background = error ? "#2a1719" : "#102320";
    toastTimer = setTimeout(() => { toast.hidden = true; }, 8000);
  }

  try {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath) throw new Error("URL 缺少 data 参数");
    const response = await fetch(
      localPilotPath(dataPath, "/internal-subject-review-data.json", "review-data"),
      { cache: "no-store" },
    );
    if (!response.ok) throw new Error(`review-data 加载失败：HTTP ${response.status}`);
    dataset = await response.json();
    if (
      dataset.schema !== "cf7.enemy-portrait-internal-subject-rescue-review-data.v1" ||
      dataset.status !== "awaiting_human_subject_selection" ||
      !Array.isArray(dataset.items)
    ) {
      throw new Error("review-data schema/status 不受支持");
    }
  } catch (error) {
    loadError.hidden = false;
    loadError.textContent = error && error.message ? error.message : String(error);
    app.dataset.ready = "error";
    return;
  }

  const storageKey = `cf7-internal-subject:${dataset.reviewDigest}`;
  const decisions = new Map();

  function restoreDraft() {
    let draft;
    try {
      draft = JSON.parse(localStorage.getItem(storageKey) || "null");
    } catch {
      return;
    }
    if (!draft || draft.reviewDigest !== dataset.reviewDigest || !Array.isArray(draft.decisions)) return;
    const itemByKey = new Map(dataset.items.map((item) => [item.reviewKey, item]));
    for (const entry of draft.decisions) {
      const item = itemByKey.get(entry.reviewKey);
      if (!item || !["select", "none"].includes(entry.decision)) continue;
      if (entry.decision === "select" && !item.candidates.some((candidate) => candidate.candidateId === entry.candidateId)) continue;
      if (entry.decision === "none" && entry.candidateId !== null) continue;
      decisions.set(entry.reviewKey, {
        decision: entry.decision,
        candidateId: entry.candidateId,
        note: typeof entry.note === "string" ? entry.note.slice(0, 500) : "",
      });
    }
  }

  function persistDraft() {
    const entries = dataset.items.flatMap((item) => {
      const decision = decisions.get(item.reviewKey);
      return decision ? [{ reviewKey: item.reviewKey, ...decision }] : [];
    });
    localStorage.setItem(storageKey, JSON.stringify({ reviewDigest: dataset.reviewDigest, decisions: entries }));
  }

  function modelLabel(selection, item) {
    if (selection.decision === "none") return "无有效主体";
    return item.candidates.find((candidate) => candidate.candidateId === selection.candidateId)?.contactSheetLabel || "未知候选";
  }

  function modelOpinion(roleLabel, selection, item, disagreement) {
    const panel = element("section", `model-opinion${disagreement ? " is-disagreement" : ""}`);
    const top = element("div", "model-topline");
    top.append(element("span", "model-role", roleLabel));
    top.append(element("span", "model-choice", modelLabel(selection, item)));
    top.append(element("span", "model-confidence", `置信 ${Math.round(selection.confidence * 100)}% · 主体 ${Math.round(selection.subjectLikeness * 100)}%`));
    panel.append(top);
    panel.append(element("p", "model-reason", selection.reason));
    if (selection.identityFeatures.length) {
      const features = element("div", "model-features");
      selection.identityFeatures.forEach((feature) => features.append(element("span", "", feature)));
      panel.append(features);
    }
    return panel;
  }

  function candidateButton(item, candidate) {
    const button = element("button", "candidate");
    button.type = "button";
    button.dataset.candidateId = candidate.candidateId;
    button.setAttribute("aria-pressed", "false");
    button.setAttribute("aria-label", `${item.portraitRef} ${candidate.contactSheetLabel}，sprite ${candidate.spriteId}，frame ${candidate.frame}`);

    const visual = element("div", "candidate-visual");
    const image = document.createElement("img");
    image.src = artifactUrl(candidate.artifact);
    image.alt = `${item.portraitRef} ${candidate.contactSheetLabel}`;
    image.loading = "lazy";
    visual.append(image);

    const proposal = item.model.proposal;
    const independent = item.model.independentReview;
    const recommendationRoles = [];
    if (proposal.candidateId === candidate.candidateId) recommendationRoles.push("A");
    if (independent.candidateId === candidate.candidateId) recommendationRoles.push("B");
    if (recommendationRoles.length) {
      const recommendations = element("div", "recommendations");
      recommendations.append(element("span", recommendationRoles.length === 2 ? "both" : "", recommendationRoles.length === 2 ? "A+B" : recommendationRoles[0]));
      visual.append(recommendations);
    }

    const meta = element("div", "candidate-meta");
    const title = element("div", "candidate-title");
    title.append(element("strong", "", candidate.contactSheetLabel));
    title.append(element("span", "tier", candidate.complexityTier));
    meta.append(title);
    meta.append(element("p", "candidate-details", `sprite ${candidate.spriteId} · frame ${candidate.frame}\n${candidate.width}×${candidate.height} · 复杂度位次 ${candidate.complexityRank}`));
    if (candidate.initialRootFrameCandidate) meta.append(element("span", "root-anchor", "根时间轴直连候选"));
    visual.title = "点击选择；可右键图片在新标签页查看原始预览";
    button.append(visual, meta);
    button.addEventListener("click", () => {
      const current = decisions.get(item.reviewKey);
      decisions.set(item.reviewKey, {
        decision: "select",
        candidateId: candidate.candidateId,
        note: current?.note || "",
      });
      persistDraft();
      updateItem(item.reviewKey);
      updateProgress();
    });
    image.addEventListener("contextmenu", () => { image.loading = "eager"; });
    return button;
  }

  function buildItem(item) {
    const article = element("article", `review-card${item.model.comparison.highlightedForHuman ? " is-focus" : ""}`);
    article.id = `row-${item.reviewCode.toLowerCase()}`;
    article.dataset.reviewKey = item.reviewKey;
    article.dataset.focus = String(item.model.comparison.highlightedForHuman);

    const head = element("header", "card-head");
    const identity = element("div", "");
    const line = element("div", "identity-line");
    line.append(element("span", "review-code", item.reviewCode));
    line.append(element("h2", "", item.portraitRef));
    identity.append(line);
    identity.append(element("p", "source-line", `${item.sourceSwf} · root ${item.rootCharacterId}`));
    const state = element("span", "state-badge", item.model.comparison.highlightedForHuman ? "A/B 候选分歧" : "A/B 一致建议");
    head.append(identity, state);

    const modelPanel = element("div", "model-panel");
    const disagreement = !item.model.comparison.candidateAgreement;
    modelPanel.append(
      modelOpinion("LUNA A · 提案", item.model.proposal, item, disagreement),
      modelOpinion("LUNA B · 独立复核", item.model.independentReview, item, disagreement),
    );

    const grid = element("div", "candidate-grid");
    const candidateButtons = new Map();
    item.candidates.forEach((candidate) => {
      const button = candidateButton(item, candidate);
      candidateButtons.set(candidate.candidateId, button);
      grid.append(button);
    });

    const strip = element("div", "decision-strip");
    const none = element("button", "none-choice", "没有有效主体");
    none.type = "button";
    none.setAttribute("aria-pressed", "false");
    none.addEventListener("click", () => {
      const current = decisions.get(item.reviewKey);
      decisions.set(item.reviewKey, { decision: "none", candidateId: null, note: current?.note || "" });
      persistDraft();
      updateItem(item.reviewKey);
      updateProgress();
    });
    const note = element("textarea", "decision-note");
    note.placeholder = "可选：记录为什么选择该内部影片剪辑，或说明模型都遗漏了什么。";
    note.maxLength = 500;
    note.addEventListener("input", () => {
      const current = decisions.get(item.reviewKey);
      if (!current) return;
      current.note = note.value;
      persistDraft();
    });
    strip.append(none, note);
    article.append(head, modelPanel, grid, strip);
    rowViews.set(item.reviewKey, { article, state, candidateButtons, none, note });
    return article;
  }

  function updateItem(reviewKey) {
    const item = dataset.items.find((entry) => entry.reviewKey === reviewKey);
    const view = rowViews.get(reviewKey);
    const decision = decisions.get(reviewKey);
    view.article.classList.toggle("is-resolved", Boolean(decision));
    view.candidateButtons.forEach((button, candidateId) => {
      button.setAttribute("aria-pressed", String(decision?.decision === "select" && decision.candidateId === candidateId));
    });
    view.none.setAttribute("aria-pressed", String(decision?.decision === "none"));
    view.note.value = decision?.note || "";
    if (decision) {
      if (decision.decision === "none") {
        view.state.textContent = "已裁决 · 无有效主体";
      } else {
        const candidate = item.candidates.find((entry) => entry.candidateId === decision.candidateId);
        view.state.textContent = `已裁决 · ${candidate.contactSheetLabel}`;
      }
    } else {
      view.state.textContent = item.model.comparison.highlightedForHuman ? "A/B 候选分歧" : "A/B 一致建议";
    }
    applyFilter();
  }

  function applyFilter() {
    dataset.items.forEach((item) => {
      const view = rowViews.get(item.reviewKey);
      view.article.hidden =
        (filter === "focus" && !item.model.comparison.highlightedForHuman) ||
        (filter === "pending" && decisions.has(item.reviewKey));
    });
  }

  function updateProgress() {
    const resolved = decisions.size;
    const remaining = dataset.items.length - resolved;
    resolvedCount.textContent = String(resolved);
    totalCount.textContent = String(dataset.items.length);
    focusCount.textContent = String(dataset.counts.highlightedForHuman);
    saveButton.disabled = remaining !== 0;
    saveButton.textContent = remaining === 0 ? `保存并导出 ${dataset.items.length} 项决策` : `尚缺 ${remaining} 项`;
    commitTitle.textContent = remaining === 0 ? "人工主体裁决已完整" : `还需裁决 ${remaining} 个单位`;
    commitDetail.textContent = remaining === 0
      ? "保存后才会形成下一阶段可消费的正式输入；仍不会自动推广头像。"
      : "模型建议不会自动成为人工答案；点击候选或“没有有效主体”。";
  }

  function payload() {
    return {
      schema: "cf7.enemy-portrait-internal-subject-human-decisions.v1",
      batchId: dataset.batchId,
      sourceDigest: dataset.sourceDigest,
      manifestDigest: dataset.manifestDigest,
      modelReportDigest: dataset.modelReportDigest,
      reviewDigest: dataset.reviewDigest,
      reviewedAt: new Date().toISOString(),
      decisions: dataset.items.map((item) => ({ reviewKey: item.reviewKey, ...decisions.get(item.reviewKey) })),
    };
  }

  function downloadFallback(value) {
    const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json;charset=utf-8" });
    const anchor = document.createElement("a");
    anchor.href = URL.createObjectURL(blob);
    anchor.download = "internal-subject-human-decisions.json";
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(anchor.href), 1000);
  }

  restoreDraft();
  dataset.items.forEach((item) => list.append(buildItem(item)));
  dataset.items.forEach((item) => updateItem(item.reviewKey));
  updateProgress();

  document.querySelectorAll(".filter").forEach((button) => {
    button.addEventListener("click", () => {
      filter = button.dataset.filter;
      document.querySelectorAll(".filter").forEach((entry) => entry.classList.toggle("is-active", entry === button));
      applyFilter();
    });
  });

  document.querySelector("#next-pending").addEventListener("click", () => {
    const next = dataset.items.find((item) => !decisions.has(item.reviewKey));
    if (!next) {
      showToast("17 项都已裁决，可以保存导出。", false);
      return;
    }
    filter = "all";
    document.querySelectorAll(".filter").forEach((entry) => entry.classList.toggle("is-active", entry.dataset.filter === "all"));
    applyFilter();
    rowViews.get(next.reviewKey).article.scrollIntoView({ block: "start" });
  });

  saveButton.addEventListener("click", async () => {
    if (decisions.size !== dataset.items.length) return;
    saveButton.disabled = true;
    saveButton.textContent = "正在校验并保存…";
    const value = payload();
    try {
      if (typeof window.saveInternalSubjectReviewDecisions === "function") {
        const saved = await window.saveInternalSubjectReviewDecisions(value);
        localStorage.removeItem(storageKey);
        showToast(`已保存：${saved.path}；版本归档：${saved.archivePath}`);
      } else {
        downloadFallback(value);
        showToast("已生成非空 JSON 下载；当前不是专用启动器，未写入版本归档。", false);
      }
      commitTitle.textContent = "决策已保存导出";
      commitDetail.textContent = "可以关闭页面；下一阶段将依据人工选择导出矢量主体并进入头像裁剪。";
    } catch (error) {
      showToast(`保存失败：${error && error.message ? error.message : String(error)}`, true);
    } finally {
      saveButton.disabled = false;
      saveButton.textContent = `再次保存并归档 ${dataset.items.length} 项决策`;
    }
  });

  window.addEventListener("internal-subject-export-saved", (event) => {
    showToast(`下载已落盘：${event.detail}`);
  });

  app.dataset.ready = "true";
}());
