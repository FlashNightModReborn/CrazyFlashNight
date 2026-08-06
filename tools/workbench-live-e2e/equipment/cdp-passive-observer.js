"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const WebSocket = require("../../../launcher/perf/node_modules/playwright-core/lib/utilsBundle.js").ws;
const RuntimeGuard = require("../lib/runtime-guard");
const Evidence = require("../lib/evidence-artifact");
const ProductionClosure = require("./production-closure");
const {
  TRANSCRIPT_SCHEMA,
  atomicWriteJson,
  deriveDiagnosticAuthorityBinding,
  deriveRequestAuthorityBinding,
  fail,
  nextRecord,
  redactAuthority,
} = require("./common");

const OVERLAY_URL = "https://overlay.local/overlay.html";
const BINDING = "__cf7EquipmentPassiveEmitV2";
const MARKER = "__cf7EquipmentPassiveObserverV2";
const MAX_EVENT_BYTES = 8 * 1024 * 1024;
const TOOL_SOURCE_PREFIX = "cf7-evidence://equipment/";

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function getJson(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, { timeout: timeoutMs }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        if (response.statusCode !== 200) return reject(new Error("HTTP " + response.statusCode));
        try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
        catch (error) { reject(error); }
      });
    });
    request.on("timeout", () => request.destroy(new Error("request timeout")));
    request.on("error", reject);
  });
}

async function findExactTarget(port, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    try {
      const targets = await getJson("http://127.0.0.1:" + port + "/json", Math.min(2000, timeoutMs));
      last = targets;
      const exact = Array.isArray(targets) ? targets.filter((entry) => entry
        && entry.type === "page" && entry.url === OVERLAY_URL
        && /^ws:\/\/127\.0\.0\.1:\d+\//.test(String(entry.webSocketDebuggerUrl || ""))) : [];
      if (exact.length === 1) return exact[0];
      if (exact.length > 1) fail("overlay_page_not_exact", "observer", "multiple exact Overlay targets exist");
    } catch (error) { last = { error: error.message }; }
    await delay(pollMs);
  }
  fail("overlay_page_not_exact", "observer", "one exact production Overlay target was not found", { last });
}

class NarrowCdp {
  constructor(url) {
    this.url = url;
    this.socket = null;
    this.nextId = 0;
    this.pending = new Map();
    this.listeners = new Set();
  }

  async connect(timeoutMs) {
    await new Promise((resolve, reject) => {
      const socket = new WebSocket(this.url);
      this.socket = socket;
      const timer = setTimeout(() => reject(new Error("CDP WebSocket timeout")), timeoutMs);
      socket.once("open", () => { clearTimeout(timer); resolve(); });
      socket.once("error", (error) => { clearTimeout(timer); reject(error); });
      socket.on("message", (bytes) => this._message(bytes));
      socket.on("close", () => {
        this.pending.forEach((record) => record.reject(new Error("CDP WebSocket closed")));
        this.pending.clear();
      });
    });
  }

  _message(bytes) {
    let message;
    try { message = JSON.parse(String(bytes)); } catch (_error) { return; }
    if (message.id && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message || "CDP command failed"));
      else pending.resolve(message.result || {});
      return;
    }
    if (message.method) this.listeners.forEach((listener) => listener(message));
  }

  send(method, params, timeoutMs) {
    return new Promise((resolve, reject) => {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return reject(new Error("CDP is closed"));
      const id = ++this.nextId;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("CDP command timeout: " + method));
      }, timeoutMs || 10000);
      this.pending.set(id, {
        resolve: (value) => { clearTimeout(timer); resolve(value); },
        reject: (error) => { clearTimeout(timer); reject(error); },
      });
      this.socket.send(JSON.stringify({ id, method, params: params || {} }));
    });
  }

  onEvent(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener); }
  close() { if (this.socket) this.socket.close(); }
}

class Writer {
  constructor(runDir, observerId) {
    this.runDir = runDir;
    this.observerId = observerId;
    this.summaryPath = path.join(runDir, observerId + "-passive-transcript.json");
    this.jsonlPath = path.join(runDir, observerId + "-passive-transcript.jsonl");
    this.events = [];
    this.previousHash = "0".repeat(64);
    fs.writeFileSync(this.jsonlPath, "", { encoding: "utf8", mode: 0o600, flag: "wx" });
  }

  append(raw) {
    const requestBinding = raw && deriveRequestAuthorityBinding(raw.message);
    const diagnosticBinding = raw && deriveDiagnosticAuthorityBinding(raw.message);
    const binding = requestBinding || diagnosticBinding;
    if (binding && Object.prototype.hasOwnProperty.call(raw, "authorityBinding")) {
      fail("authority_binding_collision", "observer",
        "page-controlled evidence attempted to supply an observer authority binding");
    }
    const enriched = binding ? Object.assign({}, raw, { authorityBinding: binding }) : raw;
    const clean = redactAuthority(enriched);
    const record = nextRecord(this.previousHash, this.events.length + 1,
      Object.assign({}, clean, { observedAt: new Date().toISOString() }));
    const line = JSON.stringify(record);
    if (Buffer.byteLength(line, "utf8") > MAX_EVENT_BYTES) {
      fail("observer_event_oversize", "observer", "observer event exceeded evidence bound");
    }
    fs.appendFileSync(this.jsonlPath, line + "\n", "utf8");
    this.events.push(record);
    this.previousHash = record.eventHash;
    return record;
  }

  value(extra) {
    return Object.assign({
      schema: TRANSCRIPT_SCHEMA,
      observerId: this.observerId,
      pageUrl: OVERLAY_URL,
      eventCount: this.events.length,
      chainHead: this.previousHash,
      events: this.events.slice(),
    }, extra || {});
  }

  flush(extra) {
    const value = this.value(extra);
    if (fs.existsSync(this.summaryPath)) fs.unlinkSync(this.summaryPath);
    atomicWriteJson(this.summaryPath, value);
    return value;
  }
}

function injectionSource() {
  return function install(options) {
    "use strict";
    function clone(value) {
      try { return JSON.parse(JSON.stringify(value)); }
      catch (_error) { return { observerCloneError: true }; }
    }
    function text(value, maximum) {
      var output = String(value == null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ").trim();
      return output.length <= maximum ? output : output.slice(0, maximum);
    }
    function state() {
      var container = document.getElementById("panel-container");
      var tuning = document.querySelector(".equipment-tuning-view");
      return {
        panel: container ? String(container.getAttribute("data-panel") || "") : "",
        hidden: !container || container.hidden || container.style.display === "none",
        tuningVisible: !!(tuning && container && !container.hidden && container.style.display !== "none"),
        operation: tuning ? String(tuning.getAttribute("data-operation") || "") : "",
        sourceKind: tuning ? String(tuning.getAttribute("data-source-kind") || "") : "",
        reconcile: tuning ? String(tuning.getAttribute("data-reconcile") || "") : "",
      };
    }
    function target(value, inputEvent) {
      if (!value || value.nodeType !== 1) return null;
      var node = value.closest ? value.closest("button,[data-candidate-key],[data-tuning-focus-key],[data-header-action],[data-slot],[data-physical-slot]") || value : value;
      var attributes = {};
      ["id", "class", "data-candidate-key", "data-tuning-focus-key", "data-header-action",
        "data-slot", "data-physical-slot", "data-operation", "data-source-kind", "aria-label",
        "aria-disabled"]
        .forEach(function(name) {
          if (node.hasAttribute && node.hasAttribute(name)) attributes[name] = text(node.getAttribute(name), 320);
        });
      function escaped(value) { return String(value).replace(/\\/g, "\\\\").replace(/\"/g, "\\\""); }
      var selector = node.tagName ? node.tagName.toLowerCase() : "unknown";
      if (attributes["data-tuning-focus-key"] === "commit"
          && node.matches && node.matches(".equipment-tuning-commit")) {
        selector = ".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]";
      } else if (attributes["data-candidate-key"]) {
        selector += "[data-candidate-key=\"" + escaped(attributes["data-candidate-key"]) + "\"]";
      } else if (attributes["data-physical-slot"]) {
        selector += "[data-physical-slot=\"" + escaped(attributes["data-physical-slot"]) + "\"]";
      } else if (attributes["data-header-action"]) {
        selector += "[data-header-action=\"" + escaped(attributes["data-header-action"]) + "\"]";
      } else if (attributes.id) selector = "#" + attributes.id;
      var rectValue = node.getBoundingClientRect ? node.getBoundingClientRect() : null;
      var rect = rectValue ? { left: Number(rectValue.left), top: Number(rectValue.top),
        right: Number(rectValue.right), bottom: Number(rectValue.bottom),
        width: Number(rectValue.width), height: Number(rectValue.height) } : null;
      var style = window.getComputedStyle ? window.getComputedStyle(node) : null;
      var visible = !!(node.isConnected && rect && rect.width > 0 && rect.height > 0
        && (!style || (style.display !== "none" && style.visibility !== "hidden"
          && style.visibility !== "collapse" && Number(style.opacity || 1) > 0)));
      var enabled = !(node.disabled === true || attributes["aria-disabled"] === "true"
        || style && style.pointerEvents === "none");
      var clientPoint = inputEvent ? { x: Number(inputEvent.clientX), y: Number(inputEvent.clientY) }
        : null;
      var hit = clientPoint && document.elementFromPoint
        ? document.elementFromPoint(clientPoint.x, clientPoint.y) : null;
      return { selector: selector, tagName: String(node.tagName || ""), text: text(node.textContent, 240),
        attributes: attributes, mutationCapable: !!(node.matches && node.matches(".equipment-tuning-commit,[data-candidate-key]")),
        visible: visible, enabled: enabled,
        viewport: { width: Number(window.innerWidth), height: Number(window.innerHeight) },
        rect: rect, clientPoint: clientPoint,
        hitTargetMatches: !!(hit && (hit === node || node.contains(hit))) };
    }
    function emit(value) {
      try { window[options.binding](clone(value)); } catch (_error) {}
    }
    var previous = window[options.marker];
    if (previous && typeof previous.detach === "function") previous.detach();
    var record = { bridge: window.Bridge, ui: window.UiData, oldSend: null, oldDispatch: null,
      webview: null, click: null, key: null, bridgeWrapper: null, uiWrapper: null };
    if (record.bridge && typeof record.bridge.send === "function") {
      record.oldSend = record.bridge.send;
      record.bridgeWrapper = function(message) {
        emit({ kind: "bridge_send", message: message, panelState: state(), pageTime: Date.now() });
        return record.oldSend.apply(this, arguments);
      };
      record.bridge.send = record.bridgeWrapper;
    }
    if (record.ui && typeof record.ui.dispatch === "function") {
      record.oldDispatch = record.ui.dispatch;
      record.uiWrapper = function(payload) {
        emit({ kind: "uidata_dispatch", payload: payload, panelState: state(), pageTime: Date.now() });
        return record.oldDispatch.apply(this, arguments);
      };
      record.ui.dispatch = record.uiWrapper;
    }
    record.webview = function(event) { emit({ kind: "webview_message", message: event.data,
      panelState: state(), pageTime: Date.now() }); };
    if (window.chrome && window.chrome.webview) window.chrome.webview.addEventListener("message", record.webview);
    record.click = function(event) { emit({ kind: "dom_input", eventType: "click",
      isTrusted: event.isTrusted === true, button: Number(event.button), target: target(event.target, event),
      panelState: state(), pageTime: Date.now() }); };
    record.key = function(event) { emit({ kind: "dom_input", eventType: "keydown",
      isTrusted: event.isTrusted === true, key: text(event.key, 40), repeat: event.repeat === true,
      target: target(event.target, event), panelState: state(), pageTime: Date.now() }); };
    document.addEventListener("click", record.click, true);
    document.addEventListener("keydown", record.key, true);
    record.detach = function() {
      try { if (record.bridge && record.bridge.send === record.bridgeWrapper) record.bridge.send = record.oldSend; } catch (_error) {}
      try { if (record.ui && record.ui.dispatch === record.uiWrapper) record.ui.dispatch = record.oldDispatch; } catch (_error) {}
      try { if (window.chrome && window.chrome.webview) window.chrome.webview.removeEventListener("message", record.webview); } catch (_error) {}
      document.removeEventListener("click", record.click, true);
      document.removeEventListener("keydown", record.key, true);
      if (window[options.marker] === record) delete window[options.marker];
      emit({ kind: "observer_detached", panelState: state(), pageTime: Date.now() });
    };
    window[options.marker] = record;
    emit({ kind: "observer_ready", url: String(location.href), bridgeWrapped: !!record.oldSend,
      uiDataWrapped: !!record.oldDispatch, webviewObserved: !!(window.chrome && window.chrome.webview),
      panelState: state(), pageTime: Date.now() });
    return { ok: true, url: String(location.href), bridgeWrapped: !!record.oldSend,
      uiDataWrapped: !!record.oldDispatch, webviewObserved: !!(window.chrome && window.chrome.webview) };
  };
}

function remoteValue(result, phase) {
  if (!result || !result.result || result.result.exceptionDetails) {
    fail("cdp_evaluation_failed", phase, "narrow CDP evaluation failed", { result });
  }
  return result.result.value;
}

async function attachPassiveObserver(options) {
  const timeoutMs = Number(options.timeoutMs || 30000);
  const pollMs = Number(options.pollMs || 250);
  const binding = options.cdpBinding;
  const identity = options.runtimeIdentity;
  if (!binding || !identity || binding.runtimePid !== identity.pid) {
    fail("cdp_runtime_binding_mismatch", "observer", "CDP endpoint is not bound to the candidate PID");
  }
  const target = await findExactTarget(binding.port, timeoutMs, pollMs);
  const client = new NarrowCdp(target.webSocketDebuggerUrl);
  await client.connect(timeoutMs);
  const parsedScripts = new Map();
  const parsedScriptOrder = [];
  const executionContextOccurrences = [];
  const toolSources = new Map();
  const observerId = String(options.observerId || "equipment-first");
  let toolSequence = 0;
  let loadedProductionEvidence = null;
  let terminalDetachEvaluated = false;
  const unsubscribeScripts = client.onEvent((event) => {
    if (event.method === "Runtime.executionContextCreated" && event.params
        && event.params.context && Number.isInteger(event.params.context.id)) {
      const context = event.params.context;
      const occurrence = { occurrence: executionContextOccurrences.length + 1,
        id: context.id, uniqueId: String(context.uniqueId || ""),
        name: String(context.name || ""), origin: String(context.origin || ""),
        auxData: context.auxData && typeof context.auxData === "object"
          ? JSON.parse(JSON.stringify(context.auxData)) : {} };
      executionContextOccurrences.push(occurrence);
    }
    if (event.method === "Debugger.scriptParsed" && event.params) {
      const url = typeof event.params.url === "string" ? event.params.url : "";
      if (!parsedScripts.has(url)) parsedScripts.set(url, []);
      parsedScripts.get(url).push(event.params.scriptId);
      let origin = "opaque";
      try { origin = new URL(url).origin; } catch (_error) {}
      const entry = { occurrence: parsedScriptOrder.length + 1, url, origin,
        scriptId: String(event.params.scriptId || ""),
        executionContextId: Number(event.params.executionContextId),
        rawParams: JSON.parse(JSON.stringify(event.params)),
        sourceMethod: "Debugger.getScriptSource", sourceBase64: null,
        sourceSha256: null, sourceBytes: null };
      parsedScriptOrder.push(entry);
    }
  });
  await client.send("Page.enable");
  await client.send("Debugger.enable");
  await client.send("Runtime.enable");
  await client.send("Runtime.addBinding", { name: BINDING });
  const writer = new Writer(options.runDir, observerId);
  const unsubscribe = client.onEvent((event) => {
    if (event.method !== "Runtime.bindingCalled" || !event.params || event.params.name !== BINDING) return;
    let value;
    try { value = JSON.parse(event.params.payload); }
    catch (_error) { return writer.append({ kind: "observer_payload_invalid" }); }
    writer.append(value);
  });
  function taggedExpression(label, expression, deliveryMethod) {
    const sequence = ++toolSequence;
    const url = TOOL_SOURCE_PREFIX + encodeURIComponent(observerId) + "/"
      + String(sequence).padStart(4, "0") + "-" + label + ".js";
    const source = expression + "\n//# sourceURL=" + url;
    const bytes = Buffer.from(source, "utf8");
    toolSources.set(url, { sequence, label, url,
      deliveryMethod: deliveryMethod || "Runtime.evaluate",
      sourceBase64: bytes.toString("base64"), sha256: Evidence.sha256Bytes(bytes),
      bytes: bytes.length });
    return source;
  }
  async function evaluateTool(label, expression, phase) {
    return remoteValue(await client.send("Runtime.evaluate", {
      expression: taggedExpression(label, expression, "Runtime.evaluate"), returnByValue: true,
    }), phase);
  }
  const observation = await evaluateTool("identity",
    "({identity:{url:String(location.href),origin:String(location.origin),timeOrigin:Number(performance.timeOrigin),readyState:String(document.readyState),userAgent:String(navigator.userAgent)},content:String(document.documentElement&&document.documentElement.outerHTML||'')})",
    "observer_identity");
  if (!observation || !observation.identity || observation.identity.url !== OVERLAY_URL
      || observation.identity.origin !== new URL(OVERLAY_URL).origin || !observation.content) {
    fail("overlay_page_identity_invalid", "observer", "Overlay page identity/content is invalid");
  }
  const endpointAttestation = RuntimeGuard.attestLoopbackCdpEndpoint({
    port: binding.port,
    runtimePid: binding.runtimePid,
    expectedUserDataRoot: path.join(options.root, "launcher", "webview2_overlay_userdata", "EBWebView"),
    expectedExecutableName: "msedgewebview2.exe",
  });
  Object.assign(binding, {
    expectedPageUrl: OVERLAY_URL,
    pageIdentity: observation.identity,
    pageIdentitySha256: Evidence.sha256Text(Evidence.canonicalJson(observation.identity)),
    pageContentSha256: Evidence.sha256Text(observation.content),
    pageContentBytes: Buffer.byteLength(observation.content, "utf8"),
    pageContentCapturedAt: new Date().toISOString(),
    attestation: endpointAttestation,
  });
  writer.append({ kind: "cdp_endpoint_bound", cdpPort: binding.port,
    runtimePid: binding.runtimePid, endpointAttestation, pageIdentity: observation.identity,
    pageIdentitySha256: binding.pageIdentitySha256, pageContentSha256: binding.pageContentSha256,
    pageContentBytes: binding.pageContentBytes, pageContentCapturedAt: binding.pageContentCapturedAt });
  const installExpression = "(" + injectionSource().toString() + ")(" + JSON.stringify({
    binding: BINDING, marker: MARKER,
  }) + ")";
  await client.send("Page.addScriptToEvaluateOnNewDocument", {
    source: taggedExpression("install_new_document", installExpression,
      "Page.addScriptToEvaluateOnNewDocument"),
  });
  const installed = await evaluateTool("install_current_document", installExpression,
    "observer_install");
  if (!installed || installed.ok !== true || installed.bridgeWrapped !== true
      || installed.webviewObserved !== true || installed.url !== OVERLAY_URL) {
    fail("observer_install_failed", "observer", "passive hooks did not bind exact production primitives", { installed });
  }
  let detached = false;
  writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
    attachedAt: new Date().toISOString(), detachedAt: null });
  async function evaluateFixed(label, expression, phase) {
    return evaluateTool(label, expression, phase);
  }
  return Object.freeze({
    async health() {
      const value = await evaluateFixed("health", "(()=>{const m=window[" + JSON.stringify(MARKER)
        + "];return {installed:!!m,bridgeCurrent:!!(m&&m.bridge&&m.bridge.send===m.bridgeWrapper),uiDataCurrent:!!(m&&(!m.ui||m.ui.dispatch===m.uiWrapper)),url:String(location.href)}})()", "observer_health");
      if (!value.installed || !value.bridgeCurrent || !value.uiDataCurrent || value.url !== OVERLAY_URL) {
        fail("observer_health_failed", "observer", "passive observer lost exact bindings", { value });
      }
      return value;
    },
    async panelState() {
      return evaluateFixed("panel_state", "(()=>{const c=document.getElementById('panel-container'),t=document.querySelector('.equipment-tuning-view');return {panel:c?String(c.getAttribute('data-panel')||''):'',hidden:!c||c.hidden||c.style.display==='none',tuningVisible:!!(t&&c&&!c.hidden&&c.style.display!=='none')}})()", "observer_panel_state");
    },
    async captureProductionClosure(productionClosure, productionBinding, lifecycle, runId) {
      if (!terminalDetachEvaluated || detached || loadedProductionEvidence) {
        fail("loaded_production_not_terminal", "production_closure",
          "loaded production may be captured exactly once after the terminal detach tool executes");
      }
      const scripts = ProductionClosure.scriptFiles(productionClosure);
      const deadline = Date.now() + timeoutMs;
      while (Date.now() <= deadline) {
        const missing = scripts.filter((entry) => {
          const suffix = entry.locator.slice("root:launcher/web/".length);
          const matches = parsedScripts.get("https://overlay.local/" + suffix);
          return !matches || matches.length < 1;
        });
        if (!missing.length) break;
        await delay(pollMs);
      }
      const tree = await client.send("Page.getResourceTree", {}, 15000);
      const frameId = tree && tree.frameTree && tree.frameTree.frame
        && tree.frameTree.frame.id;
      if (typeof frameId !== "string" || !frameId) {
        fail("loaded_production_page_invalid", "production_closure",
          "CDP resource tree lacks the exact Overlay main frame");
      }
      const resourceOccurrences = [];
      (function collect(frameTree) {
        const frame = frameTree && frameTree.frame || {};
        let frameOrigin = "opaque";
        try { frameOrigin = new URL(String(frame.url || "")).origin; } catch (_error) {}
        if (typeof frame.id === "string" && typeof frame.url === "string") {
          resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
            resourceKind: "frame_document", frameId: frame.id, frameUrl: frame.url,
            frameOrigin, url: frame.url, origin: frameOrigin, resourceType: "Document",
            mimeType: String(frame.mimeType || "text/html"),
            rawFrame: JSON.parse(JSON.stringify(frame)), rawResource: null,
            sourceMethod: "Page.getResourceContent", sourceBase64: null,
            sourceSha256: null, sourceBytes: null, sourceError: null });
        }
        (frameTree && frameTree.resources || []).forEach((entry) => {
          if (entry && typeof entry.url === "string") {
            let origin = "opaque";
            try { origin = new URL(entry.url).origin; } catch (_error) {}
            resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
              resourceKind: "frame_resource",
              frameId: String(frame.id || ""), frameUrl: String(frame.url || ""), frameOrigin,
              url: entry.url, origin, resourceType: String(entry.type || ""),
              mimeType: String(entry.mimeType || ""),
              rawFrame: JSON.parse(JSON.stringify(frame)),
              rawResource: JSON.parse(JSON.stringify(entry)),
              sourceMethod: "Page.getResourceContent", sourceBase64: null,
              sourceSha256: null, sourceBytes: null, sourceError: null });
          }
        });
        (frameTree && frameTree.childFrames || []).forEach(collect);
      }(tree.frameTree));
      for (const occurrence of resourceOccurrences) {
        let result;
        try {
          result = await client.send("Page.getResourceContent", {
            frameId: occurrence.frameId, url: occurrence.url,
          }, 15000);
        } catch (error) {
          occurrence.sourceError = String(error && error.message || "resource_content_unavailable")
            .slice(0, 500);
          continue;
        }
        if (!result || typeof result.content !== "string") {
          occurrence.sourceError = "resource_content_unavailable";
          continue;
        }
        const source = result.base64Encoded === true
          ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
        occurrence.sourceBase64 = source.toString("base64");
        occurrence.sourceSha256 = Evidence.sha256Bytes(source);
        occurrence.sourceBytes = source.length;
      }
      for (const occurrence of parsedScriptOrder) {
        if (!occurrence.scriptId || !Number.isInteger(occurrence.executionContextId)) {
          fail("loaded_production_script_invalid", "production_closure",
            "raw CDP script occurrence lacks script/context identity", {
              occurrence: occurrence.occurrence,
            });
        }
        const result = await client.send("Debugger.getScriptSource",
          { scriptId: occurrence.scriptId }, 15000);
        if (!result || typeof result.scriptSource !== "string") {
          fail("loaded_production_script_invalid", "production_closure",
            "CDP script source is unavailable", { scriptId: occurrence.scriptId });
        }
        const sourceBytes = Buffer.from(result.scriptSource, "utf8");
        occurrence.sourceBase64 = sourceBytes.toString("base64");
        occurrence.sourceSha256 = Evidence.sha256Bytes(sourceBytes);
        occurrence.sourceBytes = sourceBytes.length;
      }
      const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle,
        capturedAt: new Date().toISOString(),
        runtimePid: identity.pid, runId,
        productionClosureSha256: productionClosure.closureSha256,
        productionBindingSha256: productionBinding.bindingSha256,
        contextOccurrences: JSON.parse(JSON.stringify(executionContextOccurrences)),
        scriptOccurrences: JSON.parse(JSON.stringify(parsedScriptOrder)),
        resourceOccurrences: JSON.parse(JSON.stringify(resourceOccurrences)),
        toolSourcePlan: Array.from(toolSources.values()).map((entry) => Object.assign({}, entry)) };
      value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
      loadedProductionEvidence = value;
      return value;
    },
    async terminalCapture(productionClosure, productionBinding, lifecycle, runId) {
      if (detached || terminalDetachEvaluated || loadedProductionEvidence) {
        fail("observer_terminal_capture_reused", "observer",
          "terminal observer capture is one-shot");
      }
      let loaded;
      try {
        await evaluateTool("detach",
          "(()=>{const m=window[" + JSON.stringify(MARKER)
            + "];if(m&&typeof m.detach==='function')m.detach();return true})()",
          "observer_detach");
        terminalDetachEvaluated = true;
        const terminalPlan = Array.from(toolSources.values())[toolSources.size - 1];
        const deadline = Date.now() + timeoutMs;
        while (terminalPlan && Date.now() <= deadline) {
          const occurrences = parsedScripts.get(terminalPlan.url);
          if (occurrences && occurrences.length === 1) break;
          await delay(pollMs);
        }
        if (!terminalPlan || terminalPlan.label !== "detach"
            || !parsedScripts.has(terminalPlan.url)
            || parsedScripts.get(terminalPlan.url).length !== 1) {
          fail("observer_terminal_script_missing", "observer",
            "terminal detach tool did not enter the raw Debugger script stream exactly once");
        }
        loaded = await this.captureProductionClosure(
          productionClosure, productionBinding, lifecycle, runId);
      } finally {
        detached = true;
        unsubscribe();
        unsubscribeScripts();
        client.close();
      }
      const transcript = writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
        attachedAt: binding.pageContentCapturedAt, detachedAt: new Date().toISOString() });
      return { loadedProduction: loaded, transcript };
    },
    snapshot() { return writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
      attachedAt: binding.pageContentCapturedAt, detachedAt: null }); },
    async detach() {
      if (!detached) {
        detached = true;
        try {
          if (!terminalDetachEvaluated) await evaluateTool("detach",
          "(()=>{const m=window[" + JSON.stringify(MARKER)
            + "];if(m&&typeof m.detach==='function')m.detach();return true})()",
          "observer_detach");
        } catch (_error) {
          writer.append({ kind: "observer_detach_transport_lost" });
        }
        unsubscribe();
        unsubscribeScripts();
        client.close();
      }
      return writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
        attachedAt: binding.pageContentCapturedAt, detachedAt: new Date().toISOString() });
    },
  });
}

module.exports = { attachPassiveObserver };
