"use strict";

const http = require("http");
const WebSocket = require("../../../launcher/perf/node_modules/playwright-core/lib/utilsBundle.js").ws;
const { fail, isPlainObject, sha256Bytes } = require("./common");

const MAX_CDP_MESSAGE_BYTES = 16 * 1024 * 1024;

function httpJson(port, pathname, timeoutMs) {
  return new Promise((resolve, reject) => {
    const request = http.request({ host: "127.0.0.1", port, path: pathname, method: "GET",
      timeout: timeoutMs || 3000 }, (response) => {
      const chunks = [];
      let bytes = 0;
      response.on("data", (chunk) => {
        bytes += chunk.length;
        if (bytes > MAX_CDP_MESSAGE_BYTES) {
          request.destroy(new Error("CDP HTTP response exceeded the evidence bound"));
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => {
        if (response.statusCode !== 200) return reject(new Error("CDP HTTP status " + response.statusCode));
        try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
        catch (error) { reject(error); }
      });
    });
    request.once("timeout", () => request.destroy(new Error("CDP HTTP timeout")));
    request.once("error", reject);
    request.end();
  });
}

class NarrowCdpClient {
  constructor(url) {
    this.url = url;
    this.socket = null;
    this.nextId = 0;
    this.pending = new Map();
    this.listeners = new Set();
    this.closed = false;
    this.ownedEvaluations = [];
  }

  async connect(timeoutMs) {
    if (this.socket || this.closed) throw new Error("CDP client cannot be reconnected");
    await new Promise((resolve, reject) => {
      const socket = new WebSocket(this.url, {
        followRedirects: false,
        handshakeTimeout: timeoutMs || 5000,
        maxPayload: MAX_CDP_MESSAGE_BYTES,
        perMessageDeflate: false,
      });
      this.socket = socket;
      const timer = setTimeout(() => {
        try { socket.terminate(); } catch (_error) {}
        reject(new Error("CDP WebSocket connection timeout"));
      }, timeoutMs || 5000);
      const rejectOpen = (error) => {
        clearTimeout(timer);
        reject(error);
      };
      socket.once("open", () => {
        clearTimeout(timer);
        socket.off("error", rejectOpen);
        resolve();
      });
      socket.once("error", rejectOpen);
      socket.on("message", (bytes) => this._message(bytes));
      socket.on("error", (error) => this.closeWithError(error));
      socket.on("close", () => this.closeWithError(new Error("CDP WebSocket closed")));
    });
    return this;
  }

  closeWithError(error) {
    if (this.closed) return;
    this.closed = true;
    this.pending.forEach((entry) => { clearTimeout(entry.timer); entry.reject(error); });
    this.pending.clear();
  }

  _message(bytes) {
    const payload = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
    if (payload.length > MAX_CDP_MESSAGE_BYTES) {
      try { this.socket.terminate(); } catch (_error) {}
      this.closeWithError(new Error("CDP WebSocket message exceeded the evidence bound"));
      return;
    }
    let message;
    try { message = JSON.parse(payload.toString("utf8")); }
    catch (error) {
      try { this.socket.terminate(); } catch (_error) {}
      this.closeWithError(error);
      return;
    }
    if (Number.isInteger(message.id)) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error("CDP " + pending.method + ": "
        + String(message.error.message || "protocol error")));
      else pending.resolve(message.result || {});
      return;
    }
    if (typeof message.method === "string") this.listeners.forEach((listener) => listener(message));
  }

  onEvent(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  call(method, params, timeoutMs) {
    if (this.closed || !this.socket || this.socket.readyState !== WebSocket.OPEN
        || typeof method !== "string" || !method) {
      return Promise.reject(new Error("CDP client is closed or method is invalid"));
    }
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("CDP call timeout: " + method));
      }, timeoutMs || 10000);
      this.pending.set(id, { resolve, reject, timer, method });
      this.socket.send(JSON.stringify({ id, method, params: params || {} }), (error) => {
        if (!error) return;
        const pending = this.pending.get(id);
        if (!pending) return;
        clearTimeout(pending.timer);
        this.pending.delete(id);
        pending.reject(error);
      });
    });
  }

  close() {
    if (this.closed) return;
    try { this.socket.close(); } catch (_error) {}
    this.closeWithError(new Error("CDP client detached"));
  }
}

function validateWebSocketUrl(webSocketUrl, expectedPort) {
  let parsed;
  try { parsed = new URL(webSocketUrl); }
  catch (error) { throw error; }
  if (parsed.protocol !== "ws:" || parsed.hostname !== "127.0.0.1"
      || Number(parsed.port) !== Number(expectedPort) || parsed.username || parsed.password
      || !/^\/devtools\/page\/[A-Za-z0-9_-]+$/.test(parsed.pathname) || parsed.search || parsed.hash) {
    throw new Error("CDP target WebSocket is not the exact loopback page endpoint");
  }
  return parsed.toString();
}

async function connectWebSocket(webSocketUrl, expectedPort, timeoutMs) {
  const client = new NarrowCdpClient(validateWebSocketUrl(webSocketUrl, expectedPort));
  return client.connect(timeoutMs || 5000);
}

async function discoverExactTarget(port, expectedUrl, timeoutMs) {
  const targets = await httpJson(port, "/json/list", timeoutMs);
  if (!Array.isArray(targets)) fail("cdp_target_list_invalid", "observer",
    "CDP target list is not an array");
  const matching = targets.filter((entry) => isPlainObject(entry) && entry.type === "page"
    && entry.url === expectedUrl && typeof entry.webSocketDebuggerUrl === "string");
  if (matching.length !== 1) fail("overlay_page_not_exact", "observer",
    "expected exactly one production Overlay page on the bound CDP endpoint", {
      observedUrls: targets.map((entry) => entry && entry.url).filter(Boolean),
    });
  validateWebSocketUrl(matching[0].webSocketDebuggerUrl, port);
  return matching[0];
}

async function connectExactTarget(port, expectedUrl, timeoutMs, pollMs) {
  const deadline = Date.now() + Number(timeoutMs || 30000);
  let lastError = null;
  while (Date.now() <= deadline) {
    try {
      const target = await discoverExactTarget(port, expectedUrl, 3000);
      return { target, client: await connectWebSocket(target.webSocketDebuggerUrl, port, 5000) };
    } catch (error) { lastError = error; }
    await new Promise((resolve) => setTimeout(resolve, Math.max(100, Number(pollMs || 250))));
  }
  fail("cdp_attach_timeout", "observer", "exact Overlay CDP target was unavailable", {
    port, lastError: lastError && lastError.message,
  });
}

function valueFromEvaluation(result, label) {
  const remote = result && result.result;
  if (!remote || remote.subtype === "error" || remote.type === "undefined"
      || !Object.prototype.hasOwnProperty.call(remote, "value")) {
    fail("cdp_evaluation_invalid", "observer", label + " did not return one by-value result");
  }
  return remote.value;
}

async function evaluateByValue(client, expression, label) {
  if (!(client instanceof NarrowCdpClient)) {
    fail("cdp_evaluation_client_invalid", "observer", "owned evaluation lacks the exact CDP client");
  }
  const sequence = client.ownedEvaluations.length + 1;
  const slug = String(label || "evaluation").toLowerCase().replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 80) || "evaluation";
  const url = "cf7-evidence://kshop/" + String(sequence).padStart(4, "0") + "-" + slug + ".js";
  const taggedExpression = String(expression) + "\n//# sourceURL=" + url;
  const bytes = Buffer.from(taggedExpression, "utf8");
  client.ownedEvaluations.push({ sequence, label: String(label || ""), url,
    sha256: sha256Bytes(bytes), bytes: bytes.length });
  const result = await client.call("Runtime.evaluate", { expression: taggedExpression,
    returnByValue: true, awaitPromise: true, userGesture: false, includeCommandLineAPI: false }, 15000);
  if (result.exceptionDetails) fail("cdp_evaluation_exception", "observer",
    label + " raised an exception", { exceptionDetails: result.exceptionDetails });
  return valueFromEvaluation(result, label);
}

function snapshotOwnedEvaluations(client) {
  if (!(client instanceof NarrowCdpClient) || !Array.isArray(client.ownedEvaluations)) {
    fail("cdp_evaluation_client_invalid", "observer", "owned evaluation registry is unavailable");
  }
  return client.ownedEvaluations.map((entry) => Object.assign({}, entry));
}

module.exports = {
  NarrowCdpClient,
  connectExactTarget,
  discoverExactTarget,
  evaluateByValue,
  httpJson,
  snapshotOwnedEvaluations,
};
