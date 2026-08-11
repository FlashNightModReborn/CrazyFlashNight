"use strict";

(() => {
  const DATA_SCHEMA = "cf7.portrait-pilot-framing-guidance-data.v1";
  const app = document.getElementById("app");
  const template = document.getElementById("guidance-card-template");
  const exportButton = document.getElementById("export-button");
  const importButton = document.getElementById("import-button");
  const importFile = document.getElementById("import-file");
  const message = document.getElementById("message");
  let dataset = null;
  let states = {};
  let storageKey = null;
  let exportInFlight = false;
  const controllers = new Map();

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

  function choiceFor(item, sourceRole) {
    return item.choices.find((choice) => choice.sourceRole === sourceRole) || null;
  }

  function validCropBox(choice, cropBox) {
    if (!Array.isArray(cropBox) || cropBox.length !== 4 || cropBox.some((value) => typeof value !== "number" || !Number.isFinite(value))) return false;
    const [x0, y0, x1, y1] = cropBox;
    if (cropBox.some((value) => value < -0.5 || value > 1.5) || x0 >= x1 || y0 >= y1) return false;
    const width = (x1 - x0) * choice.candidateWidth;
    const height = (y1 - y0) * choice.candidateHeight;
    const minimumSide = Math.max(48, choice.minimumCandidateCropSide, Math.min(choice.candidateWidth, choice.candidateHeight) * 0.1);
    if (Math.abs(width - height) > 1.5 || Math.min(width, height) < minimumSide) return false;
    const visibleWidth = Math.max(0, Math.min(1, x1) - Math.max(0, x0)) * choice.candidateWidth;
    const visibleHeight = Math.max(0, Math.min(1, y1) - Math.max(0, y0)) * choice.candidateHeight;
    return (visibleWidth * visibleHeight) / (width * height) >= 0.2;
  }

  function validState(item, state, requireConfirmed) {
    if (!state || !exactKeys(state, ["sourceRole", "cropBox", "confirmed", "updatedAt"])) return false;
    const choice = choiceFor(item, state.sourceRole);
    if (!choice || !validCropBox(choice, state.cropBox) || typeof state.confirmed !== "boolean") return false;
    if (typeof state.updatedAt !== "string" || Number.isNaN(Date.parse(state.updatedAt))) return false;
    return !requireConfirmed || state.confirmed;
  }

  function entryFromState(item, state) {
    const choice = choiceFor(item, state.sourceRole);
    return {
      sourceRole: state.sourceRole,
      candidateId: choice.candidateId,
      sourceCandidateSha256: choice.sourceCandidate.sha256,
      cropBox: state.cropBox.map((value) => Number(value.toFixed(9))),
      updatedAt: state.updatedAt,
    };
  }

  function validGuidanceEntry(item, entry) {
    if (!entry || !exactKeys(entry, ["sourceRole", "candidateId", "sourceCandidateSha256", "cropBox", "updatedAt"])) return false;
    const choice = choiceFor(item, entry.sourceRole);
    return Boolean(
      choice &&
      entry.candidateId === choice.candidateId &&
      entry.sourceCandidateSha256 === choice.sourceCandidate.sha256 &&
      validCropBox(choice, entry.cropBox) &&
      typeof entry.updatedAt === "string" &&
      !Number.isNaN(Date.parse(entry.updatedAt))
    );
  }

  function completeStateMap(candidate = states) {
    return dataset.items.every((item) => validState(item, candidate[item.reviewKey], true));
  }

  function validateImport(value) {
    if (!exactKeys(value, ["schema", "batchId", "guidanceDigest", "parentReceiptDigest", "complete", "exportedAt", "guidance"])) {
      throw new Error("框选指导文件字段不闭合");
    }
    if (
      value.schema !== dataset.guidanceSchema ||
      value.batchId !== dataset.batchId ||
      value.guidanceDigest !== dataset.guidanceDigest ||
      value.parentReceiptDigest !== dataset.parent.receiptDigest
    ) throw new Error("框选指导属于旧批次或其他父回执");
    if (value.complete !== true || Number.isNaN(Date.parse(value.exportedAt))) throw new Error("框选指导未完整导出");
    const expected = dataset.items.map((item) => item.reviewKey).sort();
    const actual = Object.keys(value.guidance || {}).sort();
    if (JSON.stringify(expected) !== JSON.stringify(actual)) throw new Error("框选指导没有覆盖全部待调整行");
    if (!dataset.items.every((item) => validGuidanceEntry(item, value.guidance[item.reviewKey]))) {
      throw new Error("框选指导含未知来源、候选 hash 或非法正方形");
    }
    return value.guidance;
  }

  function initialState(item) {
    const sourceRole = item.preferredRoleHint || "proposal";
    const choice = choiceFor(item, sourceRole) || item.choices[0];
    const crop = clampCrop(choice, cropPixels(choice, choice.initialCropBox));
    return {
      sourceRole: choice.sourceRole,
      cropBox: cropNormalized(choice, crop),
      confirmed: false,
      updatedAt: new Date().toISOString(),
    };
  }

  function persist() {
    localStorage.setItem(storageKey, JSON.stringify({
      schema: "cf7.portrait-pilot-framing-guidance-local.v1",
      guidanceDigest: dataset.guidanceDigest,
      states,
    }));
  }

  function loadLocal() {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return Object.fromEntries(dataset.items.map((item) => [item.reviewKey, initialState(item)]));
    try {
      const value = JSON.parse(raw);
      if (
        !exactKeys(value, ["schema", "guidanceDigest", "states"]) ||
        value.schema !== "cf7.portrait-pilot-framing-guidance-local.v1" ||
        value.guidanceDigest !== dataset.guidanceDigest
      ) throw new Error("stale");
      return Object.fromEntries(dataset.items.map((item) => [
        item.reviewKey,
        validState(item, value.states?.[item.reviewKey], false) ? value.states[item.reviewKey] : initialState(item),
      ]));
    } catch {
      return Object.fromEntries(dataset.items.map((item) => [item.reviewKey, initialState(item)]));
    }
  }

  function badge(text, kind = "") {
    const element = document.createElement("span");
    element.className = `badge ${kind}`.trim();
    element.textContent = text;
    return element;
  }

  function imageElement(record, alt, className = "") {
    const image = document.createElement("img");
    image.src = artifactUrl(record);
    image.alt = alt;
    image.className = className;
    return image;
  }

  function loadImage(record) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error(`图片加载失败：${record.path}`));
      image.src = artifactUrl(record);
    });
  }

  function cropPixels(choice, cropBox) {
    return {
      x: cropBox[0] * choice.candidateWidth,
      y: cropBox[1] * choice.candidateHeight,
      side: ((cropBox[2] - cropBox[0]) * choice.candidateWidth + (cropBox[3] - cropBox[1]) * choice.candidateHeight) / 2,
    };
  }

  function cropNormalized(choice, crop) {
    return [
      crop.x / choice.candidateWidth,
      crop.y / choice.candidateHeight,
      (crop.x + crop.side) / choice.candidateWidth,
      (crop.y + crop.side) / choice.candidateHeight,
    ].map((value) => Number(value.toFixed(9)));
  }

  function clampCrop(choice, crop) {
    const minimum = Math.max(48, choice.minimumCandidateCropSide, Math.min(choice.candidateWidth, choice.candidateHeight) * 0.1);
    const maximum = Math.min(choice.candidateWidth * 2, choice.candidateHeight * 2);
    const side = Math.min(maximum, Math.max(minimum, crop.side));
    return {
      x: Math.min(choice.candidateWidth * 1.5 - side, Math.max(-choice.candidateWidth * 0.5, crop.x)),
      y: Math.min(choice.candidateHeight * 1.5 - side, Math.max(-choice.candidateHeight * 0.5, crop.y)),
      side,
    };
  }

  function visibleFraction(choice, crop) {
    const width = Math.max(0, Math.min(choice.candidateWidth, crop.x + crop.side) - Math.max(0, crop.x));
    const height = Math.max(0, Math.min(choice.candidateHeight, crop.y + crop.side) - Math.max(0, crop.y));
    return (width * height) / (crop.side * crop.side);
  }

  function drawChecker(context, width, height, cell = 20) {
    context.fillStyle = "#202833";
    context.fillRect(0, 0, width, height);
    context.fillStyle = "#2a3441";
    for (let y = 0; y < height; y += cell) {
      for (let x = 0; x < width; x += cell) {
        if ((x / cell + y / cell) % 2 === 0) context.fillRect(x, y, cell, cell);
      }
    }
  }

  function drawPreview(canvas, highResolutionImage, choice, crop) {
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, canvas.width, canvas.height);
    drawChecker(context, canvas.width, canvas.height, Math.max(8, canvas.width / 8));
    const scaleX = highResolutionImage.naturalWidth / choice.sourceSize[0];
    const scaleY = highResolutionImage.naturalHeight / choice.sourceSize[1];
    const nativeSide = crop.side * ((scaleX + scaleY) / 2);
    const drawScale = canvas.width / nativeSide;
    const fullX = (choice.sourceCropBounds[0] + crop.x) * scaleX;
    const fullY = (choice.sourceCropBounds[1] + crop.y) * scaleY;
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(
      highResolutionImage,
      -fullX * drawScale,
      -fullY * drawScale,
      highResolutionImage.naturalWidth * drawScale,
      highResolutionImage.naturalHeight * drawScale,
    );
  }

  function createController(card, item) {
    const canvas = card.querySelector(".source-canvas");
    const largePreview = card.querySelector(".preview-large");
    const preview80 = card.querySelector(".preview-80");
    const slider = card.querySelector(".zoom-slider");
    const readout = card.querySelector(".crop-readout");
    const visibility = card.querySelector(".visibility-readout");
    const confirmButton = card.querySelector(".confirm-guidance");
    const confirmState = card.querySelector(".confirm-state");
    const images = new Map();
    let interaction = null;
    let view = null;

    function current() {
      const state = states[item.reviewKey];
      const choice = choiceFor(item, state.sourceRole);
      const loaded = images.get(state.sourceRole);
      return { state, choice, candidateImage: loaded?.candidate, highResolutionImage: loaded?.highResolution };
    }

    function setCrop(crop, changed = true) {
      const { state, choice } = current();
      const next = clampCrop(choice, crop);
      state.cropBox = cropNormalized(choice, next);
      if (changed) state.confirmed = false;
      state.updatedAt = new Date().toISOString();
      persist();
      draw();
      updateProgress();
    }

    function transform(choice) {
      const worldWidth = choice.candidateWidth * 1.5;
      const worldHeight = choice.candidateHeight * 1.5;
      const scale = Math.min(canvas.width / worldWidth, canvas.height / worldHeight);
      return {
        scale,
        offsetX: (canvas.width - worldWidth * scale) / 2 + choice.candidateWidth * 0.25 * scale,
        offsetY: (canvas.height - worldHeight * scale) / 2 + choice.candidateHeight * 0.25 * scale,
      };
    }

    function canvasPoint(event) {
      const rect = canvas.getBoundingClientRect();
      return {
        x: (event.clientX - rect.left) * canvas.width / rect.width,
        y: (event.clientY - rect.top) * canvas.height / rect.height,
      };
    }

    function sourcePoint(event) {
      const point = canvasPoint(event);
      return { x: (point.x - view.offsetX) / view.scale, y: (point.y - view.offsetY) / view.scale };
    }

    function draw() {
      const { state, choice, candidateImage, highResolutionImage } = current();
      if (!candidateImage || !highResolutionImage) return;
      const crop = cropPixels(choice, state.cropBox);
      view = transform(choice);
      const context = canvas.getContext("2d");
      context.clearRect(0, 0, canvas.width, canvas.height);
      drawChecker(context, canvas.width, canvas.height);
      context.imageSmoothingEnabled = true;
      context.drawImage(
        candidateImage,
        view.offsetX,
        view.offsetY,
        choice.candidateWidth * view.scale,
        choice.candidateHeight * view.scale,
      );
      const box = {
        x: view.offsetX + crop.x * view.scale,
        y: view.offsetY + crop.y * view.scale,
        side: crop.side * view.scale,
      };
      context.save();
      context.beginPath();
      context.rect(0, 0, canvas.width, canvas.height);
      context.rect(box.x, box.y, box.side, box.side);
      context.fillStyle = "rgba(3, 8, 13, .58)";
      context.fill("evenodd");
      context.restore();
      context.strokeStyle = state.confirmed ? "#52c7b8" : "#f2bd5d";
      context.lineWidth = 3;
      context.strokeRect(box.x, box.y, box.side, box.side);
      context.strokeStyle = "rgba(255,255,255,.45)";
      context.lineWidth = 1;
      for (const fraction of [1 / 3, 2 / 3]) {
        context.beginPath();
        context.moveTo(box.x + box.side * fraction, box.y);
        context.lineTo(box.x + box.side * fraction, box.y + box.side);
        context.moveTo(box.x, box.y + box.side * fraction);
        context.lineTo(box.x + box.side, box.y + box.side * fraction);
        context.stroke();
      }
      context.fillStyle = state.confirmed ? "#52c7b8" : "#f2bd5d";
      for (const [x, y] of [[box.x, box.y], [box.x + box.side, box.y], [box.x, box.y + box.side], [box.x + box.side, box.y + box.side]]) {
        context.fillRect(x - 6, y - 6, 12, 12);
      }
      drawPreview(largePreview, highResolutionImage, choice, crop);
      drawPreview(preview80, highResolutionImage, choice, crop);
      const initialSide = cropPixels(choice, choice.initialCropBox).side;
      const zoom = initialSide / crop.side;
      const fraction = visibleFraction(choice, crop);
      readout.textContent = `${choice.candidateId} · frame ${choice.frame} · ${crop.side.toFixed(1)} px · ${zoom.toFixed(2)}×`;
      visibility.textContent = `候选可见面积 ${(fraction * 100).toFixed(1)}% · ${state.confirmed ? "已确认" : "修改后待确认"}`;
      const minimum = Math.max(48, choice.minimumCandidateCropSide, Math.min(choice.candidateWidth, choice.candidateHeight) * 0.1);
      const maximum = Math.min(choice.candidateWidth * 2, choice.candidateHeight * 2);
      slider.value = String(Math.round(Math.log(crop.side / minimum) / Math.log(maximum / minimum) * 1000));
      confirmButton.classList.toggle("confirmed", state.confirmed);
      confirmButton.textContent = state.confirmed ? "已确认此框选 ✓" : "确认此框选";
      confirmState.textContent = state.confirmed ? `已绑定 ${choice.label} / ${choice.candidateId}` : "尚未确认；任何移动或缩放都会撤销旧确认";
      card.dataset.confirmed = String(state.confirmed);
      for (const button of card.querySelectorAll(".source-choice-buttons button")) {
        button.classList.toggle("selected", button.dataset.role === state.sourceRole);
      }
      for (const reference of card.querySelectorAll(".source-reference")) {
        reference.classList.toggle("selected", reference.dataset.role === state.sourceRole);
      }
    }

    function changeRole(sourceRole) {
      const state = states[item.reviewKey];
      const choice = choiceFor(item, sourceRole);
      state.sourceRole = sourceRole;
      state.cropBox = [...choice.initialCropBox];
      state.confirmed = false;
      state.updatedAt = new Date().toISOString();
      persist();
      draw();
      updateProgress();
    }

    for (const button of card.querySelectorAll(".source-choice-buttons button")) {
      button.addEventListener("click", () => changeRole(button.dataset.role));
    }
    card.querySelector(".reset-crop").addEventListener("click", () => {
      const { choice } = current();
      setCrop(cropPixels(choice, choice.initialCropBox));
    });
    card.querySelector(".zoom-in").addEventListener("click", () => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const center = { x: crop.x + crop.side / 2, y: crop.y + crop.side / 2 };
      crop.side /= 1.1;
      crop.x = center.x - crop.side / 2;
      crop.y = center.y - crop.side / 2;
      setCrop(crop);
    });
    card.querySelector(".zoom-out").addEventListener("click", () => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const center = { x: crop.x + crop.side / 2, y: crop.y + crop.side / 2 };
      crop.side *= 1.1;
      crop.x = center.x - crop.side / 2;
      crop.y = center.y - crop.side / 2;
      setCrop(crop);
    });
    slider.addEventListener("input", () => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const center = { x: crop.x + crop.side / 2, y: crop.y + crop.side / 2 };
      const minimum = Math.max(48, choice.minimumCandidateCropSide, Math.min(choice.candidateWidth, choice.candidateHeight) * 0.1);
      const maximum = Math.min(choice.candidateWidth * 2, choice.candidateHeight * 2);
      crop.side = minimum * ((maximum / minimum) ** (Number(slider.value) / 1000));
      crop.x = center.x - crop.side / 2;
      crop.y = center.y - crop.side / 2;
      setCrop(crop);
    });
    confirmButton.addEventListener("click", () => {
      const state = states[item.reviewKey];
      if (!validState(item, state, false)) {
        setMessage("当前框选非法：请保留足够可见主体并使用像素正方形。", true);
        return;
      }
      state.confirmed = true;
      state.updatedAt = new Date().toISOString();
      persist();
      draw();
      updateProgress();
      setMessage(`${item.portraitRef} 的框选已确认；导出前仍可继续调整。`);
    });

    canvas.addEventListener("pointerdown", (event) => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const point = sourcePoint(event);
      const displayThreshold = 16 / view.scale;
      const corners = [
        { name: "nw", x: crop.x, y: crop.y, anchorX: crop.x + crop.side, anchorY: crop.y + crop.side },
        { name: "ne", x: crop.x + crop.side, y: crop.y, anchorX: crop.x, anchorY: crop.y + crop.side },
        { name: "sw", x: crop.x, y: crop.y + crop.side, anchorX: crop.x + crop.side, anchorY: crop.y },
        { name: "se", x: crop.x + crop.side, y: crop.y + crop.side, anchorX: crop.x, anchorY: crop.y },
      ];
      const corner = corners.find((entry) => Math.hypot(point.x - entry.x, point.y - entry.y) <= displayThreshold);
      if (corner) interaction = { type: "resize", corner: corner.name, anchorX: corner.anchorX, anchorY: corner.anchorY };
      else if (point.x >= crop.x && point.x <= crop.x + crop.side && point.y >= crop.y && point.y <= crop.y + crop.side) {
        interaction = { type: "move", offsetX: point.x - crop.x, offsetY: point.y - crop.y };
      } else {
        interaction = { type: "move", offsetX: crop.side / 2, offsetY: crop.side / 2 };
        setCrop({ x: point.x - crop.side / 2, y: point.y - crop.side / 2, side: crop.side });
      }
      canvas.setPointerCapture(event.pointerId);
      event.preventDefault();
    });
    canvas.addEventListener("pointermove", (event) => {
      if (!interaction) return;
      const { choice, state } = current();
      const point = sourcePoint(event);
      const crop = cropPixels(choice, state.cropBox);
      if (interaction.type === "move") {
        setCrop({ x: point.x - interaction.offsetX, y: point.y - interaction.offsetY, side: crop.side });
      } else {
        const side = Math.max(Math.abs(point.x - interaction.anchorX), Math.abs(point.y - interaction.anchorY));
        setCrop({
          x: interaction.corner.includes("w") ? interaction.anchorX - side : interaction.anchorX,
          y: interaction.corner.includes("n") ? interaction.anchorY - side : interaction.anchorY,
          side,
        });
      }
      event.preventDefault();
    });
    const endPointer = (event) => {
      interaction = null;
      if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    };
    canvas.addEventListener("pointerup", endPointer);
    canvas.addEventListener("pointercancel", endPointer);
    canvas.addEventListener("wheel", (event) => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const center = { x: crop.x + crop.side / 2, y: crop.y + crop.side / 2 };
      crop.side *= Math.exp(event.deltaY * 0.001);
      crop.x = center.x - crop.side / 2;
      crop.y = center.y - crop.side / 2;
      setCrop(crop);
      event.preventDefault();
    }, { passive: false });
    canvas.addEventListener("keydown", (event) => {
      const { choice, state } = current();
      const crop = cropPixels(choice, state.cropBox);
      const step = crop.side * (event.shiftKey ? 0.08 : 0.015);
      let handled = true;
      if (event.key === "ArrowLeft") crop.x -= step;
      else if (event.key === "ArrowRight") crop.x += step;
      else if (event.key === "ArrowUp") crop.y -= step;
      else if (event.key === "ArrowDown") crop.y += step;
      else if (event.key === "+" || event.key === "=") {
        crop.x += crop.side * 0.025;
        crop.y += crop.side * 0.025;
        crop.side *= 0.95;
      } else if (event.key === "-" || event.key === "_") {
        crop.x -= crop.side * 0.025;
        crop.y -= crop.side * 0.025;
        crop.side *= 1.05;
      } else handled = false;
      if (handled) {
        setCrop(crop);
        event.preventDefault();
      }
    });

    const loading = Promise.all(item.choices.map(async (choice) => {
      const [candidate, highResolution] = await Promise.all([
        loadImage(choice.sourceCandidate),
        loadImage(choice.sourceHighResolution),
      ]);
      images.set(choice.sourceRole, { candidate, highResolution });
    })).then(draw);
    return { draw, loading };
  }

  function renderCard(item) {
    const fragment = template.content.cloneNode(true);
    const card = fragment.querySelector(".guidance-card");
    card.dataset.reviewKey = item.reviewKey;
    fragment.querySelector(".review-code").textContent = item.reviewCode;
    fragment.querySelector(".review-title").textContent = `${item.portraitRef} · ${item.variantKey}`;
    fragment.querySelector(".review-meta").textContent = `${item.category} · ${item.reviewKey}`;
    fragment.querySelector(".human-feedback").textContent = `冻结的人类调整意见：${item.humanDecision.notes}`;
    const badges = fragment.querySelector(".badges");
    badges.append(badge("adjustment", "risk"), badge("直接人工几何", ""));
    if (item.preferredRoleHint) badges.append(badge(`备注指向 ${item.preferredRoleHint === "proposal" ? "Luna A" : "Luna B"}`, "risk"));

    const buttons = fragment.querySelector(".source-choice-buttons");
    const references = fragment.querySelector(".source-choice-reference");
    for (const choice of item.choices) {
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.role = choice.sourceRole;
      button.textContent = `${choice.label} · ${choice.candidateId} / f${choice.frame}`;
      buttons.append(button);
      const reference = document.createElement("div");
      reference.className = "source-reference";
      reference.dataset.role = choice.sourceRole;
      reference.append(
        imageElement(choice.currentMaster, `${choice.label} 当前 512 结果`),
        imageElement(choice.currentPreviews["80"], `${choice.label} 当前 80px 结果`, "preview-80-source"),
      );
      const facts = document.createElement("div");
      const title = document.createElement("strong");
      title.textContent = choice.label;
      const text = document.createElement("span");
      text.textContent = `${choice.candidateId} · frame ${choice.frame} · 当前框 ${Math.round((choice.initialCropBox[2] - choice.initialCropBox[0]) * choice.candidateWidth)}px`;
      facts.append(title, text);
      reference.append(facts);
      references.append(reference);
    }
    app.append(fragment);
    const mounted = app.lastElementChild;
    const controller = createController(mounted, item);
    controllers.set(item.reviewKey, controller);
    return controller.loading;
  }

  function updateProgress() {
    const confirmed = dataset.items.filter((item) => validState(item, states[item.reviewKey], true)).length;
    document.getElementById("progress-count").textContent = `${confirmed} / ${dataset.items.length}`;
    document.getElementById("progress-label").textContent = confirmed === dataset.items.length ? "可以导出完整框选指导" : "逐项确认后才能导出";
    document.getElementById("progress-bar").style.width = `${confirmed / dataset.items.length * 100}%`;
    exportButton.disabled = !completeStateMap();
  }

  async function exportGuidance() {
    if (exportInFlight) return;
    if (!completeStateMap()) {
      setMessage("框选尚未逐项确认，不能导出。", true);
      return;
    }
    exportInFlight = true;
    exportButton.disabled = true;
    exportButton.textContent = "正在保存…";
    setMessage("正在写入 canonical 框选指导与版本化归档…");
    const value = {
      schema: dataset.guidanceSchema,
      batchId: dataset.batchId,
      guidanceDigest: dataset.guidanceDigest,
      parentReceiptDigest: dataset.parent.receiptDigest,
      complete: true,
      exportedAt: new Date().toISOString(),
      guidance: Object.fromEntries(dataset.items.map((item) => [item.reviewKey, entryFromState(item, states[item.reviewKey])])),
    };
    try {
      validateImport(value);
      if (typeof window.savePortraitFramingGuidance === "function") {
        const saved = await window.savePortraitFramingGuidance(value);
        setMessage(`保存成功：${saved.path}；归档：${saved.archivePath}`);
        exportButton.textContent = "已保存 ✓（可再次导出）";
        return;
      }
      const blob = new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" });
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = "portrait-pilot-framing-guidance.json";
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 0);
      setMessage("浏览器下载已触发；请核对下载文件非空。");
      exportButton.textContent = "已触发下载 ✓（可再次导出）";
    } finally {
      exportInFlight = false;
      exportButton.disabled = !completeStateMap();
    }
  }

  async function importGuidance(file) {
    const value = JSON.parse(await file.text());
    const imported = validateImport(value);
    states = Object.fromEntries(dataset.items.map((item) => [item.reviewKey, {
      sourceRole: imported[item.reviewKey].sourceRole,
      cropBox: imported[item.reviewKey].cropBox,
      confirmed: true,
      updatedAt: imported[item.reviewKey].updatedAt,
    }]));
    persist();
    for (const controller of controllers.values()) controller.draw();
    updateProgress();
    setMessage("完整框选指导已导入，并与当前父回执及候选 hash 对齐。");
  }

  async function boot() {
    const dataPath = new URLSearchParams(location.search).get("data");
    if (!dataPath || !dataPath.startsWith("/tmp/portrait-pilot/") || dataPath.includes("..") || !dataPath.endsWith("/framing-guidance-data.json")) {
      throw new Error("缺少受约束的 framing-guidance-data 路径");
    }
    const response = await fetch(dataPath, { cache: "no-store" });
    if (!response.ok) throw new Error(`framing guidance data 加载失败：HTTP ${response.status}`);
    dataset = await response.json();
    if (dataset.schema !== DATA_SCHEMA || dataset.partial !== false || !Array.isArray(dataset.items) || dataset.items.length < 1) {
      throw new Error("framing guidance data schema、partial 或行数非法");
    }
    storageKey = `cf7-portrait-pilot-framing-guidance:${dataset.guidanceDigest}`;
    states = loadLocal();
    document.getElementById("parent-receipt").textContent = `parent receipt ${dataset.parent.receiptDigest}`;
    document.getElementById("guidance-digest").textContent = `guidance ${dataset.guidanceDigest}`;
    await Promise.all(dataset.items.map(renderCard));
    updateProgress();
    app.dataset.ready = "true";
    window.__portraitFramingGuidanceTest = {
      get dataset() { return dataset; },
      get states() { return states; },
      get storageKey() { return storageKey; },
      validateImport,
      completeStateMap,
      entryFromState,
    };
  }

  exportButton.addEventListener("click", () => exportGuidance().catch((error) => setMessage(`导出失败：${error.message}`, true)));
  importButton.addEventListener("click", () => importFile.click());
  importFile.addEventListener("change", async () => {
    try {
      if (importFile.files[0]) await importGuidance(importFile.files[0]);
    } catch (error) {
      setMessage(error.message, true);
    } finally {
      importFile.value = "";
    }
  });
  window.addEventListener("framing-guidance-export-saved", (event) => setMessage(`框选指导已保存：${event.detail}`));
  boot().catch((error) => {
    app.dataset.ready = "error";
    setMessage(error.message, true);
  });
})();
