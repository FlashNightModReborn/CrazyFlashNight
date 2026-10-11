"use strict";

const childProcess = require("child_process");
const path = require("path");

function httpSysOwners(text, port) {
  // netsh's English Request Queue View is the observed Windows contract here.
  // Unknown/localized output is rejected; PID 4 alone is never ownership proof.
  if (typeof text !== "string" || !/Snapshot of HTTP service state \(Request Queue View\):/.test(text)) {
    throw new Error("unsupported HTTP.sys request-queue output");
  }
  const starts = [...text.matchAll(/^Request queue name:/gm)].map((match) => match.index);
  const matches = [];
  starts.forEach((start, index) => {
    const section = text.slice(start, starts[index + 1] === undefined ? text.length : starts[index + 1]);
    const urls = [...section.matchAll(/^\s*(https?:\/\/[^\s]+)\s*$/gim)].map((match) => match[1]);
    const relevant = urls.filter((url) => new RegExp(`^https?://[^/]+:${port}/`, "i").test(url));
    if (relevant.length === 0) return;
    const pids = [...section.matchAll(/^\s+ID:\s*([0-9]+),\s*image:/gm)].map((match) => Number(match[1]));
    const active = /^ {4}State:\s*Active\s*$/m.test(section);
    const attached = /^ {4}Number of active processes attached:\s*([0-9]+)\s*$/m.exec(section);
    if (!active || pids.length === 0 || !attached || Number(attached[1]) !== pids.length) {
      throw new Error("HTTP.sys queue has no verifiable active process owner");
    }
    matches.push({ pids, urls: relevant });
  });
  if (matches.length === 0) throw new Error("HTTP.sys has no registered request queue for the Worker endpoint");
  return matches;
}

function assertEndpointOwnership(owner, observation) {
  const process = observation && observation.process;
  if (!process || process.pid !== owner.hostPid || process.processStartUtcTicks !== owner.processStartUtcTicks
      || typeof process.processPath !== "string" || path.resolve(process.processPath).toLowerCase() !== path.resolve(owner.processPath).toLowerCase()) {
    throw new Error("Worker endpoint process identity mismatch");
  }
  const listeners = observation.listeners;
  if (!Array.isArray(listeners) || listeners.length === 0
      || listeners.some((entry) => entry.localPort !== owner.httpPort || !Number.isInteger(entry.owningProcess))) {
    throw new Error("Worker endpoint has no exact listening owner");
  }
  if (listeners.every((entry) => entry.owningProcess === owner.hostPid)) return "tcp_process";
  if (!listeners.every((entry) => entry.owningProcess === 4)) throw new Error("Worker endpoint listener belongs to another process");
  const queues = httpSysOwners(observation.httpServiceState, owner.httpPort);
  if (queues.some((queue) => queue.pids.some((pid) => pid !== owner.hostPid))) {
    throw new Error("Worker HTTP.sys endpoint queue belongs to another process");
  }
  const expectedPrefix = `http://localhost:${owner.httpPort}/`;
  if (!queues.some((queue) => queue.urls.some((url) => url.toLowerCase() === expectedPrefix))) {
    throw new Error("Worker HTTP.sys endpoint lacks the exact localhost prefix");
  }
  return "http_sys_request_queue";
}

function queryWorkerOwnership(owner) {
  if (!Number.isSafeInteger(owner.hostPid) || owner.hostPid < 1 || !Number.isInteger(owner.httpPort)
      || owner.httpPort < 1 || owner.httpPort > 65535) throw new Error("invalid Worker ownership probe input");
  const script = "chcp.com 65001 | Out-Null; $ErrorActionPreference='Stop'; "
    + "$taskProcess=Get-Process -Id " + owner.hostPid + " -ErrorAction Stop; "
    + "$taskListeners=@(Get-NetTCPConnection -State Listen -LocalPort " + owner.httpPort
    + " -ErrorAction SilentlyContinue | ForEach-Object { @{localPort=[int]$_.LocalPort;localAddress=$_.LocalAddress;owningProcess=[int]$_.OwningProcess} }); "
    + "$taskHttpState=''; if (@($taskListeners | Where-Object { $_.owningProcess -eq 4 }).Count -gt 0) { "
    + "$taskHttpLines=& netsh.exe http show servicestate view=requestq verbose=yes; if ($LASTEXITCODE -ne 0) { throw 'HTTP service state unavailable' }; "
    + "$taskHttpState=[string]::Join([Environment]::NewLine,$taskHttpLines) }; "
    + "@{process=@{pid=$taskProcess.Id;processPath=$taskProcess.Path;processStartUtcTicks=$taskProcess.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)};"
    + "listeners=$taskListeners;httpServiceState=$taskHttpState} | ConvertTo-Json -Depth 5 -Compress";
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
    encoding: "utf8", windowsHide: true, timeout: 15000, maxBuffer: 4 * 1024 * 1024,
  });
  if (result.status !== 0) throw new Error("Worker endpoint ownership probe unavailable; no credential was sent");
  try { return JSON.parse(result.stdout.trim()); }
  catch (_error) { throw new Error("Worker endpoint ownership probe returned invalid data"); }
}

module.exports = { assertEndpointOwnership, httpSysOwners, queryWorkerOwnership };
