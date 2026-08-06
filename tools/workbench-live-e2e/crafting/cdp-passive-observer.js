"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const WebSocket = require("../../../launcher/perf/node_modules/playwright-core/lib/utilsBundle.js").ws;
const RuntimeGuard = require("../lib/runtime-guard");
const Evidence = require("../lib/evidence-artifact");
const SourceContract = require("./source-contract");
const {
  TRANSCRIPT_SCHEMA,
  atomicWriteJson,
  deriveRequestAuthorityBinding,
  fail,
  nextRecord,
  redactAuthority,
} = require("./common");

const OVERLAY_URL = "https://overlay.local/overlay.html";
const TOOL_SOURCE_PREFIX = "cf7-evidence://crafting/";
const BINDING = "__cf7CraftingPassiveEmitV3";
const MARKER = "__cf7CraftingPassiveObserverV3";
const MAX_EVENT_BYTES = 8 * 1024 * 1024;

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
    const binding = requestBinding;
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
      var crafting = document.querySelector(".crafting-panel");
      return {
        panel: container ? String(container.getAttribute("data-panel") || "") : "",
        hidden: !container || container.hidden || container.style.display === "none",
        craftingVisible: !!(crafting && container && !container.hidden
          && container.style.display !== "none"),
        view: crafting ? String(crafting.getAttribute("data-crafting-view") || "") : "",
      };
    }
    function target(value, inputEvent) {
      if (!value || value.nodeType !== 1) return null;
      var node = value.closest
        ? value.closest("button,[data-workbench-key],[data-commit-primary],[data-header-action]") || value
        : value;
      var attributes = {};
      ["id", "class", "data-workbench-key", "data-commit-primary", "data-header-action",
        "data-crafting-view", "aria-label", "aria-disabled"]
        .forEach(function(name) {
          if (node.hasAttribute && node.hasAttribute(name)) attributes[name] = text(node.getAttribute(name), 320);
        });
      var selector = node.tagName ? node.tagName.toLowerCase() : "unknown";
      if (attributes.id) selector = "#" + attributes.id;
      else if (attributes["data-workbench-key"]) selector += "[data-workbench-key=\""
        + attributes["data-workbench-key"].replace(/\"/g, "\\\"") + "\"]";
      else if (node.hasAttribute && node.hasAttribute("data-commit-primary")) {
        selector += "[data-commit-primary]";
      }
      else if (node.matches && node.matches(".crafting-organizer-btn")) {
        selector += ".crafting-organizer-btn";
      } else if (node.matches && node.matches(".inventory-return-crafting-btn")) {
        selector += ".inventory-return-crafting-btn";
      } else if (attributes["data-header-action"]) {
        selector += "[data-header-action=\"" + attributes["data-header-action"]
          .replace(/\"/g, "\\\"") + "\"]";
      }
      var rect = node.getBoundingClientRect ? node.getBoundingClientRect() : null;
      var style = window.getComputedStyle ? window.getComputedStyle(node) : null;
      var visible = !!(node.isConnected && rect && rect.width > 0 && rect.height > 0
        && (!style || (style.display !== "none" && style.visibility !== "hidden"
          && style.visibility !== "collapse"
          && Number(style.opacity || 1) > 0)));
      var enabled = !(node.disabled === true
        || String(node.getAttribute && node.getAttribute("aria-disabled") || "") === "true"
        || style && style.pointerEvents === "none");
      var point = inputEvent && Number.isFinite(Number(inputEvent.clientX))
        && Number.isFinite(Number(inputEvent.clientY))
        ? { x: Number(inputEvent.clientX), y: Number(inputEvent.clientY) } : null;
      var hit = point && document.elementFromPoint
        ? document.elementFromPoint(point.x, point.y) : null;
      return { selector: selector, tagName: String(node.tagName || ""),
        text: text(node.textContent, 240), attributes: attributes,
        mutationCapable: !!(node.matches
          && node.matches(".crafting-commit-btn,[data-commit-primary],[data-workbench-key]")),
        visible: visible, enabled: enabled,
        viewport: { width: Number(window.innerWidth), height: Number(window.innerHeight),
          scrollX: Number(window.scrollX), scrollY: Number(window.scrollY) },
        clientPoint: point,
        hitTargetMatches: !!(point && hit && (hit === node || node.contains(hit))),
        rect: rect ? { left: Number(rect.left), top: Number(rect.top),
          right: Number(rect.right), bottom: Number(rect.bottom),
          width: Number(rect.width), height: Number(rect.height) } : null };
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
        // This is only the real Bridge.send boundary. The observer attaches after the
        // production message listener, so it deliberately makes no claim about an
        // internal mux-issued event or response-to-downstream callback order.
        emit({ kind: "bridge_send", message: message,
          panelState: state(), pageTime: Date.now() });
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
      coordinates: { x: Number(event.clientX), y: Number(event.clientY) },
      panelState: state(), pageTime: Date.now() }); };
    record.key = function(event) { emit({ kind: "dom_input", eventType: "keydown",
      isTrusted: event.isTrusted === true, key: text(event.key, 40), repeat: event.repeat === true,
      target: target(event.target, null), coordinates: null,
      panelState: state(), pageTime: Date.now() }); };
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

function authoritativeIconNamesForLifecycle(events, lifecycle) {
  const opens = (events || []).filter((event) => event && event.kind === "webview_message"
    && event.message && event.message.type === "panel_cmd" && event.message.panel === "crafting"
    && event.message.cmd === "open" && typeof event.message.panelInstanceId === "string"
    && event.message.panelInstanceId);
  if (opens.length !== 1) {
    fail("dynamic_icon_lifecycle_open_invalid", "source_identity",
      "one lifecycle must expose one exact Crafting owner", { lifecycle, count: opens.length });
  }
  const owner = opens[0].message.panelInstanceId;
  const names = [];
  function add(value) {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  }
  function addItem(item) {
    if (!item || typeof item !== "object") return;
    add(item.icon);
    (Array.isArray(item.modSlots) ? item.modSlots : []).forEach((mod) => add(mod && mod.icon));
  }
  (events || []).filter((event) => event && event.kind === "webview_message"
    && event.message && event.message.type === "panel_resp"
    && event.message.panel === "crafting" && event.message.panelInstanceId === owner
    && event.message.success === true).forEach((event) => {
    const message = event.message;
    (Array.isArray(message.recipes) ? message.recipes : []).forEach((recipe) =>
      addItem(recipe && recipe.output));
    addItem(message.output);
    addItem(message.crafted);
    (Array.isArray(message.materials) ? message.materials : []).forEach(addItem);
    (Array.isArray(message.snapshots) ? message.snapshots : []).forEach((snapshot) => {
      (snapshot && Array.isArray(snapshot.slots) ? snapshot.slots : []).forEach((slot) => {
        if (slot && slot.occupied === true) addItem(slot.item);
      });
    });
  });
  if (!names.length) {
    fail("dynamic_icon_authority_empty", "source_identity",
      "Crafting recipe/material/Inventory authority exposed no icon names", { lifecycle });
  }
  return names;
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
  function contextProjection(context) {
    const rawContext = context && typeof context === "object"
      ? immutableJsonClone(context) : Object.freeze({});
    const rawAuxData = rawContext.auxData && typeof rawContext.auxData === "object"
      ? immutableJsonClone(rawContext.auxData) : Object.freeze({});
    return { origin: String(context && context.origin || ""),
      frameId: String(rawAuxData.frameId || ""), rawAuxData, rawContext };
  }
  function bindContext(entry) {
    const context = executionContexts.get(entry.executionContextId);
    if (context) entry.contextOrigin = String(context.origin || "");
  }
  function record(event) {
    if (event.method === "Runtime.executionContextCreated" && event.params
        && event.params.context && Number.isInteger(event.params.context.id)) {
      const context = immutableJsonClone(event.params.context);
      executionContexts.set(context.id, context);
      parsedScriptOrder.forEach(bindContext);
    }
    if (event.method === "Debugger.scriptParsed" && event.params) {
      const rawParams = immutableJsonClone(event.params);
      const url = typeof rawParams.url === "string" ? rawParams.url : "";
      if (!parsedScripts.has(url)) parsedScripts.set(url, []);
      parsedScripts.get(url).push(rawParams.scriptId);
      let origin = "opaque";
      try { origin = new URL(url).origin; } catch (_error) {}
      const rawExecutionContextAuxData = rawParams.executionContextAuxData
          && typeof rawParams.executionContextAuxData === "object"
        ? immutableJsonClone(rawParams.executionContextAuxData) : null;
      const entry = { occurrence: parsedScriptOrder.length + 1, url, origin,
        scriptId: String(rawParams.scriptId || ""),
        executionContextId: Number(rawParams.executionContextId),
        startLine: Number(rawParams.startLine), startColumn: Number(rawParams.startColumn),
        endLine: Number(rawParams.endLine), endColumn: Number(rawParams.endColumn),
        sourceMapUrl: String(rawParams.sourceMapURL || ""),
        contextOrigin: "",
        frameId: String(rawExecutionContextAuxData && rawExecutionContextAuxData.frameId || ""),
        rawExecutionContextAuxData, rawParams,
        sourceMethod: "Debugger.getScriptSource", sourceSha256: null, sourceBytes: null };
      bindContext(entry);
      parsedScriptOrder.push(entry);
    }
  }
  return { contextProjection, executionContexts, parsedScriptOrder, parsedScripts, record };
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
  const ledger = createScriptContextLedger();
  const { contextProjection, executionContexts, parsedScriptOrder, parsedScripts } = ledger;
  const toolSources = new Map();
  const observerId = String(options.observerId || "crafting-first");
  let toolSequence = 0;
  const unsubscribeScripts = client.onEvent((event) => {
    ledger.record(event);
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
  function taggedExpression(label, expression) {
    const sequence = ++toolSequence;
    const url = TOOL_SOURCE_PREFIX + encodeURIComponent(observerId) + "/"
      + String(sequence).padStart(4, "0") + "-" + label + ".js";
    const source = expression + "\n//# sourceURL=" + url;
    const bytes = Buffer.from(source, "utf8");
    toolSources.set(url, { sequence, label, url, sha256: Evidence.sha256Bytes(bytes),
      bytes: bytes.length });
    return source;
  }
  async function evaluateTool(label, expression, phase) {
    return remoteValue(await client.send("Runtime.evaluate", {
      expression: taggedExpression(label, expression), returnByValue: true,
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
    source: taggedExpression("install_new_document", installExpression),
  });
  const installed = await evaluateTool("install_current_document", installExpression,
    "observer_install");
  if (!installed || installed.ok !== true || installed.bridgeWrapped !== true
      || installed.webviewObserved !== true || installed.url !== OVERLAY_URL) {
    fail("observer_install_failed", "observer", "passive hooks did not bind exact production primitives", { installed });
  }
  let detached = false;
  let detachResult = null;
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
      return evaluateFixed("panel_state", "(()=>{const c=document.getElementById('panel-container'),t=document.querySelector('.crafting-panel');return {panel:c?String(c.getAttribute('data-panel')||''):'',hidden:!c||c.hidden||c.style.display==='none',craftingVisible:!!(t&&c&&!c.hidden&&c.style.display!=='none'),view:t?String(t.getAttribute('data-crafting-view')||''):''}})()", "observer_panel_state");
    },
    async recordPanelState(label) {
      if (label !== "after_close") {
        fail("observer_panel_state_label_invalid", "observer",
          "only the fixed post-close panel state may be sampled");
      }
      const value = await evaluateFixed("record_panel_state", "(()=>{const c=document.getElementById('panel-container'),t=document.querySelector('.crafting-panel');return {panel:c?String(c.getAttribute('data-panel')||''):'',hidden:!c||c.hidden||c.style.display==='none',craftingVisible:!!(t&&c&&!c.hidden&&c.style.display!=='none'),view:t?String(t.getAttribute('data-crafting-view')||''):''}})()", "observer_panel_state");
      writer.append({ kind: "panel_state_sample", label, panelState: value });
      return value;
    },
    async captureProductionClosure(sourceFingerprint, sourceBinding, lifecycle, runId) {
      if (!detached) {
        fail("loaded_production_not_terminal", "source_identity",
          "loadedProduction may be captured only after observer.detach evaluation");
      }
      const expectedWeb = SourceContract.webFiles(sourceFingerprint);
      const scripts = SourceContract.scriptFiles(sourceFingerprint);
      const styles = SourceContract.styleFiles(sourceFingerprint);
      const expectedStaticResources = SourceContract.expectedStaticResourceSet(sourceFingerprint);
      const cssConditionalResources = SourceContract.cssConditionalResourceSet(sourceFingerprint);
      const iconNames = authoritativeIconNamesForLifecycle(writer.events, lifecycle);
      const iconProjection = SourceContract.iconResourceSetForNames(
        root, sourceFingerprint, iconNames);
      const fontEnvironment = SourceContract.captureFontEnvironment(
        root, sourceFingerprint, process.env);
      const expectedScriptUrls = scripts.map((entry) => "https://overlay.local/"
        + entry.locator.slice("root:launcher/web/".length));
      const expectedStyleUrls = styles.map((entry) => "https://overlay.local/"
        + entry.locator.slice("root:launcher/web/".length));
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
      let tree = null;
      let resourceOccurrences = [];
      let missingMandatory = expectedStaticResources.concat(iconProjection.resources);
      while (Date.now() <= deadline) {
        tree = await client.send("Page.getResourceTree", {}, 15000);
        resourceOccurrences = [];
        let currentFrameOccurrence = 0;
        (function collect(frameTree) {
          const frame = frameTree && frameTree.frame || {};
          currentFrameOccurrence += 1;
          let frameOrigin = "opaque";
          try { frameOrigin = new URL(String(frame.url || "")).origin; } catch (_error) {}
          (frameTree && frameTree.resources || []).forEach((entry, resourceIndex) => {
            if (!entry || typeof entry.url !== "string") return;
            let origin = "opaque";
            try { origin = new URL(entry.url).origin; } catch (_error) {}
            resourceOccurrences.push({ occurrence: resourceOccurrences.length + 1,
              frameOccurrence: currentFrameOccurrence, resourceOccurrence: resourceIndex + 1,
              frameId: String(frame.id || ""), frameUrl: String(frame.url || ""), frameOrigin,
              url: entry.url, origin, resourceType: String(entry.type || ""),
              mimeType: String(entry.mimeType || ""), resource: JSON.parse(JSON.stringify(entry)),
              sourceMethod: null, sourceSha256: null, sourceBytes: null, sourceError: null });
          });
          (frameTree && frameTree.childFrames || []).forEach(collect);
        }(tree && tree.frameTree));
        const counts = new Map();
        resourceOccurrences.forEach((entry) => {
          const key = entry.url + "\u0000" + entry.resourceType;
          counts.set(key, Number(counts.get(key) || 0) + 1);
        });
        missingMandatory = expectedStaticResources.concat(iconProjection.resources)
          .filter((entry) => Number(counts.get(entry.url + "\u0000" + entry.resourceType) || 0) !== 1);
        if (!missingMandatory.length) break;
        await delay(pollMs);
      }
      const frameId = tree && tree.frameTree && tree.frameTree.frame
        && tree.frameTree.frame.id;
      if (typeof frameId !== "string" || !frameId) {
        fail("loaded_production_page_invalid", "source_identity",
          "CDP resource tree lacks the exact Overlay main frame");
      }
      if (missingMandatory.length) {
        fail("loaded_production_resource_incomplete", "source_identity",
          "terminal Page tree lacks a mandatory fixed or authoritative icon resource", {
            missing: missingMandatory.map((entry) => ({
              url: entry.url, resourceType: entry.resourceType,
            })),
          });
      }
      const styleOccurrences = resourceOccurrences.filter((entry) =>
        entry.resourceType === "Stylesheet" || /\.css(?:$|[?#])/.test(entry.url));
      const relevantStyleUrls = styleOccurrences.map((entry) => entry.url);
      if (Evidence.canonicalJson(relevantStyleUrls)
          !== Evidence.canonicalJson(expectedStyleUrls)
          || styleOccurrences.some((entry) => entry.origin !== "https://overlay.local"
            || entry.frameId !== frameId || entry.frameOrigin !== "https://overlay.local"
            || entry.resourceType !== "Stylesheet")) {
        fail("loaded_production_style_set_invalid", "source_identity",
          "CDP raw stylesheet occurrence stream has extras, duplicates, foreign origins, or wrong order", {
            actual: relevantStyleUrls, expected: expectedStyleUrls,
          });
      }
      const pageResult = await client.send("Page.getResourceContent",
        { frameId, url: OVERLAY_URL }, 15000);
      if (!pageResult || typeof pageResult.content !== "string") {
        fail("loaded_production_page_invalid", "source_identity",
          "CDP could not read the actually loaded Overlay resource");
      }
      const pageBytes = pageResult.base64Encoded === true
        ? Buffer.from(pageResult.content, "base64")
        : Buffer.from(pageResult.content, "utf8");
      const pageExpected = expectedWeb.find((entry) => entry.role === "page");
      const scriptSources = new Map();
      for (const occurrence of parsedScriptOrder) {
        if (!occurrence.scriptId || !Number.isInteger(occurrence.executionContextId)) {
          fail("loaded_production_script_invalid", "source_identity",
            "raw CDP script occurrence lacks script/context identity", {
              occurrence: occurrence.occurrence,
            });
        }
        const result = await client.send("Debugger.getScriptSource",
          { scriptId: occurrence.scriptId }, 15000);
        if (!result || typeof result.scriptSource !== "string") {
          fail("loaded_production_script_invalid", "source_identity",
            "CDP script source is unavailable", { scriptId: occurrence.scriptId });
        }
        const sourceBytes = Buffer.from(result.scriptSource, "utf8");
        occurrence.sourceSha256 = Evidence.sha256Bytes(sourceBytes);
        occurrence.sourceBytes = sourceBytes.length;
        scriptSources.set(occurrence.scriptId, result.scriptSource);
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
      const observedToolUrls = new Set();
      toolScriptOccurrences.forEach((entry) => {
        const expected = toolSources.get(entry.url);
        if (!expected || observedToolUrls.has(entry.url)
            || entry.sourceSha256 !== expected.sha256 || entry.sourceBytes !== expected.bytes) {
          fail("loaded_production_tool_script_invalid", "source_identity",
            "tool-owned CDP script source is unknown, duplicated, or byte-detached", {
              url: entry.url,
            });
        }
        observedToolUrls.add(entry.url);
      });
      const nonDeferredToolPlans = Array.from(toolSources.values())
        .filter((entry) => entry.label !== "install_new_document");
      const contextAuxKeys = ["frameId", "isDefault", "type"];
      function validScriptContext(entry) {
        const context = executionContexts.get(entry.executionContextId);
        if (!context || !entry.rawExecutionContextAuxData
            || Evidence.canonicalJson(Object.keys(entry.rawExecutionContextAuxData).sort())
              !== Evidence.canonicalJson(contextAuxKeys)
            || !entry.rawParams || !entry.rawParams.executionContextAuxData) return false;
        const projection = contextProjection(context);
        return Evidence.canonicalJson(entry.rawParams.executionContextAuxData)
            === Evidence.canonicalJson(entry.rawExecutionContextAuxData)
          && Evidence.canonicalJson(entry.rawExecutionContextAuxData)
            === Evidence.canonicalJson(projection.rawAuxData)
          && entry.rawExecutionContextAuxData.frameId === frameId
          && entry.rawExecutionContextAuxData.isDefault === true
          && entry.rawExecutionContextAuxData.type === "default";
      }
      if (nonDeferredToolPlans.some((entry) => !observedToolUrls.has(entry.url))
          || Evidence.canonicalJson(relevantScriptUrls)
            !== Evidence.canonicalJson(expectedScriptUrls)
          || foreignScriptOccurrences.length !== 0 || anonymousScriptOccurrences.length !== 0
          || pageScriptOccurrences.length !== 1
          || parsedScriptOrder.some((entry, index) => entry.occurrence !== index + 1
            || !entry.scriptId || !entry.frameId || entry.frameId !== frameId
            || entry.contextOrigin !== "https://overlay.local"
            || !validScriptContext(entry)
            || !/^[a-f0-9]{64}$/.test(String(entry.sourceSha256 || ""))
            || !Number.isInteger(entry.sourceBytes) || entry.sourceBytes < 0)) {
        fail("loaded_production_script_set_invalid", "source_identity",
          "CDP raw script stream has anonymous/foreign/extra/duplicate/context/source drift", {
            actual: relevantScriptUrls, expected: expectedScriptUrls,
            foreign: foreignScriptOccurrences.map((entry) => entry.url),
            anonymousCount: anonymousScriptOccurrences.length,
            pageOccurrenceCount: pageScriptOccurrences.length,
          });
      }
      const scriptByUrl = new Map(scripts.map((entry) => ["https://overlay.local/"
        + entry.locator.slice("root:launcher/web/".length), entry]));
      const loadedScripts = executableScriptOccurrences.map((occurrence) => {
        const expected = scriptByUrl.get(occurrence.url);
        const scriptIds = parsedScripts.get(occurrence.url);
        if (!expected || !scriptIds || scriptIds.length !== 1
            || scriptIds[0] !== occurrence.scriptId) {
          fail("loaded_production_script_missing", "source_identity",
            "CDP did not observe exactly one required Crafting production script", {
              url: occurrence.url, count: scriptIds ? scriptIds.length : 0,
            });
        }
        return { role: expected.role, locator: expected.locator, url: occurrence.url,
          occurrence: occurrence.occurrence, scriptId: occurrence.scriptId,
          executionContextId: occurrence.executionContextId, frameId: occurrence.frameId,
          contextOrigin: occurrence.contextOrigin, sourceMethod: "Debugger.getScriptSource",
          sha256: occurrence.sourceSha256, bytes: occurrence.sourceBytes };
      });
      const pageText = pageBytes.toString("utf8");
      const inlineScripts = pageScriptOccurrences.map((occurrence) => {
        const source = scriptSources.get(occurrence.scriptId);
        if (typeof source !== "string" || !pageText.includes(source)) {
          fail("loaded_production_inline_script_invalid", "source_identity",
            "inline script source is not contained in the exact loaded page bytes");
        }
        return { occurrence: occurrence.occurrence, scriptId: occurrence.scriptId,
          executionContextId: occurrence.executionContextId, frameId: occurrence.frameId,
          contextOrigin: occurrence.contextOrigin, sourceMethod: "Debugger.getScriptSource",
          sha256: occurrence.sourceSha256, bytes: occurrence.sourceBytes };
      });
      const boundConditionalResources = new Map();
      cssConditionalResources.concat(iconProjection.resources)
        .concat(fontEnvironment.installed.map((entry) => ({
          url: entry.url, resourceType: "Font", origin: "https://cfn-fonts.local",
          sha256: entry.sha256, bytes: entry.bytes,
        }))).forEach((entry) => {
          if (boundConditionalResources.has(entry.url)) {
            fail("loaded_conditional_resource_collision", "source_identity",
              "conditional CSS/font/icon layers share one URL", { url: entry.url });
          }
          boundConditionalResources.set(entry.url, entry);
        });
      for (const occurrence of resourceOccurrences) {
        const expected = boundConditionalResources.get(occurrence.url);
        if (!expected || occurrence.resourceType !== expected.resourceType) continue;
        occurrence.sourceMethod = "Page.getResourceContent";
        try {
          const result = await client.send("Page.getResourceContent",
            { frameId: occurrence.frameId, url: occurrence.url }, 15000);
          if (!result || typeof result.content !== "string") throw new Error("resource content unavailable");
          const bytes = result.base64Encoded === true
            ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
          occurrence.sourceSha256 = Evidence.sha256Bytes(bytes);
          occurrence.sourceBytes = bytes.length;
        } catch (error) {
          occurrence.sourceError = String(error && error.message || error || "resource read failed");
        }
      }
      const loadedStyles = [];
      const styleByUrl = new Map(styles.map((entry) => ["https://overlay.local/"
        + entry.locator.slice("root:launcher/web/".length), entry]));
      for (const occurrence of styleOccurrences) {
        const url = occurrence.url;
        const expected = styleByUrl.get(url);
        if (!expected) {
          fail("loaded_production_style_invalid", "source_identity",
            "CDP stylesheet occurrence is outside the production closure", { url });
        }
        const result = await client.send("Page.getResourceContent",
          { frameId: occurrence.frameId, url }, 15000);
        if (!result || typeof result.content !== "string") {
          fail("loaded_production_resource_invalid", "source_identity",
            "CDP could not read one actually loaded Overlay resource", {
              locator: expected.locator,
            });
        }
        const bytes = result.base64Encoded === true
          ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
        loadedStyles.push({ role: expected.role, locator: expected.locator, url,
          resourceOccurrence: occurrence.occurrence, frameId: occurrence.frameId,
          sourceMethod: "Page.getResourceContent", sha256: Evidence.sha256Bytes(bytes),
          bytes: bytes.length });
      }
      const referencedContexts = [];
      const referencedContextIds = new Set();
      parsedScriptOrder.forEach((occurrence) => {
        if (referencedContextIds.has(occurrence.executionContextId)) return;
        const context = executionContexts.get(occurrence.executionContextId);
        if (!context) {
          fail("loaded_production_context_missing", "source_identity",
            "raw script references an unavailable execution context", {
              executionContextId: occurrence.executionContextId,
            });
        }
        referencedContextIds.add(occurrence.executionContextId);
        const projection = contextProjection(context);
        referencedContexts.push({ occurrence: referencedContexts.length + 1,
          executionContextId: context.id, origin: projection.origin,
          name: String(context.name || ""), uniqueId: String(context.uniqueId || ""),
          frameId: projection.frameId, rawAuxData: projection.rawAuxData,
          rawContext: projection.rawContext });
      });
      const value = { schema: SourceContract.LOADED_SCHEMA, lifecycle,
        capturePhase: "post_observer_detach",
        capturedAt: new Date().toISOString(), runtimePid: identity.pid, runId,
        mainFrameId: frameId,
        sourceFingerprintSha256: sourceFingerprint.fingerprintSha256,
        sourceBindingSha256: sourceBinding.bindingSha256,
        page: { role: "page", locator: pageExpected.locator, url: OVERLAY_URL,
          sourceMethod: "Page.getResourceContent", sha256: Evidence.sha256Bytes(pageBytes),
          bytes: pageBytes.length }, scripts: loadedScripts, styles: loadedStyles,
        scriptOccurrences: JSON.parse(JSON.stringify(parsedScriptOrder)),
        executionContextOccurrences: JSON.parse(JSON.stringify(referencedContexts)),
        toolScriptPlan: Array.from(toolSources.values()).map((entry) => Object.assign({}, entry)),
        inlineScripts, resourceOccurrences, styleOccurrences, fontEnvironment, iconProjection,
        relevantScriptUrls, relevantStyleUrls };
      value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
      return value;
    },
    snapshot() { return writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
      attachedAt: binding.pageContentCapturedAt, detachedAt: null }); },
    async detach(sourceFingerprint, sourceBinding, lifecycle, runId) {
      if (detached) return detachResult;
      detached = true;
      let detachError = null;
      try { await evaluateTool("detach",
        "(()=>{const m=window[" + JSON.stringify(MARKER)
          + "];if(m&&typeof m.detach==='function')m.detach();return true})()",
        "observer_detach"); } catch (error) {
        detachError = error;
        writer.append({ kind: "observer_detach_transport_lost" });
      }
      let loadedProduction = null;
      try {
        const supplied = [sourceFingerprint, sourceBinding, lifecycle, runId]
          .filter((value) => value != null).length;
        if (supplied !== 0 && supplied !== 4) {
          fail("terminal_capture_arguments_invalid", "source_identity",
            "terminal detach capture requires source, binding, lifecycle, and runId together");
        }
        if (supplied === 4) {
          if (detachError) {
            fail("observer_detach_evaluation_failed", "source_identity",
              "terminal capture cannot close a lost detach evaluation", {
                error: String(detachError && detachError.message || detachError),
              });
          }
          loadedProduction = await this.captureProductionClosure(
            sourceFingerprint, sourceBinding, lifecycle, runId);
        }
      } finally {
        unsubscribe();
        unsubscribeScripts();
        client.close();
      }
      const transcript = writer.flush({ cdpPort: binding.port, runtimePid: binding.runtimePid,
        attachedAt: binding.pageContentCapturedAt, detachedAt: new Date().toISOString() });
      detachResult = { transcript, loadedProduction };
      return detachResult;
    },
  });
}

module.exports = { attachPassiveObserver, authoritativeIconNamesForLifecycle,
  createScriptContextLedger, immutableJsonClone };
