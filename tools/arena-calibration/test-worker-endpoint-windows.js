#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const http = require("http");
const net = require("net");
const { assertEndpointOwnership, queryWorkerOwnership } = require("./lib/arena-worker-endpoint");
const { queryProcess } = require("./lib/arena-worker-client");
const { isSameProcessAlive } = require("./run-worker-shard");

async function main() {
  if (process.platform !== "win32") {
    console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", windowsHttpSys: "not_run_on_this_platform" }));
    return;
  }
  const port = await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => { const value = server.address().port; server.close(() => resolve(value)); });
  });
  const script = "chcp.com 65001 | Out-Null; $ErrorActionPreference='Stop'; "
    + "$taskListener=[Net.HttpListener]::new(); $taskListener.Prefixes.Add('http://localhost:" + port + "/'); "
    + "try { $taskListener.Start(); $taskSelf=Get-Process -Id $PID; "
    + "[Console]::WriteLine((@{hostPid=$PID;httpPort=" + port + ";processPath=$taskSelf.Path;"
    + "processStartUtcTicks=$taskSelf.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)} | ConvertTo-Json -Compress)); "
    + "$taskContext=$taskListener.GetContext(); $taskBody=[Text.Encoding]::UTF8.GetBytes('fixture-only'); "
    + "$taskContext.Response.ContentLength64=$taskBody.Length; $taskContext.Response.OutputStream.Write($taskBody,0,$taskBody.Length); "
    + "$taskContext.Response.Close() } finally { $taskListener.Close() }";
  const child = childProcess.spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")],
    { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  try {
    const owner = await new Promise((resolve, reject) => {
      let buffer = "";
      const timer = setTimeout(() => reject(new Error("owned HTTP.sys fixture startup timeout")), 20000);
      child.once("error", (error) => { clearTimeout(timer); reject(error); });
      child.once("exit", (code) => { clearTimeout(timer); reject(new Error(`owned HTTP.sys fixture exited before readiness: ${code} ${stderr}`)); });
      child.stdout.setEncoding("utf8");
      child.stdout.on("data", (chunk) => {
        buffer += chunk;
        if (!buffer.includes("\n")) return;
        clearTimeout(timer);
        try { resolve(JSON.parse(buffer.split(/\r?\n/)[0])); }
        catch (error) { reject(error); }
      });
    });
    assert.strictEqual(owner.hostPid, child.pid);
    const process = queryProcess(owner.hostPid);
    assert.strictEqual(process.processStartUtcTicks, owner.processStartUtcTicks);
    assert.strictEqual(isSameProcessAlive(owner), true);
    const observation = queryWorkerOwnership(owner);
    assert.strictEqual(assertEndpointOwnership(owner, observation), "http_sys_request_queue");
    assert(observation.listeners.every((entry) => entry.owningProcess === 4));
    await new Promise((resolve, reject) => {
      const request = http.get({ hostname: "127.0.0.1", port, path: "/", headers: { Host: `localhost:${port}` } }, (response) => {
        let body = "";
        response.setEncoding("utf8"); response.on("data", (chunk) => { body += chunk; });
        response.on("end", () => {
          try { assert.strictEqual(response.statusCode, 200); assert.strictEqual(body, "fixture-only"); resolve(); }
          catch (error) { reject(error); }
        });
      });
      request.setTimeout(5000, () => request.destroy(new Error("HTTP.sys fixture request timeout")));
      request.on("error", reject);
    });
    if (child.exitCode === null) await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("owned HTTP.sys fixture exit timeout")), 10000);
      child.once("exit", () => { clearTimeout(timer); resolve(); });
    });
    assert.strictEqual(child.exitCode, 0, stderr);
    assert.strictEqual(isSameProcessAlive(owner), false);
    console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", windowsHttpSysRequestQueueOwner: true,
      kernelPidAloneNotTrusted: true, directChildRecycled: true, productionCredentialsUsed: false }));
  } finally {
    if (child.exitCode === null) child.kill();
  }
}

main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
