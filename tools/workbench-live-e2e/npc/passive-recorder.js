"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const WebSocket = require("../../../launcher/perf/node_modules/playwright-core/lib/utilsBundle.js").ws;
const ProductionClosure = require("./production-closure");
const Protocol = require("./protocol");
const {
  atomicWriteJson,
  fail,
  isPlainObject,
  nextEvent,
  redactAuthorityTokens,
  sha256Bytes,
  sha256Text,
  canonicalJson,
  sleep,
} = require("./common");

const OVERLAY_URL = "https://overlay.local/overlay.html";
const OVERLAY_ORIGIN = "https://overlay.local";
const BINDING_NAME = "__cf7NpcPassiveObserverEmit";
const MARKER_NAME = "__cf7NpcPassiveObserverV1";
const TOOL_SOURCE_PREFIX = "https://cf7-agent.invalid/npc-passive-observer/";
const MAX_EVENT_BYTES = 8 * 1024 * 1024;

class TranscriptWriter {
  constructor(runDir) {
    this.runDir = path.resolve(runDir);
    this.jsonlPath = path.join(this.runDir, "passive-transcript.jsonl");
    this.summaryPath = path.join(this.runDir, "passive-transcript.json");
    this.observerId = "npc." + path.basename(this.runDir).replace(/[^A-Za-z0-9._~-]/g, ".");
    this.events = [];
    this.previousHash = "0".repeat(64);
    fs.mkdirSync(this.runDir, { recursive: true });
    fs.writeFileSync(this.jsonlPath, "", { encoding: "utf8", mode: 0o600, flag: "wx" });
  }

  append(rawEvent) {
    if (!isPlainObject(rawEvent)) fail("observer_event_invalid", "observer", "observer emitted a non-object event");
    const event = nextEvent(this.previousHash, this.events.length + 1, Object.assign({}, rawEvent, {
      observedAt: new Date().toISOString(),
    }));
    const line = JSON.stringify(event);
    if (Buffer.byteLength(line, "utf8") > MAX_EVENT_BYTES) {
      fail("observer_event_oversize", "observer", "observer event exceeds evidence limit");
    }
    fs.appendFileSync(this.jsonlPath, line + "\n", "utf8");
    this.events.push(event);
    this.previousHash = event.eventHash;
    return event;
  }

  prefix() {
    return { eventCount: this.events.length, chainHead: this.previousHash };
  }

  snapshot(extra) {
    return Object.assign({
      schema: "workbench-live-e2e.npc.transcript.v1",
      observerId: this.observerId,
      pageUrl: OVERLAY_URL,
      eventCount: this.events.length,
      chainHead: this.previousHash,
      events: this.events.slice(),
    }, extra || {});
  }

  flush(extra) {
    const snapshot = this.snapshot(extra);
    atomicWriteJson(this.summaryPath, snapshot);
    return snapshot;
  }
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

async function findExactEndpoint(binding, timeoutMs, pollMs) {
  if (!isPlainObject(binding) || !Number.isInteger(binding.port)
      || binding.port < 1024 || binding.port > 65535
      || binding.exclusiveBeforeLaunch !== true
      || binding.configurationSource !== "CF7_WEBVIEW2_ARGS"
      || !Number.isInteger(binding.runtimePid) || binding.runtimePid < 1) {
    fail("cdp_binding_invalid", "observer", "runner-owned CDP binding is incomplete or unbound");
  }
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    try {
      const targets = await getJson("http://127.0.0.1:" + binding.port + "/json", Math.min(2000, timeoutMs));
      last = targets;
      const exact = Array.isArray(targets) ? targets.filter((entry) => entry
        && entry.type === "page" && entry.url === OVERLAY_URL
        && /^ws:\/\/127\.0\.0\.1:\d+\//.test(String(entry.webSocketDebuggerUrl || ""))) : [];
      if (exact.length === 1) return exact[0];
      if (exact.length > 1) fail("production_page_not_exact", "observer",
        "bound endpoint exposed multiple production Overlay pages");
      if (Array.isArray(targets) && targets.some((entry) => entry
          && /(?:\/dev\/|harness\.html|localhost)/i.test(String(entry.url || "")))) {
        fail("dev_surface_observed", "observer", "bound endpoint exposed a dev/harness page");
      }
    } catch (error) { last = { error: error.message }; }
    await sleep(pollMs);
  }
  fail("cdp_attach_timeout", "observer", "runner-owned WebView2 CDP endpoint was unavailable", {
    port: binding.port,
    runtimePid: binding.runtimePid,
    last,
  });
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
        this.pending.forEach((entry) => entry.reject(new Error("CDP WebSocket closed")));
        this.pending.clear();
      });
    });
  }

  _message(bytes) {
    let message;
    try { message = JSON.parse(String(bytes)); } catch (_error) { return; }
    if (message.id && this.pending.has(message.id)) {
      const entry = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.error) entry.reject(new Error(message.error.message || "CDP command failed"));
      else entry.resolve(message.result || {});
      return;
    }
    if (message.method) this.listeners.forEach((listener) => listener(message));
  }

  send(method, params, timeoutMs) {
    return new Promise((resolve, reject) => {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
        return reject(new Error("CDP is closed"));
      }
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

function remoteValue(result, phase) {
  const response = result && result.result;
  if (!response || response.exceptionDetails) {
    fail("cdp_evaluate_failed", phase, "narrow CDP Runtime evaluation failed", {
      exceptionDetails: response && response.exceptionDetails,
    });
  }
  return response.result && response.result.value;
}

function injectionSource() {
  return function installNpcObserver(options) {
    "use strict";
    const bindingName = options.bindingName;
    const markerName = options.markerName;
    function emit(value) {
      try {
        const callback = window[bindingName];
        if (typeof callback === "function") void callback(JSON.stringify(value));
      } catch (_error) { /* evidence must not affect production UI */ }
    }
    function clone(value) {
      try { return JSON.parse(JSON.stringify(value)); }
      catch (_error) { return { observerCloneError: true, valueType: typeof value }; }
    }
    function text(value, maximum) {
      const output = String(value == null ? "" : value).replace(/\s+/g, " ").trim();
      return output.length <= maximum ? output : output.slice(0, maximum);
    }
    function panelState() {
      const container = document.getElementById("panel-container");
      const hidden = !container || container.hidden || container.style.display === "none";
      return {
        panel: container ? String(container.getAttribute("data-panel") || "") : "",
        hidden: !!hidden,
        npcshopVisible: !!(container && !hidden
          && String(container.getAttribute("data-panel") || "") === "npcshop"),
      };
    }
    function targetProjection(target, event) {
      if (!target || target.nodeType !== 1) return null;
      const element = target.closest ? target.closest([
        "button",
        "input",
        "[data-workbench-key]",
        "[data-trade-commit]",
        ".workbench-quantity-number",
        ".workbench-quantity-range",
        "[data-filter-path]",
      ].join(",")) || target : target;
      const attributes = {};
      ["id", "class", "aria-label", "aria-disabled", "disabled", "data-workbench-key",
        "data-trade-commit", "data-filter-path", "min", "max", "value", "type"]
        .forEach(function(name) {
          if (element.hasAttribute && element.hasAttribute(name)) {
            attributes[name] = text(element.getAttribute(name), 320);
          }
        });
      let selector = element.tagName ? element.tagName.toLowerCase() : "unknown";
      if (element.matches && element.matches("button[aria-label='关闭 NPC 商店']")) {
        selector = "button[aria-label=\"关闭 NPC 商店\"]";
      } else if (element.matches && element.matches("button.npcshop-checkout-btn")) {
        selector = "button.npcshop-checkout-btn";
      } else if (element.matches && element.matches("button[data-trade-commit]")) {
        selector = "button[data-trade-commit]";
      } else if (element.matches && element.matches("input.workbench-quantity-number")) {
        selector = "input.workbench-quantity-number";
      } else if (element.matches && element.matches("input.workbench-quantity-range")) {
        selector = "input.workbench-quantity-range";
      } else if (attributes.id) selector = "#" + attributes.id;
      else if (own(attributes, "data-workbench-key")) {
        selector += "[data-workbench-key=\"" + attributes["data-workbench-key"].replace(/\"/g, "\\\"") + "\"]";
      }
      const rect = element.getBoundingClientRect ? element.getBoundingClientRect() : null;
      const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
      const visible = !!(rect && Number.isFinite(rect.x) && Number.isFinite(rect.y)
        && rect.width > 0 && rect.height > 0 && style && style.display !== "none"
        && style.visibility !== "hidden" && Number(style.opacity) > 0
        && style.pointerEvents !== "none");
      const enabled = !!(visible && element.disabled !== true
        && !(element.hasAttribute && element.hasAttribute("disabled"))
        && String(element.getAttribute && element.getAttribute("aria-disabled") || "").toLowerCase() !== "true"
        && !(element.closest && element.closest("[inert]")));
      const isPointer = event && event.type === "click"
        && Number.isFinite(Number(event.clientX)) && Number.isFinite(Number(event.clientY));
      const clientPoint = isPointer
        ? { x: Number(event.clientX), y: Number(event.clientY) } : null;
      const hit = isPointer && document.elementFromPoint
        ? document.elementFromPoint(clientPoint.x, clientPoint.y) : null;
      const hitTest = isPointer ? {
        tagName: hit && hit.tagName || "",
        matchesTarget: !!(hit && (hit === element || element.contains(hit) || hit.contains(element))),
      } : null;
      return { selector, tagName: element.tagName || "", text: text(element.textContent, 300),
        attributes, visible, enabled, origin: String(location.origin),
        rect: rect ? { x: Number(rect.x), y: Number(rect.y), width: Number(rect.width),
          height: Number(rect.height) } : null,
        clientPoint, clientPointSource: isPointer ? "event" : "not_applicable", hitTest,
        viewport: { width: Number(window.innerWidth), height: Number(window.innerHeight) } };
    }
    function own(value, key) { return Object.prototype.hasOwnProperty.call(value || {}, key); }

    const old = window[markerName];
    if (old && typeof old.uninstall === "function") {
      try { old.uninstall(); } catch (_error) {}
    }
    const record = {
      bridge: window.Bridge || null,
      originalBridgeSend: window.Bridge && typeof window.Bridge.send === "function" ? window.Bridge.send : null,
      uiData: window.UiData || null,
      originalUiDispatch: window.UiData && typeof window.UiData.dispatch === "function" ? window.UiData.dispatch : null,
      listeners: [],
      uninstall: function() {
        try {
          if (record.bridge && record.originalBridgeSend && record.bridge.send === record.bridgeWrapper) {
            record.bridge.send = record.originalBridgeSend;
          }
        } catch (_error) {}
        try {
          if (record.uiData && record.originalUiDispatch && record.uiData.dispatch === record.uiWrapper) {
            record.uiData.dispatch = record.originalUiDispatch;
          }
        } catch (_error) {}
        record.listeners.forEach(function(binding) {
          try { binding.target.removeEventListener(binding.type, binding.handler, binding.capture); } catch (_error) {}
        });
        if (window[markerName] === record) delete window[markerName];
        emit({ kind: "observer_detached", pageTime: Date.now(), panelState: panelState() });
      },
    };
    if (record.originalBridgeSend) {
      record.bridgeWrapper = function(message) {
        emit({ kind: "bridge_send", direction: "outbound", pageTime: Date.now(),
          sendOrder: "after_panel_request_mux_onIssued",
          monotonicMs: performance.now(), panelState: panelState(), message: clone(message) });
        return record.originalBridgeSend.apply(this, arguments);
      };
      record.bridge.send = record.bridgeWrapper;
    }
    if (record.originalUiDispatch) {
      record.uiWrapper = function(payload) {
        emit({ kind: "uidata_dispatch", direction: "inbound", pageTime: Date.now(),
          monotonicMs: performance.now(), payload: clone(payload) });
        return record.originalUiDispatch.apply(this, arguments);
      };
      record.uiData.dispatch = record.uiWrapper;
    }
    function bind(target, type, handler, capture) {
      target.addEventListener(type, handler, capture);
      record.listeners.push({ target, type, handler, capture });
    }
    if (window.chrome && window.chrome.webview) {
      const handler = function(event) {
        emit({ kind: "webview_message", direction: "inbound", pageTime: Date.now(),
          monotonicMs: performance.now(), panelState: panelState(), message: clone(event.data) });
      };
      bind(window.chrome.webview, "message", handler, false);
    }
    ["click", "keydown", "input", "change"].forEach(function(type) {
      bind(document, type, function(event) {
        emit({
          kind: "dom_input",
          direction: "input",
          eventType: type,
          pageTime: Date.now(),
          monotonicMs: performance.now(),
          isTrusted: event.isTrusted === true,
          key: type === "keydown" ? text(event.key, 40) : undefined,
          repeat: type === "keydown" ? event.repeat === true : undefined,
          button: type === "click" ? Number(event.button) : undefined,
          clientX: type === "click" ? Number(event.clientX) : null,
          clientY: type === "click" ? Number(event.clientY) : null,
          target: targetProjection(event.target, event),
          panelState: panelState(),
        });
      }, true);
    });
    window[markerName] = record;
    emit({ kind: "observer_ready", pageTime: Date.now(), monotonicMs: performance.now(),
      url: String(location.href), bridgeWrapped: !!record.originalBridgeSend,
      uiDataWrapped: !!record.originalUiDispatch,
      webviewObserved: !!(window.chrome && window.chrome.webview), panelState: panelState() });
    return { ok: true, url: String(location.href), bridgeWrapped: !!record.originalBridgeSend,
      webviewObserved: !!(window.chrome && window.chrome.webview) };
  };
}

function immutableJsonClone(value) {
  function freezeTree(node) {
    if (!node || typeof node !== "object" || Object.isFrozen(node)) return node;
    Object.keys(node).forEach((key) => freezeTree(node[key]));
    return Object.freeze(node);
  }
  return freezeTree(JSON.parse(JSON.stringify(value)));
}

function createScriptContextLedger() {
  const parsedScripts = new Map();
  const parsedScriptOrder = [];
  const executionContexts = new Map();
  const executionContextOrder = [];
  function contextProjection(context) {
    const rawAuxData = context && context.auxData && typeof context.auxData === "object"
      ? immutableJsonClone(context.auxData) : Object.freeze({});
    return { origin: String(context && context.origin || ""),
      frameId: String(rawAuxData.frameId || ""), rawAuxData };
  }
  function bindContext(entry) {
    const context = executionContexts.get(entry.executionContextId);
    if (!context) return;
    entry.contextOrigin = String(context.origin || "");
  }
  function record(message) {
    if (message.method === "Runtime.executionContextCreated" && message.params
        && message.params.context && Number.isInteger(message.params.context.id)) {
      const context = immutableJsonClone(message.params.context);
      const projection = contextProjection(context);
      executionContextOrder.push({ occurrence: executionContextOrder.length + 1,
        id: context.id, origin: String(context.origin || ""), name: String(context.name || ""),
        uniqueId: String(context.uniqueId || ""), frameId: projection.frameId,
        rawAuxData: projection.rawAuxData });
      executionContexts.set(context.id, context);
      parsedScriptOrder.forEach(bindContext);
    }
    if (message.method === "Debugger.scriptParsed" && message.params) {
      const rawParams = immutableJsonClone(message.params);
      const url = typeof rawParams.url === "string" ? rawParams.url : "";
      if (!parsedScripts.has(url)) parsedScripts.set(url, []);
      parsedScripts.get(url).push(String(rawParams.scriptId || ""));
      let origin = "opaque";
      try { origin = new URL(url).origin; } catch (_error) {}
      const rawExecutionContextAuxData = rawParams.executionContextAuxData
          && typeof rawParams.executionContextAuxData === "object"
        ? immutableJsonClone(rawParams.executionContextAuxData) : null;
      const entry = { occurrence: parsedScriptOrder.length + 1, url, origin,
        scriptId: String(rawParams.scriptId || ""),
        executionContextId: Number(rawParams.executionContextId),
        contextOrigin: "",
        frameId: String(rawExecutionContextAuxData && rawExecutionContextAuxData.frameId || ""),
        rawExecutionContextAuxData, rawParams,
        sourceMethod: "Debugger.getScriptSource", sourceSha256: null, sourceBytes: null };
      bindContext(entry);
      parsedScriptOrder.push(entry);
    }
  }
  return { executionContextOrder, parsedScriptOrder, parsedScripts, record };
}

async function attachPassiveRecorder(options) {
  const root = path.resolve(options.root);
  const writer = options.writer || new TranscriptWriter(options.runDir);
  const binding = options.cdpBinding;
  const identity = options.runtimeIdentity;
  if (!isPlainObject(identity) || identity.pid !== binding.runtimePid) {
    fail("cdp_runtime_binding_mismatch", "observer", "CDP endpoint is not bound to authenticated candidate PID");
  }
  const timeoutMs = Number(options.timeoutMs || 30000);
  const pollMs = Number(options.pollMs || 250);
  const target = await findExactEndpoint(binding, timeoutMs, pollMs);
  const client = new NarrowCdp(target.webSocketDebuggerUrl);
  await client.connect(timeoutMs);
  const scriptContextLedger = createScriptContextLedger();
  const parsedScripts = scriptContextLedger.parsedScripts;
  const parsedScriptOrder = scriptContextLedger.parsedScriptOrder;
  const executionContextOrder = scriptContextLedger.executionContextOrder;
  const toolSources = new Map();
  const observerId = String(options.observerId || ("npc-" + identity.pid));
  let toolSequence = 0;
  const unsubscribeScripts = client.onEvent(scriptContextLedger.record);
  await client.send("Page.enable");
  await client.send("Debugger.enable");
  await client.send("Runtime.enable");
  await client.send("Runtime.addBinding", { name: BINDING_NAME });
  const unsubscribe = client.onEvent((message) => {
    if (message.method !== "Runtime.bindingCalled"
        || !message.params || message.params.name !== BINDING_NAME) return;
    try { writer.append(redactAuthorityTokens(JSON.parse(message.params.payload))); }
    catch (error) { fail("observer_event_invalid", "observer", "page observer emitted invalid JSON", {
      message: error.message,
    }); }
  });
  writer.append({ kind: "cdp_endpoint_bound", cdpPort: binding.port, runtimePid: binding.runtimePid,
    exclusiveBeforeLaunch: true, configurationSource: binding.configurationSource, pageUrl: OVERLAY_URL });
  function taggedExpression(label, expression) {
    const sequence = ++toolSequence;
    const url = TOOL_SOURCE_PREFIX + encodeURIComponent(observerId) + "/"
      + String(sequence).padStart(4, "0") + "-" + label + ".js";
    const source = expression + "\n//# sourceURL=" + url;
    const bytes = Buffer.from(source, "utf8");
    toolSources.set(url, { sequence, label, url, sha256: sha256Bytes(bytes), bytes: bytes.length });
    return source;
  }
  async function evaluateTool(label, expression, phase) {
    return remoteValue(await client.send("Runtime.evaluate", {
      expression: taggedExpression(label, expression), returnByValue: true,
    }), phase);
  }
  const installExpression = "(" + injectionSource().toString() + ")(" + JSON.stringify({
    bindingName: BINDING_NAME, markerName: MARKER_NAME,
  }) + ")";
  await client.send("Page.addScriptToEvaluateOnNewDocument", {
    source: taggedExpression("install_new_document", installExpression),
  });
  const installed = await evaluateTool("install_current_document", installExpression,
    "observer_install");
  if (!installed || installed.ok !== true || installed.url !== OVERLAY_URL
      || installed.bridgeWrapped !== true || installed.webviewObserved !== true) {
    fail("observer_install_failed", "observer", "passive recorder failed exact production binding", installed);
  }
  writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
    attachedAt: new Date().toISOString(), detachedAt: null });
  let detached = false;
  let pageHooksDetached = false;
  let finalCaptureCompleted = false;
  return {
    writer,
    binding,
    async health() {
      const state = await evaluateTool("health", "(()=>{const marker=window[" + JSON.stringify(MARKER_NAME)
          + "];return {installed:!!marker,bridgeCurrent:!!(marker&&marker.bridge&&marker.bridge.send===marker.bridgeWrapper),uiDataCurrent:!!(marker&&(!marker.uiData||marker.uiData.dispatch===marker.uiWrapper)),url:String(location.href)}})()",
        "observer_health");
      if (!state.installed || !state.bridgeCurrent || !state.uiDataCurrent || state.url !== OVERLAY_URL) {
        fail("observer_health_failed", "observer", "passive recorder lost exact production bindings", state);
      }
      return state;
    },
    async panelState() {
      return evaluateTool("panel_state",
        "(()=>{const c=document.getElementById('panel-container'),h=!c||c.hidden||c.style.display==='none';return {panel:c?String(c.getAttribute('data-panel')||''):'',hidden:!!h,npcshopVisible:!!(c&&!h&&String(c.getAttribute('data-panel')||'')==='npcshop')}})()",
        "observer_panel_state");
    },
    async sealPageHooksForFinalCapture() {
      if (detached || pageHooksDetached || finalCaptureCompleted) {
        fail("observer_final_capture_reused", "observer_detach_hooks",
          "page hooks may be sealed exactly once before the final production capture");
      }
      await evaluateTool("detach_hooks",
        "(()=>{const marker=window[" + JSON.stringify(MARKER_NAME)
          + "];if(marker&&typeof marker.uninstall==='function')marker.uninstall();return true})()",
        "observer_detach_hooks");
      pageHooksDetached = true;
      const plan = Array.from(toolSources.values());
      const detachPlan = plan.at(-1);
      const deadline = Date.now() + timeoutMs;
      while (Date.now() <= deadline) {
        const observed = detachPlan && parsedScripts.get(detachPlan.url);
        if (observed && observed.length === 1) return;
        await sleep(pollMs);
      }
      fail("loaded_production_tool_script_invalid", "observer_detach_hooks",
        "the final detach tool source was not observed exactly once before closure capture", {
          url: detachPlan && detachPlan.url,
        });
    },
    async captureProductionClosure(productionClosure, productionBinding, lifecycle, runId) {
      const expectedWeb = ProductionClosure.webFiles(productionClosure);
      const scripts = expectedWeb.filter((entry) => ["overlay_boot_web", "lazy_registry",
        "npc_lazy_web"].includes(entry.role));
      const stylesheets = expectedWeb.filter((entry) => entry.role.endsWith("stylesheet"));
      if (detached || !pageHooksDetached || finalCaptureCompleted) {
        fail("observer_final_capture_order_invalid", "production_closure",
          "production closure must be captured exactly once after page hooks are sealed and before transport detach");
      }
      const expectedScriptUrls = scripts.map((entry) => OVERLAY_ORIGIN + "/"
        + entry.locator.slice("root:launcher/web/".length));
      const expectedStyleUrls = stylesheets.map((entry) => OVERLAY_ORIGIN + "/"
        + entry.locator.slice("root:launcher/web/".length));
      const deadline = Date.now() + timeoutMs;
      while (Date.now() <= deadline) {
        const missing = scripts.filter((entry) => {
          const suffix = entry.locator.slice("root:launcher/web/".length);
          const matches = parsedScripts.get(OVERLAY_ORIGIN + "/" + suffix);
          return !matches || matches.length < 1;
        });
        if (!missing.length) break;
        await sleep(pollMs);
      }
      const tree = await client.send("Page.getResourceTree", {}, 15000);
      const frameId = tree && tree.frameTree && tree.frameTree.frame && tree.frameTree.frame.id;
      if (typeof frameId !== "string" || !frameId) {
        fail("loaded_production_page_invalid", "production_closure",
          "CDP resource tree lacks the exact Overlay main frame");
      }
      const resourceOccurrences = [];
      (function collect(frameTree) {
        const frame = frameTree && frameTree.frame || {};
        let frameOrigin = "opaque";
        try { frameOrigin = new URL(String(frame.url || "")).origin; } catch (_error) {}
        if (typeof frame.id === "string" && frame.id && typeof frame.url === "string") {
          resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
            frameId: String(frame.id), frameUrl: String(frame.url), frameOrigin,
            url: String(frame.url), origin: frameOrigin, resourceType: "Document",
            mimeType: String(frame.mimeType || "text/html"),
            sourceMethod: "Page.getResourceContent", sourceSha256: null, sourceBytes: null });
        }
        (frameTree && frameTree.resources || []).forEach((entry) => {
          const url = String(entry && entry.url || "");
          let origin = "opaque";
          try { origin = new URL(url).origin; } catch (_error) {}
          resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
            frameId: String(frame.id || ""), frameUrl: String(frame.url || ""), frameOrigin,
            url, origin, resourceType: String(entry && entry.type || ""),
            mimeType: String(entry && entry.mimeType || ""),
            sourceMethod: "Page.getResourceContent", sourceSha256: null, sourceBytes: null });
        });
        (frameTree && frameTree.childFrames || []).forEach(collect);
      }(tree.frameTree));
      for (const occurrence of resourceOccurrences) {
        let sourceResult;
        try {
          sourceResult = await client.send("Page.getResourceContent", {
            frameId: occurrence.frameId, url: occurrence.url,
          }, 15000);
        } catch (error) {
          fail("loaded_production_resource_source_invalid", "production_closure",
            "CDP could not read one registered production resource", {
              url: occurrence.url, message: error && error.message,
            });
        }
        if (!sourceResult || typeof sourceResult.content !== "string") {
          fail("loaded_production_resource_source_invalid", "production_closure",
            "registered production resource has no exact source bytes", { url: occurrence.url });
        }
        const sourceBytes = sourceResult.base64Encoded === true
          ? Buffer.from(sourceResult.content, "base64") : Buffer.from(sourceResult.content, "utf8");
        occurrence.sourceSha256 = sha256Bytes(sourceBytes);
        occurrence.sourceBytes = sourceBytes.length;
      }
      const resourceIconNames = ProductionClosure.authorityIconNames(
        Protocol.strictRequestPairsFromEvents(writer.events));
      ProductionClosure.validateLoadedResourceContract(root, productionClosure,
        resourceOccurrences, frameId, resourceIconNames);
      const styleOccurrences = resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet" || /\.css(?:$|[?#])/.test(entry.url));
      const relevantStyleUrls = styleOccurrences.map((entry) => entry.url);
      if (canonicalJson(relevantStyleUrls) !== canonicalJson(expectedStyleUrls)
          || styleOccurrences.some((entry) => entry.origin !== OVERLAY_ORIGIN
            || entry.frameId !== frameId || entry.frameOrigin !== OVERLAY_ORIGIN
            || entry.resourceType !== "Stylesheet")) {
        fail("loaded_production_style_set_invalid", "production_closure",
          "raw CDP stylesheet occurrence stream contains an extra, omission, foreign frame, or reorder", {
            actual: relevantStyleUrls, expected: expectedStyleUrls,
          });
      }
      const result = await client.send("Page.getResourceContent",
        { frameId, url: OVERLAY_URL }, 15000);
      if (!result || typeof result.content !== "string") {
        fail("loaded_production_page_invalid", "production_closure",
          "CDP could not read the actually loaded Overlay resource");
      }
      const pageBytes = result.base64Encoded === true
        ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
      const page = expectedWeb.find((entry) => entry.role === "page");
      const scriptSources = new Map();
      for (const occurrence of parsedScriptOrder) {
        if (!occurrence.scriptId || !Number.isInteger(occurrence.executionContextId)) {
          fail("loaded_production_script_invalid", "production_closure",
            "raw CDP script occurrence lacks script/context identity", {
              occurrence: occurrence.occurrence,
            });
        }
        const sourceResult = await client.send("Debugger.getScriptSource", {
          scriptId: occurrence.scriptId,
        }, 15000);
        if (!sourceResult || typeof sourceResult.scriptSource !== "string") {
          fail("loaded_production_script_invalid", "production_closure",
            "CDP script source is unavailable", { scriptId: occurrence.scriptId });
        }
        const sourceBytes = Buffer.from(sourceResult.scriptSource, "utf8");
        occurrence.sourceSha256 = sha256Bytes(sourceBytes);
        occurrence.sourceBytes = sourceBytes.length;
        scriptSources.set(occurrence.scriptId, sourceResult.scriptSource);
      }
      const toolScriptOccurrences = parsedScriptOrder.filter((entry) =>
        entry.url.startsWith(TOOL_SOURCE_PREFIX));
      const foreignScriptOccurrences = parsedScriptOrder.filter((entry) =>
        entry.url !== OVERLAY_URL && !expectedScriptUrls.includes(entry.url)
          && !entry.url.startsWith(TOOL_SOURCE_PREFIX));
      const anonymousScriptOccurrences = parsedScriptOrder.filter((entry) => !entry.url);
      const pageScriptOccurrences = parsedScriptOrder.filter((entry) => entry.url === OVERLAY_URL);
      const executableScriptOccurrences = parsedScriptOrder.filter((entry) =>
        expectedScriptUrls.includes(entry.url));
      const relevantScriptUrls = executableScriptOccurrences.map((entry) => entry.url);
      const contextIds = Array.from(new Set(parsedScriptOrder.map((entry) =>
        entry.executionContextId)));
      const contextAuxKeys = ["frameId", "isDefault", "type"];
      if (executionContextOrder.length !== contextIds.length
          || executionContextOrder.some((entry, index) => entry.occurrence !== index + 1
            || !contextIds.includes(entry.id) || entry.origin !== OVERLAY_ORIGIN
            || !entry.uniqueId || entry.frameId !== frameId || !isPlainObject(entry.rawAuxData)
            || canonicalJson(Object.keys(entry.rawAuxData).sort()) !== canonicalJson(contextAuxKeys)
            || String(entry.rawAuxData.frameId || "") !== frameId
            || entry.rawAuxData.isDefault !== true || entry.rawAuxData.type !== "default")
          || new Set(executionContextOrder.map((entry) => entry.id)).size
            !== executionContextOrder.length
          || new Set(executionContextOrder.map((entry) => entry.uniqueId)).size
            !== executionContextOrder.length) {
        fail("loaded_production_context_set_invalid", "production_closure",
          "raw CDP execution-context stream contains an extra, omission, duplicate, or foreign context");
      }
      const contextById = new Map(executionContextOrder.map((entry) => [entry.id, entry]));
      const observedToolUrls = new Set();
      toolScriptOccurrences.forEach((entry) => {
        const expected = toolSources.get(entry.url);
        if (!expected || observedToolUrls.has(entry.url)
            || entry.sourceSha256 !== expected.sha256 || entry.sourceBytes !== expected.bytes) {
          fail("loaded_production_tool_script_invalid", "production_closure",
            "tool-owned CDP script source is unknown, duplicated, or byte-detached", {
              url: entry.url,
            });
        }
        observedToolUrls.add(entry.url);
      });
      const toolPlan = Array.from(toolSources.values());
      const requiredToolPlans = toolPlan.filter((entry) => entry.label !== "install_new_document");
      const plannedLabels = toolPlan.map((entry) => entry.label);
      const observedToolSequence = toolScriptOccurrences.map((entry) => entry.url);
      if (plannedLabels.filter((label) => label === "install_new_document").length !== 1
          || plannedLabels.filter((label) => label === "install_current_document").length !== 1
          || plannedLabels.filter((label) => label === "detach_hooks").length !== 1
          || plannedLabels.at(-1) !== "detach_hooks"
          || canonicalJson(observedToolSequence)
            !== canonicalJson(requiredToolPlans.map((entry) => entry.url))
          || requiredToolPlans.some((entry) => !observedToolUrls.has(entry.url))
          || canonicalJson(relevantScriptUrls) !== canonicalJson(expectedScriptUrls)
          || foreignScriptOccurrences.length !== 0 || anonymousScriptOccurrences.length !== 0
          || pageScriptOccurrences.length !== 1
          || new Set(parsedScriptOrder.map((entry) => entry.scriptId)).size !== parsedScriptOrder.length
          || parsedScriptOrder.some((entry, index) => entry.occurrence !== index + 1
            || !entry.frameId || entry.frameId !== frameId
            || entry.contextOrigin !== OVERLAY_ORIGIN
            || !isPlainObject(entry.rawParams)
            || String(entry.rawParams.url || "") !== entry.url
            || String(entry.rawParams.scriptId || "") !== entry.scriptId
            || Number(entry.rawParams.executionContextId) !== entry.executionContextId
            || !isPlainObject(entry.rawExecutionContextAuxData)
            || canonicalJson(Object.keys(entry.rawExecutionContextAuxData).sort())
              !== canonicalJson(contextAuxKeys)
            || canonicalJson(entry.rawParams.executionContextAuxData)
              !== canonicalJson(entry.rawExecutionContextAuxData)
            || String(entry.rawExecutionContextAuxData.frameId || "") !== frameId
            || entry.rawExecutionContextAuxData.isDefault !== true
            || entry.rawExecutionContextAuxData.type !== "default"
            || !contextById.has(entry.executionContextId)
            || canonicalJson(entry.rawExecutionContextAuxData)
              !== canonicalJson(contextById.get(entry.executionContextId).rawAuxData)
            || !/^[a-f0-9]{64}$/.test(String(entry.sourceSha256 || ""))
            || !Number.isInteger(entry.sourceBytes) || entry.sourceBytes < 0)) {
        fail("loaded_production_script_set_invalid", "production_closure",
          "raw CDP script stream contains anonymous/foreign/extra/duplicate/context/source drift", {
            actual: relevantScriptUrls, expected: expectedScriptUrls,
            foreign: foreignScriptOccurrences.map((entry) => entry.url),
            anonymousCount: anonymousScriptOccurrences.length,
            pageOccurrenceCount: pageScriptOccurrences.length,
          });
      }
      const scriptByUrl = new Map(scripts.map((entry) => [OVERLAY_ORIGIN + "/"
        + entry.locator.slice("root:launcher/web/".length), entry]));
      const loadedScripts = executableScriptOccurrences.map((occurrence, index) => {
        const expected = scriptByUrl.get(occurrence.url);
        const ids = parsedScripts.get(occurrence.url);
        if (!expected || !ids || ids.length !== 1 || ids[0] !== occurrence.scriptId) {
          fail("loaded_production_script_missing", "production_closure",
            "CDP did not observe exactly one required NPC production script", {
              url: occurrence.url, count: ids ? ids.length : 0,
            });
        }
        return { occurrence: occurrence.occurrence, order: index + 1,
          scriptId: occurrence.scriptId, executionContextId: occurrence.executionContextId,
          frameId: occurrence.frameId, contextOrigin: occurrence.contextOrigin,
          url: occurrence.url, origin: occurrence.origin, declarationRole: expected.role,
          sourceMethod: "Debugger.getScriptSource",
          sha256: occurrence.sourceSha256, bytes: occurrence.sourceBytes };
      });
      const pageText = pageBytes.toString("utf8");
      const inlineScripts = pageScriptOccurrences.map((occurrence) => {
        const source = scriptSources.get(occurrence.scriptId);
        if (typeof source !== "string" || !pageText.includes(source)) {
          fail("loaded_production_inline_script_invalid", "production_closure",
            "inline script source is not contained in the exact loaded page bytes");
        }
        return { occurrence: occurrence.occurrence, scriptId: occurrence.scriptId,
          executionContextId: occurrence.executionContextId, frameId: occurrence.frameId,
          contextOrigin: occurrence.contextOrigin, sourceMethod: "Debugger.getScriptSource",
          sha256: occurrence.sourceSha256, bytes: occurrence.sourceBytes };
      });
      const loadedStylesheets = [];
      const styleByUrl = new Map(stylesheets.map((entry) => [OVERLAY_ORIGIN + "/"
        + entry.locator.slice("root:launcher/web/".length), entry]));
      for (let index = 0; index < styleOccurrences.length; index += 1) {
        const occurrence = styleOccurrences[index];
        const url = occurrence.url;
        const cssResult = await client.send("Page.getResourceContent", {
          frameId: occurrence.frameId, url,
        }, 15000);
        if (!cssResult || typeof cssResult.content !== "string") {
          fail("loaded_production_stylesheet_invalid", "production_closure",
            "CDP could not read one actually loaded stylesheet", { url });
        }
        const bytes = cssResult.base64Encoded === true
          ? Buffer.from(cssResult.content, "base64") : Buffer.from(cssResult.content, "utf8");
        const expected = styleByUrl.get(url);
        if (!expected) fail("loaded_production_stylesheet_invalid", "production_closure",
          "stylesheet occurrence is outside the exact production closure", { url });
        loadedStylesheets.push({ occurrence: occurrence.occurrence, order: index + 1, url,
          frameId: occurrence.frameId, origin: occurrence.origin, declarationRole: expected.role,
          sourceMethod: "Page.getResourceContent", sha256: sha256Bytes(bytes), bytes: bytes.length });
      }
      const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle,
        capturedAt: new Date().toISOString(), runtimePid: identity.pid, runId,
        productionClosureSha256: productionClosure.closureSha256,
        productionBindingSha256: productionBinding.bindingSha256,
        page: { role: page.role, locator: page.locator, url: OVERLAY_URL, origin: OVERLAY_ORIGIN,
          sourceMethod: "Page.getResourceContent", sha256: sha256Bytes(pageBytes),
          bytes: pageBytes.length },
        scriptOccurrences: JSON.parse(JSON.stringify(parsedScriptOrder)),
        executionContexts: JSON.parse(JSON.stringify(executionContextOrder)),
        toolScriptPlan: toolPlan.map((entry) => Object.assign({}, entry)),
        inlineScripts, resourceIconNames, resourceOccurrences, styleOccurrences,
        relevantScriptUrls, relevantStyleUrls,
        scripts: loadedScripts, stylesheets: loadedStylesheets };
      value.evidenceSha256 = sha256Text(canonicalJson(value));
      finalCaptureCompleted = true;
      return value;
    },
    async detach() {
      if (!detached) {
        detached = true;
        if (!pageHooksDetached || !finalCaptureCompleted) {
          writer.append({ kind: "observer_detach_transport_lost", pageTime: null });
        }
        unsubscribe();
        unsubscribeScripts();
        client.close();
      }
      return writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
        detachedAt: new Date().toISOString() });
    },
  };
}

module.exports = {
  BINDING_NAME,
  MARKER_NAME,
  OVERLAY_URL,
  TranscriptWriter,
  attachPassiveRecorder,
  createScriptContextLedger,
  injectionSource,
};
