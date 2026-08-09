"use strict";

(async function boot() {
  const app = document.querySelector("#app");
  const target = document.querySelector("#target");
  const loadError = document.querySelector("#load-error");
  const saveButton = document.querySelector("#save");
  const title = document.querySelector("#commit-title");
  const detail = document.querySelector("#commit-detail");
  const toast = document.querySelector("#toast");
  let dataset;
  let canonical;
  let item;
  let prior;
  let selected = null;
  let note;
  const buttons = new Map();

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  async function fetchJson(path, label) {
    const response = await fetch(path, { cache: "no-store" });
    if (!response.ok) throw new Error(`${label} 加载失败：HTTP ${response.status}`);
    return response.json();
  }

  function showToast(message, error = false) {
    toast.hidden = false;
    toast.textContent = message;
    toast.style.borderColor = error ? "#ff7278" : "#55d6cc";
    toast.style.background = error ? "#2a1416" : "#10231f";
  }

  function candidateLabel(selection) {
    if (selection.decision === "none") return "无有效主体";
    return item.candidates.find((candidate) => candidate.candidateId === selection.candidateId)?.contactSheetLabel || selection.candidateId;
  }

  function renderModel(label, selection) {
    const panel = element("section", "model");
    const head = element("div");
    head.append(element("strong", "", label), element("span", "choice", candidateLabel(selection)));
    panel.append(head, element("p", "", selection.reason));
    return panel;
  }

  function choose(decision, candidateId) {
    selected = { decision, candidateId };
    buttons.forEach((button, id) => button.setAttribute("aria-pressed", String(decision === "select" && id === candidateId)));
    document.querySelector(".none").setAttribute("aria-pressed", String(decision === "none"));
    saveButton.disabled = false;
    title.textContent = "本项已重新确认";
    detail.textContent = decision === "select" ? `将完整保存为 ${candidateLabel(selected)}` : "将完整保存为“没有有效主体”";
  }

  try {
    const params = new URLSearchParams(location.search);
    const dataPath = params.get("data");
    const decisionsPath = params.get("decisions");
    const reviewKey = params.get("reviewKey");
    if (!dataPath || !decisionsPath || !reviewKey) throw new Error("URL 缺少 data、decisions 或 reviewKey 参数");
    [dataset, canonical] = await Promise.all([
      fetchJson(dataPath, "review-data"),
      fetchJson(decisionsPath, "human decisions"),
    ]);
    if (dataset.schema !== "cf7.enemy-portrait-internal-subject-rescue-review-data.v1" || !Array.isArray(dataset.items)) {
      throw new Error("review-data schema 不受支持");
    }
    if (
      canonical.schema !== "cf7.enemy-portrait-internal-subject-human-decisions.v1" ||
      canonical.reviewDigest !== dataset.reviewDigest ||
      !Array.isArray(canonical.decisions) ||
      canonical.decisions.length !== dataset.items.length
    ) {
      throw new Error("human decisions 与 review-data 不闭合");
    }
    item = dataset.items.find((entry) => entry.reviewKey === reviewKey);
    prior = canonical.decisions.find((entry) => entry.reviewKey === reviewKey);
    if (!item || !prior) throw new Error(`复核目标不存在：${reviewKey}`);
  } catch (error) {
    loadError.hidden = false;
    loadError.textContent = error && error.message ? error.message : String(error);
    app.dataset.ready = "error";
    return;
  }

  const article = element("article", "card");
  const head = element("header", "card-head");
  const identityWrap = element("div");
  const identity = element("div", "identity");
  identity.append(element("span", "code", item.reviewCode), element("h2", "", item.portraitRef));
  identityWrap.append(identity, element("p", "source", `${item.sourceSwf} · root ${item.rootCharacterId}`));
  head.append(identityWrap, element("span", "old-badge", `旧选择：${candidateLabel(prior)}`));

  const models = element("div", "models");
  models.append(
    renderModel("LUNA A · 提案", item.model.proposal),
    renderModel("LUNA B · 独立复核", item.model.independentReview),
  );

  const grid = element("div", "candidates");
  item.candidates.forEach((candidate) => {
    const button = element("button", `candidate${prior.candidateId === candidate.candidateId ? " is-prior" : ""}`);
    button.type = "button";
    button.setAttribute("aria-pressed", "false");
    button.dataset.candidateId = candidate.candidateId;
    const recommended = [];
    if (item.model.proposal.candidateId === candidate.candidateId) recommended.push("A");
    if (item.model.independentReview.candidateId === candidate.candidateId) recommended.push("B");
    if (recommended.length) button.append(element("span", "recommend", recommended.length === 2 ? "A+B 建议" : `${recommended[0]} 建议`));
    const visual = element("div", "visual");
    const image = document.createElement("img");
    image.src = `/${candidate.artifact.path}`;
    image.alt = `${item.portraitRef} ${candidate.contactSheetLabel}`;
    visual.append(image);
    const meta = element("div", "meta");
    meta.append(element("strong", "", candidate.contactSheetLabel));
    meta.append(document.createTextNode(`\nsprite ${candidate.spriteId} · frame ${candidate.frame}\n${candidate.width}×${candidate.height} · 复杂度位次 ${candidate.complexityRank}`));
    button.append(visual, meta);
    button.addEventListener("click", () => choose("select", candidate.candidateId));
    buttons.set(candidate.candidateId, button);
    grid.append(button);
  });

  const decision = element("div", "decision");
  const none = element("button", "none", "没有有效主体");
  none.type = "button";
  none.setAttribute("aria-pressed", "false");
  none.addEventListener("click", () => choose("none", null));
  note = document.createElement("textarea");
  note.maxLength = 500;
  note.value = prior.note || "";
  note.placeholder = "可选：记录这次修正的理由。";
  decision.append(none, note);
  article.append(head, models, grid, decision);
  target.append(article);

  saveButton.addEventListener("click", async () => {
    if (!selected) return;
    const payload = {
      ...canonical,
      reviewedAt: new Date().toISOString(),
      decisions: canonical.decisions.map((entry) => entry.reviewKey === item.reviewKey ? {
        reviewKey: entry.reviewKey,
        decision: selected.decision,
        candidateId: selected.candidateId,
        note: note.value,
      } : entry),
    };
    saveButton.disabled = true;
    saveButton.textContent = "正在校验并保存…";
    try {
      if (typeof window.saveInternalSubjectReviewDecisions !== "function") throw new Error("当前不是专用复核启动器");
      const saved = await window.saveInternalSubjectReviewDecisions(payload);
      title.textContent = "修正已保存导出";
      detail.textContent = "可以关闭页面；其余 16 项保持原决定。";
      showToast(`已保存：${saved.path}；版本归档：${saved.archivePath}`);
      saveButton.textContent = "再次保存本次复核";
    } catch (error) {
      showToast(`保存失败：${error && error.message ? error.message : String(error)}`, true);
      saveButton.textContent = "重试保存";
    } finally {
      saveButton.disabled = false;
    }
  });

  app.dataset.ready = "true";
}());
