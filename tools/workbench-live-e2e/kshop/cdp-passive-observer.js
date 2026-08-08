"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  EVENT_SCHEMA,
  atomicWriteJson,
  canonicalJson,
  fail,
  isPlainObject,
  nextEvent,
  redactOpaqueTokens,
  sha256Bytes,
  sha256Text,
  sleep,
} = require("./common");
const { connectExactTarget, evaluateByValue, snapshotOwnedEvaluations } = require("./cdp-client");
const { attestLoopbackCdpEndpoint } = require("../lib/runtime-guard");
const ProductionClosure = require("./production-closure");

const OVERLAY_URL = "https://overlay.local/overlay.html";
const MAX_EVENT_BYTES = 8 * 1024 * 1024;
const BINDING_NAME = "__cf7KShopPassiveObserverEmit";
const MARKER_NAME = "__cf7KShopPassiveObserverV1";

class TranscriptWriter {
  constructor(runDir, observerId) {
    this.path = path.join(runDir, "passive-transcript.jsonl");
    this.summaryPath = path.join(runDir, "passive-transcript.json");
    this.observerId = String(observerId || ("kshop-" + crypto.randomBytes(12).toString("hex")));
    this.events = [];
    this.previousHash = "0".repeat(64);
    fs.mkdirSync(runDir, { recursive: true });
    fs.writeFileSync(this.path, "", { encoding: "utf8", mode: 0o600, flag: "wx" });
  }

  append(rawEvent) {
    if (!isPlainObject(rawEvent)) {
      fail("observer_event_invalid", "observer", "observer emitted a non-object event");
    }
    if (Object.prototype.hasOwnProperty.call(rawEvent, "observerId")) {
      fail("observer_identity_collision", "observer",
        "page-controlled evidence attempted to supply the observer identity");
    }
    const event = nextEvent(this.previousHash, this.events.length + 1, Object.assign({}, rawEvent, {
      observerId: this.observerId,
      observedAt: new Date().toISOString(),
    }));
    const line = JSON.stringify(event);
    if (Buffer.byteLength(line, "utf8") > MAX_EVENT_BYTES) {
      fail("observer_event_oversize", "observer", "observer event exceeded the evidence limit");
    }
    fs.appendFileSync(this.path, line + "\n", { encoding: "utf8" });
    this.events.push(event);
    this.previousHash = event.eventHash;
    return event;
  }

  snapshot(extra) {
    return Object.assign({
      schema: "workbench-live-e2e.kshop.transcript.v2",
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

function browserInjectionSource() {
  return function installPassiveObserver(options) {
    "use strict";
    const bindingName = options.bindingName;
    const markerName = options.markerName;
    function emit(raw) {
      try {
        const callback = window[bindingName];
        if (typeof callback === "function") void callback(JSON.stringify(raw));
      } catch (_error) { /* evidence transport must never affect the application */ }
    }
    function safeClone(value) {
      try { return JSON.parse(JSON.stringify(value)); }
      catch (_error) { return { observerCloneError: true, valueType: typeof value }; }
    }
    const authorityKeys = new Set([
      "expectedTuningToken", "tuningToken", "checkoutToken", "expectedCheckoutToken",
      "expectedPurchasedToken", "purchasedToken", "expectedCraftToken", "craftToken",
      "expectedBatchToken", "batchToken", "expectedTradeToken", "tradeToken",
      "expectedLearnToken", "learnToken", "expectedLease", "slotLease", "closeLease",
      "transactionId"
    ]);
    function wireFacts(value) {
      let serialized;
      try { serialized = JSON.stringify(value); }
      catch (_error) { return { wirePayloadLength:-1, authorityValueLengths:{} }; }
      const authorityValueLengths = {};
      function visit(entry) {
        if (Array.isArray(entry)) return entry.forEach(visit);
        if (!entry || typeof entry !== "object") return;
        Object.keys(entry).forEach(function(key) {
          if (authorityKeys.has(key) && typeof entry[key] === "string") {
            const publicKey = "field:" + key;
            if (!authorityValueLengths[publicKey]) authorityValueLengths[publicKey] = [];
            authorityValueLengths[publicKey].push(entry[key].length);
          } else visit(entry[key]);
        });
      }
      visit(value);
      return { wirePayloadLength:serialized.length, authorityValueLengths:authorityValueLengths };
    }
    function boundedText(value, maximum) {
      const text = String(value == null ? "" : value).replace(/\s+/g, " ").trim();
      return text.length <= maximum ? text : text.slice(0, maximum);
    }
    function stableTarget(target, inputEvent) {
      if (!target || target.nodeType !== 1) return null;
      const element = target.closest
        ? target.closest("button,[data-filter-path],[data-idx],[data-header-action],#kshop-checkout") || target
        : target;
      const attributes = {};
      ["id", "class", "data-filter-path", "data-idx", "data-header-action",
        "data-kshop-settlement-commit", "data-kshop-settlement-back",
        "data-kshop-settlement-close", "aria-label", "data-mode"].forEach(function(name) {
        if (element.hasAttribute && element.hasAttribute(name)) {
          attributes[name] = boundedText(element.getAttribute(name), 320);
        }
      });
      let selector = element.tagName ? element.tagName.toLowerCase() : "unknown";
      if (attributes.id) selector = "#" + attributes.id;
      else if (attributes["data-kshop-settlement-commit"] !== undefined) selector = "[data-kshop-settlement-commit]";
      else if (attributes["data-kshop-settlement-back"] !== undefined) selector = "[data-kshop-settlement-back]";
      else if (attributes["data-kshop-settlement-close"] !== undefined) selector = "[data-kshop-settlement-close]";
      else if (attributes["data-filter-path"] !== undefined) selector = "[data-filter-path=\""
          + attributes["data-filter-path"].replace(/\"/g, "\\\"") + "\"]";
      else if (attributes["data-header-action"] !== undefined) selector = "[data-header-action=\""
          + attributes["data-header-action"] + "\"]";
      else if (attributes["data-idx"] !== undefined) selector += "[data-idx=\""
          + attributes["data-idx"] + "\"]";
      const rawRect = element.getBoundingClientRect ? element.getBoundingClientRect() : null;
      const rect = rawRect ? { left:Number(rawRect.left), top:Number(rawRect.top),
        right:Number(rawRect.right), bottom:Number(rawRect.bottom),
        width:Number(rawRect.width), height:Number(rawRect.height) } : null;
      let style = null;
      try { style = window.getComputedStyle ? window.getComputedStyle(element) : null; }
      catch (_error) { style = null; }
      const visible = !!(element.isConnected && rect && rect.width > 0 && rect.height > 0
        && style && style.display !== "none" && style.visibility !== "hidden"
        && Number(style.opacity || 1) > 0);
      const enabled = !(element.disabled === true
        || String(element.getAttribute && element.getAttribute("aria-disabled") || "") === "true");
      const clientPoint = inputEvent && inputEvent.type === "click"
        ? { x:Number(inputEvent.clientX), y:Number(inputEvent.clientY) }
        : rect ? { x:Number(rect.left + rect.width / 2), y:Number(rect.top + rect.height / 2) }
          : null;
      let hit = null;
      try {
        hit = clientPoint && document.elementFromPoint
          ? document.elementFromPoint(clientPoint.x, clientPoint.y) : null;
      } catch (_error) { hit = null; }
      return {
        selector: selector,
        tagName: element.tagName || "",
        text: boundedText(element.textContent, 240),
        attributes: attributes,
        visible: visible,
        enabled: enabled,
        viewport: { width:Number(window.innerWidth), height:Number(window.innerHeight),
          devicePixelRatio:Number(window.devicePixelRatio || 1),
          scrollX:Number(window.scrollX || 0), scrollY:Number(window.scrollY || 0) },
        rect: rect,
        clientPoint: clientPoint,
        hitTargetMatches:!!(hit && (hit === element || element.contains(hit))),
      };
    }
    function panelState() {
      const container = document.getElementById("panel-container");
      return {
        panel: container ? String(container.getAttribute("data-panel") || "") : "",
        hidden: container ? !!container.hidden || container.style.display === "none" : true,
      };
    }

    const priorObserver = window[markerName];
    if (priorObserver && typeof priorObserver.uninstall === "function") {
      try { priorObserver.uninstall(); } catch (_error) { /* replace stale observer */ }
    }

    const bridgeObject = window.Bridge && typeof window.Bridge.send === "function"
      ? window.Bridge : null;
    const bridgeSendDelegate = bridgeObject ? bridgeObject.send : null;
    const uiDataObject = window.UiData && typeof window.UiData.dispatch === "function"
      ? window.UiData : null;
    const uiDispatchDelegate = uiDataObject ? uiDataObject.dispatch : null;
    const panelMuxPrototype = window.PanelRuntime && window.PanelRuntime.PanelRequestMux
      ? window.PanelRuntime.PanelRequestMux.prototype : null;
    const panelRequestDelegate = panelMuxPrototype
      && typeof panelMuxPrototype.request === "function" ? panelMuxPrototype.request : null;
    let webviewHandler = null;
    let clickHandler = null;
    let keyHandler = null;
    let bridgeWrapper = null;
    let uiWrapper = null;
    let panelRequestWrapper = null;
    const marker = {
      uninstall: function() {
        try {
          if (bridgeObject && bridgeSendDelegate && bridgeObject.send === bridgeWrapper) {
            bridgeObject.send = bridgeSendDelegate;
          }
        } catch (_error) {}
        try {
          if (uiDataObject && uiDispatchDelegate && uiDataObject.dispatch === uiWrapper) {
            uiDataObject.dispatch = uiDispatchDelegate;
          }
        } catch (_error) {}
        try {
          if (panelMuxPrototype && panelRequestDelegate
              && panelMuxPrototype.request === panelRequestWrapper) {
            panelMuxPrototype.request = panelRequestDelegate;
          }
        } catch (_error) {}
        try {
          if (window.chrome && window.chrome.webview && webviewHandler) {
            window.chrome.webview.removeEventListener("message", webviewHandler);
          }
        } catch (_error) {}
        try { document.removeEventListener("click", clickHandler, true); } catch (_error) {}
        try { document.removeEventListener("keydown", keyHandler, true); } catch (_error) {}
        if (window[markerName] === marker) delete window[markerName];
        emit({ kind:"observer_detached", pageTime:Date.now(), panelState:panelState() });
      },
      health: function() {
        return { installed:window[markerName] === marker,
          bridgeCurrent:!bridgeObject || bridgeObject.send === bridgeWrapper,
          uiDataCurrent:!uiDataObject || uiDataObject.dispatch === uiWrapper,
          panelRequestMuxCurrent:!!panelMuxPrototype
            && panelMuxPrototype.request === panelRequestWrapper,
          url:String(location.href) };
      },
    };

    if (bridgeObject) {
      bridgeWrapper = function(message) {
        emit(Object.assign({
          kind:"bridge_send",
          direction:"outbound",
          pageTime:Date.now(),
          monotonicMs:performance.now(),
          panelState:panelState(),
          message:safeClone(message)
        }, wireFacts(message)));
        return bridgeSendDelegate.apply(this, arguments);
      };
      bridgeObject.send = bridgeWrapper;
    }

    if (uiDataObject) {
      uiWrapper = function(payload) {
        emit({
          kind:"uidata_dispatch",
          direction:"inbound",
          pageTime:Date.now(),
          monotonicMs:performance.now(),
          payload:safeClone(payload)
        });
        return uiDispatchDelegate.apply(this, arguments);
      };
      uiDataObject.dispatch = uiWrapper;
    }

    if (panelMuxPrototype && panelRequestDelegate) {
      panelRequestWrapper = function(cmd, payload, optionsArg, callbackArg) {
        const args = Array.prototype.slice.call(arguments);
        let callback = callbackArg;
        let optionsCopy = {};
        if (typeof optionsArg === "function") callback = optionsArg;
        else if (optionsArg && typeof optionsArg === "object") {
          Object.keys(optionsArg).forEach(function(key) { optionsCopy[key] = optionsArg[key]; });
        }
        const priorOnIssued = optionsCopy.onIssued;
        optionsCopy.onIssued = function(entry, message) {
          emit(Object.assign({
            kind:"panel_request_issued",
            direction:"outbound",
            pageTime:Date.now(),
            monotonicMs:performance.now(),
            callId:entry && String(entry.callId || ""),
            cmd:entry && String(entry.cmd || ""),
            metadata:safeClone(entry && entry.metadata || {}),
            message:safeClone(message)
          }, wireFacts(message)));
          if (typeof priorOnIssued === "function") {
            return priorOnIssued.apply(this, arguments);
          }
        };
        args[2] = optionsCopy;
        args[3] = callback;
        return panelRequestDelegate.apply(this, args);
      };
      panelMuxPrototype.request = panelRequestWrapper;
    }

      webviewHandler = function(event) {
      emit(Object.assign({
        kind:"webview_message",
        direction:"inbound",
        pageTime:Date.now(),
        monotonicMs:performance.now(),
        panelState:panelState(),
        message:safeClone(event.data)
      }, wireFacts(event.data)));
    };
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.addEventListener("message", webviewHandler);
    }

    clickHandler = function(event) {
      emit({
        kind:"dom_input",
        eventType:"click",
        direction:"input",
        pageTime:Date.now(),
        monotonicMs:performance.now(),
        isTrusted:event.isTrusted === true,
        button:Number(event.button),
        clientX:Number(event.clientX),
        clientY:Number(event.clientY),
        key:null,
        repeat:false,
        target:stableTarget(event.target, event),
        panelState:panelState()
      });
    };
    keyHandler = function(event) {
      emit({
        kind:"dom_input",
        eventType:"keydown",
        direction:"input",
        pageTime:Date.now(),
        monotonicMs:performance.now(),
        isTrusted:event.isTrusted === true,
        key:boundedText(event.key, 40),
        repeat:event.repeat === true,
        button:null,
        target:stableTarget(event.target, event),
        panelState:panelState()
      });
    };
    document.addEventListener("click", clickHandler, true);
    document.addEventListener("keydown", keyHandler, true);
    window[markerName] = marker;
    emit({
      kind:"observer_ready",
      pageTime:Date.now(),
      monotonicMs:performance.now(),
      url:String(location.href),
      bridgeWrapped:!!bridgeSendDelegate,
      uiDataWrapped:!!uiDispatchDelegate,
      panelRequestMuxWrapped:!!panelRequestDelegate,
      webviewObserved:!!(window.chrome && window.chrome.webview),
      observationOnly:true,
      businessActionMethods:[],
      panelState:panelState()
    });
    return {
      ok:true,
      url:String(location.href),
      bridgeWrapped:!!bridgeSendDelegate,
      uiDataWrapped:!!uiDispatchDelegate,
      panelRequestMuxWrapped:!!panelRequestDelegate,
      webviewObserved:!!(window.chrome && window.chrome.webview)
    };
  };
}

function authoritativeIconNamesForLifecycle(events, lifecycle) {
  const opens = (events || []).filter((event) => event && event.kind === "webview_message"
    && event.direction === "inbound" && event.message && event.message.type === "panel_cmd"
    && event.message.panel === "kshop" && event.message.cmd === "open"
    && typeof event.message.panelInstanceId === "string" && event.message.panelInstanceId);
  const lifecycleIndex = lifecycle === "first" ? 0 : lifecycle === "restart" ? 1 : -1;
  const open = lifecycleIndex >= 0 ? opens[lifecycleIndex] : null;
  if (!open) {
    fail("dynamic_icon_lifecycle_open_missing", "production_closure",
      "loaded icon projection lacks its lifecycle KShop owner", { lifecycle });
  }
  const nextOpen = opens[lifecycleIndex + 1] || null;
  const panelInstanceId = open.message.panelInstanceId;
  const names = [];
  function add(value) {
    const name = String(value || "").trim();
    if (name && !names.includes(name)) names.push(name);
  }
  (events || []).filter((event) => event && event.sequence > open.sequence
    && (!nextOpen || event.sequence < nextOpen.sequence)
    && event.kind === "webview_message" && event.direction === "inbound"
    && event.message && event.message.type === "panel_resp"
    && event.message.panel === "kshop" && event.message.panelInstanceId === panelInstanceId
    && event.message.success === true).forEach((event) => {
    const message = event.message;
    (Array.isArray(message.catalog) ? message.catalog : []).forEach((item) => add(item && item.icon));
    (Array.isArray(message.purchased) ? message.purchased : []).forEach((item) => add(item && item.icon));
    (Array.isArray(message.snapshots) ? message.snapshots : []).forEach((snapshot) => {
      (snapshot && Array.isArray(snapshot.slots) ? snapshot.slots : []).forEach((slot) => {
        if (slot && slot.occupied === true && slot.item) add(slot.item.icon);
      });
    });
  });
  if (!names.length) {
    fail("dynamic_icon_authority_empty", "production_closure",
      "lifecycle authority did not expose any catalog/inventory icon names", {
        lifecycle, panelInstanceId,
      });
  }
  return names;
}

function flattenResourceTree(tree) {
  const occurrences = [];
  let frameOccurrence = 0;
  (function visit(frameTree) {
    if (!frameTree || !frameTree.frame || typeof frameTree.frame.id !== "string") return;
    frameOccurrence += 1;
    let frameOrigin = "opaque";
    try { frameOrigin = new URL(String(frameTree.frame.url || "")).origin; } catch (_error) {}
    (frameTree.resources || []).forEach((resource, resourceIndex) => {
      let urlOrigin = "opaque";
      try { urlOrigin = new URL(String(resource && resource.url || "")).origin; } catch (_error) {}
      occurrences.push({ occurrence: occurrences.length + 1,
        frameOccurrence, resourceOccurrence: resourceIndex + 1,
        frameId: frameTree.frame.id, frameUrl: String(frameTree.frame.url || ""),
        frameOrigin, url: String(resource && resource.url || ""), urlOrigin,
        type: String(resource && resource.type || ""),
        resource: resource && typeof resource === "object"
          ? JSON.parse(JSON.stringify(resource)) : {},
        sourceMethod: null, sourceSha256: null, sourceBytes: null, sourceError: null });
    });
    (frameTree.childFrames || []).forEach(visit);
  })(tree && tree.frameTree);
  return occurrences;
}

async function attachPassiveObserver(options) {
  const root = path.resolve(options.root);
  const writer = options.writer || new TranscriptWriter(options.runDir);
  const timeoutMs = options.timeoutMs || 30000;
  const pollMs = options.pollMs || 250;
  const cdpBinding = options.cdpBinding;
  const runtimeIdentity = options.runtimeIdentity;
  const requirePanelRequestMux = options.requirePanelRequestMux !== false;
  if (!isPlainObject(runtimeIdentity) || runtimeIdentity.pid !== cdpBinding.runtimePid) {
    fail("cdp_runtime_binding_mismatch", "observer",
      "CDP endpoint is not bound to the authenticated candidate PID");
  }
  if (!Number.isInteger(cdpBinding.port) || cdpBinding.port < 1024 || cdpBinding.port > 65535
      || cdpBinding.exclusiveBeforeLaunch !== true) {
    fail("cdp_binding_invalid", "observer", "runner-owned CDP binding is malformed");
  }
  const connected = await connectExactTarget(cdpBinding.port, OVERLAY_URL, timeoutMs, pollMs);
  const client = connected.client;
  const executionContexts = new Map();
  const rawExecutionContextOccurrences = [];
  const parsedScripts = new Map();
  const rawScriptOccurrences = [];
  const removeDebuggerListener = client.onEvent((message) => {
    if (message.method === "Runtime.executionContextCreated" && message.params
        && message.params.context && Number.isInteger(message.params.context.id)) {
      const context = message.params.context;
      const occurrence = { occurrence: rawExecutionContextOccurrences.length + 1,
        id: context.id, uniqueId: String(context.uniqueId || ""),
        origin: String(context.origin || ""), name: String(context.name || ""),
        auxData: context.auxData && typeof context.auxData === "object"
          ? JSON.parse(JSON.stringify(context.auxData)) : {} };
      rawExecutionContextOccurrences.push(occurrence);
      executionContexts.set(context.id, occurrence);
      return;
    }
    if (message.method !== "Debugger.scriptParsed" || !message.params
      || typeof message.params.scriptId !== "string" || typeof message.params.url !== "string"
        || !Number.isInteger(message.params.executionContextId)) return;
    rawScriptOccurrences.push({ occurrence: rawScriptOccurrences.length + 1,
      scriptId: message.params.scriptId, url: message.params.url,
      executionContextId: message.params.executionContextId,
      startLine: Number(message.params.startLine), startColumn: Number(message.params.startColumn),
      endLine: Number(message.params.endLine), endColumn: Number(message.params.endColumn),
      sourceMapUrl: String(message.params.sourceMapURL || "") });
    const scriptIds = parsedScripts.get(message.params.url) || [];
    scriptIds.push(message.params.scriptId);
    parsedScripts.set(message.params.url, scriptIds);
  });
  await client.call("Runtime.enable", {}, 10000);
  await client.call("Debugger.enable", {}, 10000);
  await client.call("Page.enable", {}, 10000);
  const endpointAttestation = attestLoopbackCdpEndpoint({
    port: cdpBinding.port,
    runtimePid: cdpBinding.runtimePid,
    expectedUserDataRoot: path.join(root, "launcher", "webview2_overlay_userdata", "EBWebView"),
    expectedExecutableName: "msedgewebview2.exe",
  });
  const pageObservation = await evaluateByValue(client, "({identity:{url:String(location.href),"
    + "origin:String(location.origin),timeOrigin:Number(performance.timeOrigin),"
    + "readyState:String(document.readyState),userAgent:String(navigator.userAgent)},"
    + "content:String(document.documentElement&&document.documentElement.outerHTML||'')})",
  "Overlay identity");
  const pageIdentity = pageObservation.identity;
  if (pageIdentity.url !== OVERLAY_URL || !Number.isFinite(pageIdentity.timeOrigin)) {
    fail("overlay_page_identity_invalid", "observer", "bound Overlay page identity is invalid");
  }
  if (pageIdentity.origin !== new URL(OVERLAY_URL).origin || !pageObservation.content) {
    fail("overlay_page_content_invalid", "observer", "bound Overlay origin/content is invalid");
  }
  cdpBinding.attestation = endpointAttestation;
  cdpBinding.pageIdentity = pageIdentity;
  cdpBinding.pageIdentitySha256 = sha256Text(canonicalJson(pageIdentity));
  cdpBinding.pageContentSha256 = sha256Text(pageObservation.content);
  cdpBinding.pageContentBytes = Buffer.byteLength(pageObservation.content, "utf8");
  cdpBinding.pageContentCapturedAt = new Date().toISOString();
  writer.append({
    kind: "cdp_endpoint_bound",
    cdpPort: cdpBinding.port,
    runtimePid: cdpBinding.runtimePid,
    exclusiveBeforeLaunch: true,
    configurationSource: cdpBinding.configurationSource,
    pageUrl: OVERLAY_URL,
    endpointAttestation,
    pageIdentity,
    pageIdentitySha256: cdpBinding.pageIdentitySha256,
    pageContentSha256: cdpBinding.pageContentSha256,
    pageContentBytes: cdpBinding.pageContentBytes,
    pageContentCapturedAt: cdpBinding.pageContentCapturedAt,
  });
  await client.call("Runtime.addBinding", { name: BINDING_NAME }, 10000);
  const removeBindingListener = client.onEvent((message) => {
    if (message.method !== "Runtime.bindingCalled" || !message.params
        || message.params.name !== BINDING_NAME || typeof message.params.payload !== "string") return;
    let rawEvent;
    try { rawEvent = JSON.parse(message.params.payload); }
    catch (error) { fail("observer_binding_payload_invalid", "observer", error.message); }
    writer.append(redactOpaqueTokens(rawEvent));
  });
  const installed = await evaluateByValue(client,
    "(" + browserInjectionSource().toString() + ")(" + JSON.stringify({
      bindingName: BINDING_NAME,
      markerName: MARKER_NAME,
    }) + ")",
  "observer installation");
  if (!installed || installed.ok !== true || installed.url !== OVERLAY_URL
      || installed.bridgeWrapped !== true
      || requirePanelRequestMux && installed.panelRequestMuxWrapped !== true
      || installed.webviewObserved !== true) {
    fail("observer_install_failed", "observer", "passive observer did not bind exact Overlay primitives", installed);
  }
  writer.flush({
    cdpPort: cdpBinding.port,
    runtimePid: cdpBinding.runtimePid,
    exclusiveBeforeLaunch: true,
    attachedAt: new Date().toISOString(),
    detachedAt: null,
  });
  let detached = false;
  let detachResult = null;
  const publicObserver = {
    cdpBinding,
    endpointAttestation,
    pageIdentity,
    async health() {
      const state = await evaluateByValue(client, "(function(){const marker=window["
        + JSON.stringify(MARKER_NAME) + "];return marker&&typeof marker.health==='function'"
        + "?marker.health():{installed:false,bridgeCurrent:false,uiDataCurrent:false,"
        + "panelRequestMuxCurrent:false,url:String(location.href)};})()", "observer health");
      if (!state.installed || !state.bridgeCurrent || !state.uiDataCurrent
          || requirePanelRequestMux && !state.panelRequestMuxCurrent
          || state.url !== OVERLAY_URL) {
        fail("observer_health_failed", "observer", "passive observer lost its exact bindings", state);
      }
      return state;
    },
    async panelState() {
      return evaluateByValue(client, "(function(){const container=document.getElementById('panel-container');"
        + "return{panel:container?String(container.getAttribute('data-panel')||''):'',"
        + "hidden:container?!!container.hidden||container.style.display==='none':true,"
        + "kshopVisible:!!(container&&!container.hidden&&container.style.display!=='none'"
        + "&&String(container.getAttribute('data-panel')||'')==='kshop')};})()",
      "KShop visible state");
    },
    async captureProductionClosure(productionClosure, productionBinding, lifecycle) {
      if (!detached) {
        fail("loaded_production_not_terminal", "production_closure",
          "production closure may be captured only after the observer detach evaluation");
      }
      const expectedWeb = ProductionClosure.webFiles(productionClosure);
      const deadline = Date.now() + timeoutMs;
      const scriptEntries = ProductionClosure.scriptFiles(productionClosure);
      const styleEntries = ProductionClosure.styleFiles(productionClosure);
      const expectedExecutables = ProductionClosure.expectedExecutableOccurrences(productionClosure);
      const iconNames = authoritativeIconNamesForLifecycle(writer.events, lifecycle);
      const iconProjection = ProductionClosure.iconResourceSetForNames(
        root, productionClosure, iconNames);
      const fontEnvironment = ProductionClosure.captureFontEnvironment(
        root, productionClosure, process.env);
      const expectedOwnedEvaluations = snapshotOwnedEvaluations(client);
      const expectedUrls = expectedExecutables.map((entry) => entry.url)
        .concat(expectedOwnedEvaluations.map((entry) => entry.url));
      while (Date.now() <= deadline) {
        const observedCounts = new Map();
        rawScriptOccurrences.forEach((entry) => observedCounts.set(entry.url,
          Number(observedCounts.get(entry.url) || 0) + 1));
        const expectedCounts = new Map();
        expectedUrls.forEach((url) => expectedCounts.set(url,
          Number(expectedCounts.get(url) || 0) + 1));
        const missing = Array.from(expectedCounts.entries()).filter(([url, count]) =>
          Number(observedCounts.get(url) || 0) < count);
        if (missing.length === 0) break;
        await sleep(pollMs);
      }
      const ownedEvaluations = snapshotOwnedEvaluations(client);
      if (canonicalJson(ownedEvaluations) !== canonicalJson(expectedOwnedEvaluations)) {
        fail("loaded_owned_evaluation_plan_changed", "production_closure",
          "observer-owned execution plan changed during terminal capture");
      }
      const enrichedScriptOccurrences = [];
      for (const occurrence of rawScriptOccurrences) {
        const result = await client.call("Debugger.getScriptSource",
          { scriptId: occurrence.scriptId }, 15000);
        if (!result || typeof result.scriptSource !== "string") {
          fail("loaded_executable_source_invalid", "production_closure",
            "CDP could not read one raw executable occurrence", { occurrence: occurrence.occurrence });
        }
        const source = Buffer.from(result.scriptSource, "utf8");
        const context = executionContexts.get(occurrence.executionContextId) || null;
        let urlOrigin = null;
        try { urlOrigin = new URL(occurrence.url).origin; } catch (_error) { urlOrigin = "opaque"; }
        enrichedScriptOccurrences.push(Object.assign({}, occurrence, {
          urlOrigin, context: context && Object.assign({}, context),
          sourceMethod: "Debugger.getScriptSource", sha256: sha256Bytes(source),
          bytes: source.length,
        }));
      }
      const expectedProductionUrlSet = new Set(expectedExecutables.map((entry) => entry.url));
      const expectedToolUrls = ownedEvaluations.map((entry) => entry.url);
      const expectedToolUrlSet = new Set(expectedToolUrls);
      const productionOccurrences = enrichedScriptOccurrences.filter((entry) =>
        expectedProductionUrlSet.has(entry.url));
      const toolOccurrences = enrichedScriptOccurrences.filter((entry) => expectedToolUrlSet.has(entry.url));
      void toolOccurrences;
      const loadedScripts = [];
      for (const expected of scriptEntries) {
        const suffix = expected.locator.slice("root:launcher/web/".length);
        const url = "https://overlay.local/" + suffix;
        const matches = productionOccurrences.filter((entry) => entry.url === url);
        const match = matches[0] || null;
        loadedScripts.push({ role: expected.role, locator: expected.locator, url,
          sourceMethod: "Debugger.getScriptSource", sha256: match && match.sha256,
          bytes: match && match.bytes, occurrence: match && match.occurrence });
      }
      const mandatoryResources = ProductionClosure.expectedStaticResourceSet(productionClosure)
        .concat(iconProjection.resources);
      let tree = null;
      let rawResourceOccurrences = [];
      let missingResources = mandatoryResources.slice();
      while (Date.now() <= deadline) {
        tree = await client.call("Page.getResourceTree", {}, 15000);
        rawResourceOccurrences = flattenResourceTree(tree);
        const observed = new Map();
        rawResourceOccurrences.forEach((entry) => {
          const key = entry.url + "\u0000" + entry.type;
          observed.set(key, Number(observed.get(key) || 0) + 1);
        });
        missingResources = mandatoryResources.filter((entry) =>
          Number(observed.get(entry.url + "\u0000" + entry.type) || 0) !== 1);
        if (!missingResources.length) break;
        await sleep(pollMs);
      }
      if (!tree || missingResources.length) {
        fail("loaded_resource_tree_incomplete", "production_closure",
          "terminal Page resource tree lacks one mandatory fixed/icon resource", {
            missing: missingResources.map((entry) => ({ url: entry.url, type: entry.type })),
          });
      }
      const frameId = tree && tree.frameTree && tree.frameTree.frame && tree.frameTree.frame.id;
      if (typeof frameId !== "string") fail("loaded_production_page_invalid", "production_closure",
        "CDP resource tree lacks the exact Overlay main frame");
      const pageResult = await client.call("Page.getResourceContent",
        { frameId, url: OVERLAY_URL }, 15000);
      if (!pageResult || typeof pageResult.content !== "string") {
        fail("loaded_production_page_invalid", "production_closure",
          "CDP could not read the actually loaded Overlay resource");
      }
      const pageBytes = pageResult.base64Encoded === true
        ? Buffer.from(pageResult.content, "base64") : Buffer.from(pageResult.content, "utf8");
      const pageExpected = expectedWeb.find((entry) => entry.role === "page");
      const loadedPage = { role: "page", locator: pageExpected.locator, url: OVERLAY_URL,
        sourceMethod: "Page.getResourceContent", sha256: sha256Bytes(pageBytes),
        bytes: pageBytes.length };
      const boundResources = new Map();
      ProductionClosure.cssConditionalResourceSet(productionClosure)
        .concat(iconProjection.resources)
        .concat(fontEnvironment.installed.map((entry) => ({
          url: entry.url, type: "Font", sha256: entry.sha256, bytes: entry.bytes,
        }))).forEach((entry) => {
          if (boundResources.has(entry.url)) {
            fail("loaded_conditional_resource_collision", "production_closure",
              "conditional resource layers share one URL", { url: entry.url });
          }
          boundResources.set(entry.url, entry);
        });
      for (const occurrence of rawResourceOccurrences) {
        const expected = boundResources.get(occurrence.url);
        if (!expected || occurrence.type !== expected.type) continue;
        occurrence.sourceMethod = "Page.getResourceContent";
        try {
          const result = await client.call("Page.getResourceContent",
            { frameId: occurrence.frameId, url: occurrence.url }, 15000);
          if (!result || typeof result.content !== "string") {
            throw new Error("resource content unavailable");
          }
          const bytes = result.base64Encoded === true
            ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
          occurrence.sourceSha256 = sha256Bytes(bytes);
          occurrence.sourceBytes = bytes.length;
        } catch (error) {
          occurrence.sourceError = String(error && error.message || error || "resource read failed");
        }
      }
      const stylesheetOccurrences = rawResourceOccurrences.filter((resource) =>
        resource.type === "Stylesheet" || /\.css(?:$|[?#])/.test(resource.url));
      const loadedStylesheets = [];
      for (const expected of styleEntries) {
        const suffix = expected.locator.slice("root:launcher/web/".length);
        const url = "https://overlay.local/" + suffix;
        const matches = stylesheetOccurrences.filter((entry) => entry.url === url);
        const match = matches[0] || null;
        let bytes = null;
        if (match) {
          const result = await client.call("Page.getResourceContent",
            { frameId: match.frameId, url }, 15000);
          if (result && typeof result.content === "string") {
            bytes = result.base64Encoded === true
              ? Buffer.from(result.content, "base64") : Buffer.from(result.content, "utf8");
          }
        }
        loadedStylesheets.push({ role: expected.role, locator: expected.locator, url,
          sourceMethod: "Page.getResourceContent", sha256: bytes && sha256Bytes(bytes),
          bytes: bytes && bytes.length, occurrence: match && match.occurrence });
      }
      const value = { schema: ProductionClosure.LOADED_SCHEMA, lifecycle,
        capturePhase: "post_observer_detach",
        runtimePid: runtimeIdentity.pid, runId: productionBinding.runId,
        productionClosureSha256: productionClosure.closureSha256,
        productionBindingSha256: productionBinding.bindingSha256,
        page: loadedPage,
        rawScriptOccurrences: enrichedScriptOccurrences,
        rawExecutionContextOccurrences: JSON.parse(JSON.stringify(rawExecutionContextOccurrences)),
        productionScriptOccurrences: productionOccurrences,
        ownedEvaluations,
        rawResourceOccurrences,
        fontEnvironment,
        iconProjection,
        scripts: loadedScripts,
        stylesheets: loadedStylesheets };
      value.evidenceSha256 = sha256Text(canonicalJson(value));
      return value;
    },
    async detach(productionClosure, productionBinding, lifecycle) {
      if (detached) return detachResult;
      detached = true;
      let detachError = null;
      try {
        await evaluateByValue(client, "(function(){const marker=window["
          + JSON.stringify(MARKER_NAME) + "];if(marker&&typeof marker.uninstall==='function')"
          + "marker.uninstall();return true;})()", "observer detach");
      } catch (error) {
        detachError = error;
        writer.append({
          kind:"observer_detach_transport_lost",
          pageTime:null,
        });
      }
      let loadedProduction = null;
      try {
        if (productionClosure || productionBinding || lifecycle) {
          if (!productionClosure || !productionBinding || !["first", "restart"].includes(lifecycle)) {
            fail("terminal_capture_arguments_invalid", "production_closure",
              "detach terminal capture requires closure, binding, and lifecycle together");
          }
          if (detachError) {
            fail("observer_detach_evaluation_failed", "production_closure",
              "terminal capture cannot close a lost detach evaluation", {
                error: String(detachError && detachError.message || detachError),
              });
          }
          loadedProduction = await publicObserver.captureProductionClosure(
            productionClosure, productionBinding, lifecycle);
        }
      } finally {
        removeBindingListener();
        removeDebuggerListener();
        client.close();
      }
      const transcript = writer.flush({
        cdpPort: cdpBinding.port,
        runtimePid: cdpBinding.runtimePid,
        detachedAt: new Date().toISOString(),
      });
      detachResult = { transcript, loadedProduction };
      return detachResult;
    },
  };
  return Object.freeze(publicObserver);
}

module.exports = {
  BINDING_NAME,
  MARKER_NAME,
  OVERLAY_URL,
  TranscriptWriter,
  attachPassiveObserver,
  authoritativeIconNamesForLifecycle,
  browserInjectionSource,
};
