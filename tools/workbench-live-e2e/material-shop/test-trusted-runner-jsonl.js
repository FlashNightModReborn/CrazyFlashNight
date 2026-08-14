"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { EventEmitter } = require("events");
const { PassThrough } = require("stream");
const test = require("node:test");

const {
  CANDIDATE_ID,
  COMPLETION_PREFIX,
  COMPLETION_SCHEMA,
  MINIMUM_REQUEST_INTERVAL_MS,
  SLOT,
  createTrustedRunner,
} = require("./trusted-runner-jsonl");

const CORE_NAME = "CRAZYFLASHER7MercenaryEmpire.Core.exe";
const HANDLE = "content_handle_a5_000000000000";

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function fixture(t) {
  const temporary = fs.mkdtempSync(path.join(fs.realpathSync.native(os.tmpdir()),
    "cf7-a5-jsonl-"));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const resourcesRoot = path.join(temporary, "resources");
  const entry = path.join(resourcesRoot, "tools", "cf7-agent", "unattended.js");
  const candidateRoot = path.join(resourcesRoot, "tmp", "runtime-candidates", "v2", "a5");
  const processPath = path.join(candidateRoot, "runtime", CORE_NAME);
  fs.mkdirSync(path.dirname(entry), { recursive: true });
  fs.mkdirSync(path.dirname(processPath), { recursive: true });
  fs.writeFileSync(entry, "'use strict';\n", "utf8");
  const processBytes = Buffer.from("exact-a5-candidate-core-executable", "utf8");
  fs.writeFileSync(processPath, processBytes);
  const identity = {
    runtimeMode: "isolated_candidate",
    processPath,
    coreSha256: sha256(Buffer.from("exact-a5-candidate-core-library", "utf8")),
    buildIdentity: "B".repeat(64),
    payloadClosure: "C".repeat(64),
  };
  return {
    resourcesRoot,
    candidateRoot,
    entry,
    processPath,
    processSha256: sha256(processBytes),
    identity,
    preparation: {
      resourcesRoot,
      candidateRoot,
      runId: "a5-jsonl-test-run",
      buildSha256: "d".repeat(64),
      candidateIdentity: identity,
    },
  };
}

function completionFor(fx) {
  return {
    schema: COMPLETION_SCHEMA,
    runtimeMode: fx.identity.runtimeMode,
    processPath: fx.processPath,
    coreSha256: fx.processSha256,
    buildIdentity: fx.identity.buildIdentity.toLowerCase(),
    payloadClosure: fx.identity.payloadClosure.toLowerCase(),
    guardianProcessId: 4242,
    terminalReceipt: {
      actionId: "shutdown_action_a5_000000000000",
      auditSequence: 9,
      terminal: true,
      outcome: "input_dispatched",
      evidenceKind: "broker_dispatch",
      reasonCode: "shutdown_requested",
      reconcileKind: "none",
      retryable: false,
      actualTargetId: "shutdown_target_a5_000000000000",
      focusVerified: false,
      beforeObservationId: "shutdown_before_a5_000000000000",
      leaseState: "consumed",
    },
  };
}

class FakeChild extends EventEmitter {
  constructor(fx, behavior) {
    super();
    this.fx = fx;
    this.behavior = behavior || {};
    this.stdout = new PassThrough();
    this.stderr = new PassThrough();
    this.ended = false;
    this.input = "";
    this.stdin = {
      write: (chunk, encoding, callback) => {
        this.input += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
        if (typeof callback === "function") callback(null);
        this._drainRequests();
        return true;
      },
      end: () => {
        if (this.ended) return;
        this.ended = true;
        queueMicrotask(() => {
          if (this.behavior.onEnd) this.behavior.onEnd(this);
          else this.completeAndExit(0);
        });
      },
    };
  }

  _drainRequests() {
    for (;;) {
      const newline = this.input.indexOf("\n");
      if (newline < 0) return;
      const line = this.input.slice(0, newline);
      this.input = this.input.slice(newline + 1);
      const request = JSON.parse(line);
      queueMicrotask(() => {
        if (this.behavior.onRequest) this.behavior.onRequest(request, this);
      });
    }
  }

  result(id, result) {
    this.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
  }

  rpcError(id, code, message) {
    this.stdout.write(JSON.stringify({ jsonrpc: "2.0", id,
      error: { code, message } }) + "\n");
  }

  completion(value) {
    this.stderr.write(COMPLETION_PREFIX + JSON.stringify(value) + "\n");
  }

  exit(code, signal) {
    this.emit("exit", code, signal || null);
    this.emit("close", code, signal || null);
  }

  completeAndExit(code) {
    this.completion(completionFor(this.fx));
    queueMicrotask(() => this.exit(code));
  }
}

function makeRunner(t, behavior, options) {
  const fx = fixture(t);
  const calls = [];
  let monotonicNow = 0;
  const spawnImpl = (executable, args, spawnOptions) => {
    calls.push({ executable, args, options: spawnOptions });
    return new FakeChild(fx, behavior);
  };
  const runner = createTrustedRunner(fx.preparation,
    Object.assign({
      spawnImpl,
      requestTimeoutMs: 100,
      exitTimeoutMs: 100,
      monotonicNowImpl: () => monotonicNow,
      delayImpl: async (milliseconds) => { monotonicNow += milliseconds; },
    }, options || {}));
  return { fx, calls, runner };
}

function assertRejectCode(promise, code) {
  return assert.rejects(promise, (error) => {
    assert.strictEqual(error && error.code, code);
    return true;
  });
}

test("spawns only the exact materialized A5 wrapper and pairs out-of-order ids", async (t) => {
  const requests = [];
  const closedEnv = {
    PATH: "closed-test-path",
    CF7_WEBVIEW2_ARGS: "--remote-debugging-port=43117",
    CF7_WEBVIEW2_DEV_MODE: "1",
  };
  const { fx, calls, runner } = makeRunner(t, {
    onRequest(request, child) {
      requests.push(request);
      if (requests.length === 2) {
        child.result(requests[1].id, { value: "second" });
        child.result(requests[0].id, { value: "first" });
      }
    },
  }, { env: closedEnv });

  const first = runner.call("window.list", { ordinal: 1 });
  const second = runner.call("window.get", { ordinal: 2 });
  assert.strictEqual((await first).value, "first");
  assert.strictEqual((await second).value, "second");
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0].executable, process.execPath);
  assert.deepStrictEqual(calls[0].args, [fx.entry, "--adapter", "jsonl", "--slot", SLOT,
    "--candidate-id", CANDIDATE_ID]);
  assert.deepStrictEqual(calls[0].options, {
    cwd: fx.resourcesRoot,
    stdio: ["pipe", "pipe", "pipe"],
    shell: false,
    windowsHide: true,
    env: closedEnv,
  });

  const finished = await runner.finish();
  assert.deepStrictEqual(finished.completion, completionFor(fx));
  assert.strictEqual(finished.exitCode, 0);
  assert.strictEqual(finished.transcriptSha256, runner.canonicalTranscriptSha256());
  assert.match(finished.transcriptSha256, /^[a-f0-9]{64}$/);
  assert.deepStrictEqual(finished.transcript, runner.getTranscript());
  assert.strictEqual(runner.uncertainWrite, false);
});

test("paces the A5 JSONL stream before write and preserves shutdown headroom", async (t) => {
  let monotonicNow = 0;
  const observedAt = [];
  const { runner } = makeRunner(t, {
    onRequest(request, child) {
      observedAt.push(monotonicNow);
      child.result(request.id, { ordinal: observedAt.length });
    },
  }, {
    monotonicNowImpl: () => monotonicNow,
    delayImpl: async (milliseconds) => { monotonicNow += milliseconds; },
  });

  for (let index = 0; index < 121; index += 1) {
    const result = await runner.call("window.list", { ordinal: index });
    assert.strictEqual(result.ordinal, index + 1);
  }
  assert.strictEqual(observedAt[0], 0);
  assert.strictEqual(observedAt[1], MINIMUM_REQUEST_INTERVAL_MS);
  assert.strictEqual(observedAt[100], 60_000);
  assert.strictEqual(observedAt[120], 72_000);
  for (let index = 100; index < observedAt.length; index += 1) {
    assert.ok(observedAt[index] - observedAt[index - 100] >= 60_000);
  }
  await runner.finish();
});

test("request timeout excludes paced admission", async (t) => {
  let monotonicNow = 0;
  let releaseDelay;
  let delayStarted;
  const delayObserved = new Promise((resolve) => { delayStarted = resolve; });
  const blockedDelay = new Promise((resolve) => { releaseDelay = resolve; });
  const { runner } = makeRunner(t, {
    onRequest(request, child) { child.result(request.id, { ok: true }); },
  }, {
    requestTimeoutMs: 15,
    monotonicNowImpl: () => monotonicNow,
    delayImpl: async (milliseconds) => {
      delayStarted(milliseconds);
      await blockedDelay;
      monotonicNow += milliseconds;
    },
  });

  assert.strictEqual((await runner.call("window.list", {})).ok, true);
  const second = runner.call("window.list", {});
  assert.strictEqual(await delayObserved, MINIMUM_REQUEST_INTERVAL_MS);
  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.strictEqual(runner.fatal, null);
  releaseDelay();
  assert.strictEqual((await second).ok, true);
  await runner.finish();
});

test("readContent binds every range and verifies canonical base64, total, and hash", async (t) => {
  const content = Buffer.from("abcdefg", "utf8");
  const contentHash = sha256(content);
  const { runner } = makeRunner(t, {
    onRequest(request, child) {
      assert.strictEqual(request.method, "content.read");
      const bytes = content.subarray(request.params.offset,
        Math.min(content.length, request.params.offset + request.params.count));
      const result = {
        handle: HANDLE,
        offset: request.params.offset,
        totalLength: content.length,
        returnedBytes: bytes.length,
        final: request.params.offset + bytes.length === content.length,
        contentHash,
      };
      child.result(request.id, {
        result,
        metadata: {
          handle: result.handle,
          offset: result.offset,
          totalLength: result.totalLength,
          final: result.final,
          contentHash: result.contentHash,
        },
        contentBase64: bytes.toString("base64"),
      });
    },
  });
  const actual = await runner.readContent(HANDLE, {
    totalLength: content.length,
    contentHash,
    count: 3,
  });
  assert.deepStrictEqual(actual, content);
  await runner.finish();
});

test("readContent validates a production-sized WGC chunk without regexp stack growth", async (t) => {
  const content = Buffer.alloc(4_193_276, 0x7f);
  const contentHash = sha256(content);
  const { runner } = makeRunner(t, {
    onRequest(request, child) {
      assert.strictEqual(request.method, "content.read");
      const result = {
        handle: HANDLE,
        offset: 0,
        totalLength: content.length,
        returnedBytes: content.length,
        final: true,
        contentHash,
      };
      child.result(request.id, {
        result,
        metadata: {
          handle: result.handle,
          offset: result.offset,
          totalLength: result.totalLength,
          final: result.final,
          contentHash: result.contentHash,
        },
        contentBase64: content.toString("base64"),
      });
    },
  });
  assert.deepStrictEqual(await runner.readContent(HANDLE, {
    totalLength: content.length,
    contentHash,
  }), content);
  await runner.finish();
});

test("unknown and duplicate response ids fail closed", async (t) => {
  await t.test("unknown", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(_request, child) {
        child.result("not_pending_a5_000000000000", {});
      },
    });
    await assertRejectCode(runner.call("window.list", {}), "trusted_runner_response_unknown");
  });
  await t.test("duplicate", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(request, child) {
        child.result(request.id, { ok: true });
        child.result(request.id, { ok: true });
      },
    });
    assert.strictEqual((await runner.call("window.list", {})).ok, true);
    await new Promise((resolve) => setImmediate(resolve));
    await assertRejectCode(runner.finish(), "trusted_runner_response_duplicate");
  });
});

test("invalid JSON, request timeout, early exit, and nonzero exit fail closed", async (t) => {
  await t.test("invalid JSON", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(_request, child) {
        child.stdout.write('{"jsonrpc":"2.0","id":"x","id":"y","result":{}}\n');
      },
    });
    await assertRejectCode(runner.call("window.list", {}),
      "trusted_runner_response_json_invalid");
  });
  await t.test("timeout", async (t2) => {
    const { runner } = makeRunner(t2, { onRequest() {} }, { requestTimeoutMs: 15 });
    await assertRejectCode(runner.call("window.list", {}), "trusted_runner_request_timeout");
  });
  await t.test("early exit", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(_request, child) { child.exit(0); },
    });
    await assertRejectCode(runner.call("window.list", {}), "trusted_runner_early_exit");
  });
  await t.test("nonzero exit", async (t2) => {
    const { runner } = makeRunner(t2, {
      onEnd(child) { child.completeAndExit(7); },
    });
    await assertRejectCode(runner.finish(), "trusted_runner_exit_invalid");
  });
});

test("content corruption and completion pollution fail closed", async (t) => {
  await t.test("non-canonical base64", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(request, child) {
        child.result(request.id, {
          result: { handle: HANDLE, offset: 0, totalLength: 1, returnedBytes: 1,
            final: true, contentHash: "a".repeat(64) },
          metadata: { handle: HANDLE, offset: 0, totalLength: 1,
            final: true, contentHash: "a".repeat(64) },
          contentBase64: "!!!!",
        });
      },
    });
    await assertRejectCode(runner.readContent(HANDLE, { count: 1 }),
      "trusted_runner_content_base64_invalid");
  });
  await t.test("assembled hash mismatch", async (t2) => {
    const { runner } = makeRunner(t2, {
      onRequest(request, child) {
        const bytes = Buffer.from("x", "utf8");
        child.result(request.id, {
          result: { handle: HANDLE, offset: 0, totalLength: 1, returnedBytes: 1,
            final: true, contentHash: "f".repeat(64) },
          metadata: { handle: HANDLE, offset: 0, totalLength: 1,
            final: true, contentHash: "f".repeat(64) },
          contentBase64: bytes.toString("base64"),
        });
      },
    });
    await assertRejectCode(runner.readContent(HANDLE, { count: 1 }),
      "trusted_runner_content_hash_mismatch");
  });
  await t.test("duplicate completion", async (t2) => {
    const { fx, runner } = makeRunner(t2, {
      onEnd(child) {
        child.completion(completionFor(fx));
        child.completion(completionFor(fx));
        queueMicrotask(() => child.exit(0));
      },
    });
    await assertRejectCode(runner.finish(), "trusted_runner_completion_duplicate");
  });
});

test("completion accepts only the closed optional after-observation receipt shape", async (t) => {
  await t.test("valid optional after observation", async (t2) => {
    const { fx, runner } = makeRunner(t2, {
      onEnd(child) {
        const completion = completionFor(fx);
        completion.terminalReceipt.afterObservationId =
          "shutdown_after_a5_0000000000000";
        child.completion(completion);
        queueMicrotask(() => child.exit(0));
      },
    });
    const finished = await runner.finish();
    assert.equal(finished.completion.terminalReceipt.afterObservationId,
      "shutdown_after_a5_0000000000000");
  });
  await t.test("malformed optional after observation", async (t2) => {
    const { fx, runner } = makeRunner(t2, {
      onEnd(child) {
        const completion = completionFor(fx);
        completion.terminalReceipt.afterObservationId = "short";
        child.completion(completion);
        queueMicrotask(() => child.exit(0));
      },
    });
    await assertRejectCode(runner.finish(), "trusted_runner_completion_receipt_invalid");
  });
  await t.test("unknown receipt expansion", async (t2) => {
    const { fx, runner } = makeRunner(t2, {
      onEnd(child) {
        const completion = completionFor(fx);
        completion.terminalReceipt.domainResult = {};
        child.completion(completion);
        queueMicrotask(() => child.exit(0));
      },
    });
    await assertRejectCode(runner.finish(), "trusted_runner_completion_receipt_invalid");
  });
});

test("authoritative RPC rejection is not transport uncertainty but still forbids safe abort", async (t) => {
  const { runner } = makeRunner(t, {
    onRequest(request, child) {
      child.rpcError(request.id, -32020, "write outcome unavailable");
    },
  });
  await assertRejectCode(runner.call("input.click", { target: "material" }, {
    writeAuthority: true,
  }), "trusted_runner_rpc_error");
  assert.strictEqual(runner.uncertainWrite, false);
  await assertRejectCode(runner.abortBeforeAuthority(),
    "trusted_runner_abort_after_authority_forbidden");
});

test("write-authority transport timeout remains uncertain", async (t) => {
  const { runner } = makeRunner(t, { onRequest() {} }, { requestTimeoutMs: 15 });
  await assertRejectCode(runner.call("input.click", { target: "material" }, {
    writeAuthority: true,
  }), "trusted_runner_request_timeout");
  assert.strictEqual(runner.uncertainWrite, true);
});

test("abortBeforeAuthority uses supported shutdown without kill", async (t) => {
  const { runner } = makeRunner(t, {});
  const result = await runner.abortBeforeAuthority();
  assert.strictEqual(result.abortedBeforeAuthority, true);
  assert.strictEqual(result.exitCode, 0);
  assert.strictEqual(runner.uncertainWrite, false);
});

test("rejects any candidate leaf other than exact resourcesRoot A5", (t) => {
  const fx = fixture(t);
  assert.throws(() => createTrustedRunner(Object.assign({}, fx.preparation, {
    candidateRoot: path.join(fx.resourcesRoot, "tmp", "runtime-candidates", "v2", "other"),
  }), { spawnImpl() { throw new Error("must not spawn"); } }), (error) => {
    assert.strictEqual(error.code, "trusted_runner_candidate_root_mismatch");
    return true;
  });
});
