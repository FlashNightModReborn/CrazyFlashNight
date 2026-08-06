#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const NodeModule = require("module");
const os = require("os");
const path = require("path");
const CloneGuard = require("./clone-save-guard");
const OfflineCloneRecovery = require("./offline-clone-recovery");
const BrowserChildResourceClosure = require("./browser-child-resource-closure");
const LauncherObservation = require("./launcher-observation");
const RuntimeModuleJournal = require("./runtime-module-journal");
const SourceFingerprint = require("./source-fingerprint");
const {
  assertOwnedRunDirectory,
  canonicalJson,
  canonicalRecordsDigest,
  sha256Bytes,
  stageOwnedCapture,
  sha256Text,
  verifyCanonicalRecords,
  verifyOwnedCapture,
} = require("./evidence-artifact");
const {
  assertExactControlSet,
  verifyCapabilityDecision,
  verifyControlExchange,
  verifyOneShotAuthorization,
} = require("./control-contract");
const {
  allocateLoopbackCdpPort,
  assertByteInvariant,
  assertFreshRestartIdentity,
  assertRuntimeCdpBinding,
  attestLoopbackCdpEndpoint,
  parseWindowsCommandLine,
  resolveCandidateIdentityBeforeMutation,
  resolveBeforeMutation,
  withWebViewDebugEnvironment,
} = require("./runtime-guard");

const REQUEST_SCHEMA = "workbench-live-e2e.test.control.v1";
const ACK_SCHEMA = "workbench-live-e2e.test.ack.v1";
const TRANSPORTS = ["preferred", "fallback"];
const RESULTS = ["completed", "unavailable", "failed"];

async function runSelfTests() {
  let passed = 0;
  async function test(_name, body) {
    await body();
    passed += 1;
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-live-e2e-lib-"));
  const ownedBaseRelative = "tmp/workbench-live-e2e";
  const runDir = path.join(root, ownedBaseRelative, "fixture-run");
  const capturesDir = path.join(runDir, "control", "captures");
  fs.mkdirSync(capturesDir, { recursive: true });
  fs.mkdirSync(path.join(root, "saves"), { recursive: true });
  const appData = path.join(root, "appdata");
  fs.mkdirSync(appData, { recursive: true });
  const source = path.join(root, "source.png");
  fs.writeFileSync(source, Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
    "base64"), { flag: "wx" });
  function writeSave(slot, value) {
    fs.writeFileSync(path.join(root, "saves", slot + ".json"), JSON.stringify(value), "utf8");
  }
  function ownedSolPath(slot) {
    const result = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects", "fixture",
      CloneGuard.solOwnershipSuffix(root, slot));
    fs.mkdirSync(path.dirname(result), { recursive: true });
    return result;
  }
  function assertRetainedCloneFailure(targetSlot, failureRun, expectedStatus) {
    const inspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
    const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
    assert.strictEqual(inspection.lockPresent, true);
    assert.strictEqual(inspection.recoveryRecordSha256, recovery.recordSha256);
    assert.strictEqual(recovery.status, expectedStatus);
    assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
      runDir: failureRun, ownedBaseRelative }),
    (error) => error && error.code === "clone_manual_recovery_required");
    assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
      runDir: failureRun, ownedBaseRelative, recoveryMode: true }),
    (error) => error && error.code === (expectedStatus === "prepared_pending_release"
      ? "clone_prepared_release_offline_recovery_required" : "clone_lock_unavailable"));
    return { inspection, recovery };
  }
  function sealedSessionEvidence(overrides) {
    const value = Object.assign({ schema: LauncherObservation.SESSION_SCHEMA,
      apiVersion: LauncherObservation.API_VERSION, openedAt: "2026-08-03T00:00:00.000Z",
      pid: 1, httpPort: 10001, socketPort: 10002,
      portsFile: "absent-ports.json", portsFileSha256: "1".repeat(64), portsFileBytes: 10,
      credentialFile: path.join(root, "absent-credential.json"),
      credentialFileSha256: "2".repeat(64), credentialFileBytes: 10,
      credentialTokenSha256: "3".repeat(64), credentialHeader: "X-CF7-Automation-Token",
      processStartUtcTicks: "638900000000000001", lifecycleId: "fixture-life",
      capabilities: ["legacy.console", "legacy.logs", "legacy.status", "legacy.task"] }, overrides || {});
    value.sessionEvidenceSha256 = sha256Text(canonicalJson(value));
    return value;
  }
  function normalizeFixtureLog(payload, requestedTailLimit, capturedAt, sessionEvidence) {
    return LauncherObservation.normalizeLogSnapshot(payload, requestedTailLimit, capturedAt,
      sessionEvidence || sealedSessionEvidence());
  }
  try {
    await test("admitted modules expose their exact frozen API markers", async () => {
      [require("./evidence-artifact"), require("./control-contract"),
        require("./runtime-guard"), require("./clone-save-guard"),
        require("./launcher-observation")]
        .forEach((moduleApi) => assert.strictEqual(moduleApi.API_VERSION, "FROZEN-v1"));
      assert.strictEqual(require("./runtime-module-journal").API_VERSION, "FROZEN-v2");
      assert.strictEqual(RuntimeModuleJournal.ADMISSION_STATUS, "ADMITTED");
      assert.strictEqual(SourceFingerprint.ADMISSION_STATUS, "DIAGNOSTIC_ONLY");
      const retired = require("./source-safety-gate");
      assert.strictEqual(retired.ADMISSION_STATUS, "RETIRED_DIAGNOSTIC_ONLY");
    });
    await test("runtime module journal captures a clean child bootstrap actual-load set", async () => {
      const projectRoot = path.resolve(__dirname, "..", "..", "..");
      const projectTmp = path.join(projectRoot, "tmp");
      fs.mkdirSync(projectTmp, { recursive: true });
      const fixtureRoot = fs.mkdtempSync(path.join(projectTmp, "module-journal-selftest-"));
      try {
        const bootstrapPath = path.join(fixtureRoot, "bootstrap.js");
        const domainPath = path.join(fixtureRoot, "domain.js");
        const dependencyPath = path.join(fixtureRoot, "dependency.js");
        const lowerCasePath = path.join(fixtureRoot, "inprocess.js");
        const mixedCasePath = path.join(fixtureRoot, "inProcessFactory.js");
        const externalPath = path.join(root, "journal-external.js");
        fs.writeFileSync(dependencyPath, "module.exports={value:7};\n", "utf8");
        fs.writeFileSync(lowerCasePath, "module.exports={value:0};\n", "utf8");
        fs.writeFileSync(mixedCasePath, "module.exports={value:0};\n", "utf8");
        fs.writeFileSync(externalPath, "module.exports={value:9};\n", "utf8");
        fs.writeFileSync(domainPath, [
          "'use strict';",
          "const direct=module['require']('./dependency');",
          "const alias=module.require.bind(module);",
          "const cached=alias('./dependency');",
          "const lower=alias('./inprocess');",
          "const mixed=alias('./inProcessFactory');",
          "const proc=console.log['con'+'structor']('return process')();",
          "const loader=module['require']('module');",
          "const external=loader['_load'](proc.env.CF7_TEST_JOURNAL_EXTERNAL,module,false);",
          "module.exports={value:direct.value+cached.value+lower.value+mixed.value+external.value};",
          "",
        ].join("\n"), "utf8");
        fs.writeFileSync(bootstrapPath, [
          "'use strict';",
          "const Journal=require(process.env.CF7_TEST_JOURNAL_MODULE);",
          "const mode=process.env.CF7_TEST_JOURNAL_MODE;",
          "const repairLoadedDescriptor=()=>{try{Object.defineProperty(module,'loaded',{value:mode==='bootstrap_loaded_accessor_swallow',writable:true,enumerable:true,configurable:true});}catch(_){}};",
          "try {",
          " if(mode==='preexisting_extra') require(process.env.CF7_TEST_JOURNAL_DOMAIN);",
          " const manifest=Journal.buildExplicitModuleManifest({",
          "  root:process.env.CF7_TEST_PROJECT_ROOT,",
          "  requiredPhases:['after_domain','after_async','terminal'],",
          "  builtins:JSON.parse(process.env.CF7_TEST_JOURNAL_BUILTINS),",
          "  entries:JSON.parse(process.env.CF7_TEST_JOURNAL_ENTRIES)",
          " });",
          " const outputManifest=JSON.parse(JSON.stringify(manifest));",
          " if(mode==='initial_loaded_true') module.loaded=true;",
          " const controller=Journal.installRuntimeModuleJournal({",
          "  root:process.env.CF7_TEST_PROJECT_ROOT,manifest",
          " });",
          " if(mode==='manifest_mutation') { manifest.entries[0].sha256='0'.repeat(64); manifest.entries.length=1; }",
          " if(mode==='cache_injected'||mode==='cache_non_enumerable') {",
          "  const Loader=require('module');",
          "  const target=process.env.CF7_TEST_JOURNAL_DEPENDENCY;",
          "  const fake=new Loader(target,module); fake.id=target; fake.filename=target; fake.loaded=true; fake.exports={value:999};",
          "  if(mode==='cache_non_enumerable') Object.defineProperty(require.cache,target,{value:fake,writable:true,configurable:true,enumerable:false});",
          "  else require.cache[target]=fake;",
          " }",
          " const value=require(process.env.CF7_TEST_JOURNAL_DOMAIN);",
          " if(mode==='cache_delete') delete require.cache[process.env.CF7_TEST_JOURNAL_DEPENDENCY];",
          " if(mode==='cache_identity_swap') {",
          "  const Loader=require('module'); const target=process.env.CF7_TEST_JOURNAL_DEPENDENCY;",
          "  const fake=new Loader(target,module); fake.id=target; fake.filename=target; fake.loaded=true; fake.exports={value:999}; require.cache[target]=fake;",
          " }",
          " if(mode==='cache_accessor') {",
          "  const target=process.env.CF7_TEST_JOURNAL_DEPENDENCY; const prior=require.cache[target];",
          "  Object.defineProperty(require.cache,target,{get(){return prior;},configurable:true,enumerable:true});",
          " }",
          " if(mode==='cache_symbol') require.cache[Symbol('fixture')]={};",
          " if(mode==='forged_parent') require('module')._load('./dependency',{filename:process.env.CF7_TEST_JOURNAL_DOMAIN},false);",
          " if(mode==='undeclared_builtin') require('fs');",
          " if(mode==='hook_replace') require('module')._load=function(){return {};};",
          " if(mode==='extension_replace') require('module')._extensions['.js']=function(){};",
          " if(mode==='resolver_find_path_replace') require('module')._findPath=function(){return process.env.CF7_TEST_JOURNAL_DEPENDENCY;};",
          " if(mode==='resolver_lookup_paths_replace') require('module')._resolveLookupPaths=function(){return [];};",
          " if(mode==='resolver_node_paths_replace') require('module')._nodeModulePaths=function(){return [];};",
          " if(mode==='resolver_path_cache_replace') require('module')._pathCache=Object.create(null);",
          " if(mode==='bootstrap_identity_swap') {",
          "  const fake=new module.constructor(__filename,null); fake.id='.'; fake.filename=__filename; fake.loaded=false; fake.exports={}; require.cache[__filename]=fake;",
          " }",
          " if(mode==='bootstrap_cache_accessor') {",
          "  const prior=require.cache[__filename]; Object.defineProperty(require.cache,__filename,{get(){return prior;},configurable:true,enumerable:true});",
          " }",
          " if(mode==='bootstrap_loaded_missing') delete module.loaded;",
          " if(mode==='bootstrap_loaded_nonwritable') Object.defineProperty(module,'loaded',{value:false,writable:false,enumerable:true,configurable:true});",
          " if(mode==='bootstrap_loaded_nonenumerable') Object.defineProperty(module,'loaded',{value:false,writable:true,enumerable:false,configurable:true});",
          " if(mode==='bootstrap_loaded_nonconfigurable') Object.defineProperty(module,'loaded',{value:false,writable:true,enumerable:true,configurable:false});",
          " controller.checkpoint('after_domain');",
          " if(mode==='bootstrap_loaded_accessor_swallow') Object.defineProperty(module,'loaded',{get(){return false;},set(_){},enumerable:true,configurable:true});",
          " const complete=()=>{try{",
          "  if((mode==='async_positive'||mode==='bootstrap_loaded_regress')&&module.loaded!==true) throw new Error('setImmediate did not observe loaded=true');",
          "  if(mode==='bootstrap_loaded_accessor_swallow'&&module.loaded!==false) throw new Error('accessor did not swallow Node loaded=true write');",
          "  controller.checkpoint('after_async');",
          "  if(mode==='bootstrap_loaded_regress') module.loaded=false;",
          "  controller.seal('terminal');",
          "  if(mode==='post_seal') require('fs');",
          "  const artifact=controller.reverifyAndRestore();",
          "  process.stdout.write(JSON.stringify({ok:true,value,manifest:outputManifest,artifact}));",
          " }catch(error){repairLoadedDescriptor();process.stdout.write(JSON.stringify({ok:false,code:error&&error.code,message:error&&error.message,stack:error&&error.stack}));}};",
          " if(mode==='async_positive'||mode==='bootstrap_loaded_regress'||mode==='bootstrap_loaded_accessor_swallow') setImmediate(complete); else complete();",
          "} catch(error) {",
          " repairLoadedDescriptor();",
          " process.stdout.write(JSON.stringify({ok:false,code:error&&error.code,message:error&&error.message,stack:error&&error.stack}));",
          "}",
          "",
        ].join("\n"), "utf8");
        const entries = [
          { filePath: bootstrapPath, role: "bootstrap", loadable: true, preexisting: true },
          { filePath: path.join(__dirname, "runtime-module-journal.js"), role: "journal",
            loadable: true, preexisting: true },
          { filePath: path.join(__dirname, "evidence-artifact.js"), role: "journal_helper",
            loadable: true, preexisting: true },
          { filePath: domainPath, role: "domain_module", loadable: true, preexisting: false },
          { filePath: dependencyPath, role: "domain_module", loadable: true, preexisting: false },
          { filePath: lowerCasePath, role: "domain_module", loadable: true, preexisting: false },
          { filePath: mixedCasePath, role: "domain_module", loadable: true, preexisting: false },
          { filePath: externalPath, role: "external_module", loadable: true, preexisting: false },
        ];
        function runChild(mode, childEntries, childBuiltins) {
          return childProcess.spawnSync(process.execPath, [bootstrapPath], {
            encoding: "utf8", windowsHide: true, timeout: 30000,
            env: Object.assign({}, process.env, {
              CF7_TEST_PROJECT_ROOT: projectRoot,
              CF7_TEST_JOURNAL_MODULE: path.join(__dirname, "runtime-module-journal.js"),
              CF7_TEST_JOURNAL_DOMAIN: domainPath,
              CF7_TEST_JOURNAL_DEPENDENCY: dependencyPath,
              CF7_TEST_JOURNAL_EXTERNAL: externalPath,
              CF7_TEST_JOURNAL_ENTRIES: JSON.stringify(childEntries || entries),
              CF7_TEST_JOURNAL_BUILTINS: JSON.stringify(childBuiltins
                || [{ name: "module", risk: "high_risk_explicit" }]),
              CF7_TEST_JOURNAL_MODE: mode || "positive",
            }),
          });
        }
        const child = runChild("positive");
        assert.strictEqual(child.status, 0, String(child.stderr || ""));
        const result = JSON.parse(String(child.stdout || "{}"));
        assert.strictEqual(result.ok, true, result.code + ": " + result.message + "\n" + result.stack);
        assert.strictEqual(result.value.value, 23);
        RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: result.manifest, artifact: result.artifact });
        assert.ok(result.artifact.events.some((entry) => entry.request === "./dependency"));
        assert.ok(result.artifact.events.some((entry) => entry.kind === "builtin"
          && entry.resolved === "module"));
        assert.ok(result.artifact.events.some((entry) => entry.kind === "file"
          && entry.resolved.startsWith("external:")));
        assert.strictEqual(result.artifact.bootstrapLoadedAtInstall, false);
        assert.strictEqual(result.artifact.bootstrapLoadedAtRestore, false);
        assert.deepStrictEqual(result.artifact.checkpoints.map((entry) => entry.bootstrapLoaded),
          [false, false]);
        assert.strictEqual(result.artifact.seal.bootstrapLoaded, false);
        const asyncChild = runChild("async_positive");
        assert.strictEqual(asyncChild.status, 0, String(asyncChild.stderr || ""));
        const asyncResult = JSON.parse(String(asyncChild.stdout || "{}"));
        assert.strictEqual(asyncResult.ok, true,
          asyncResult.code + ": " + asyncResult.message + "\n" + asyncResult.stack);
        RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: asyncResult.manifest, artifact: asyncResult.artifact });
        assert.strictEqual(asyncResult.artifact.bootstrapLoadedAtInstall, false);
        assert.deepStrictEqual(asyncResult.artifact.checkpoints.map((entry) => entry.bootstrapLoaded),
          [false, true]);
        assert.strictEqual(asyncResult.artifact.seal.bootstrapLoaded, true);
        assert.strictEqual(asyncResult.artifact.bootstrapLoadedAtRestore, true);
        const clockRollback = JSON.parse(JSON.stringify(asyncResult.artifact));
        clockRollback.installedAt = "2030-01-01T00:00:05.000Z";
        clockRollback.checkpoints[0].capturedAt = "2030-01-01T00:00:04.000Z";
        clockRollback.checkpoints[1].capturedAt = "2030-01-01T00:00:03.000Z";
        clockRollback.seal.capturedAt = "2030-01-01T00:00:02.000Z";
        clockRollback.sealedAt = clockRollback.seal.capturedAt;
        clockRollback.restoredAt = "2030-01-01T00:00:01.000Z";
        clockRollback.checkpoints.concat([clockRollback.seal]).forEach((checkpoint) => {
          delete checkpoint.checkpointSha256;
          checkpoint.checkpointSha256 = sha256Text(canonicalJson(checkpoint));
        });
        delete clockRollback.evidenceSha256;
        clockRollback.evidenceSha256 = sha256Text(canonicalJson(clockRollback));
        assert.doesNotThrow(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
          root: projectRoot, manifest: asyncResult.manifest, artifact: clockRollback,
        }));
        const forgedSealedAt = JSON.parse(JSON.stringify(asyncResult.artifact));
        forgedSealedAt.sealedAt = "2031-01-01T00:00:00.000Z";
        delete forgedSealedAt.evidenceSha256;
        forgedSealedAt.evidenceSha256 = sha256Text(canonicalJson(forgedSealedAt));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
          root: projectRoot, manifest: asyncResult.manifest, artifact: forgedSealedAt,
        }), (error) => error && error.code === "runtime_module_timestamp_binding_invalid");
        const forgedLoadedRegression = JSON.parse(JSON.stringify(asyncResult.artifact));
        forgedLoadedRegression.seal.bootstrapLoaded = false;
        delete forgedLoadedRegression.seal.checkpointSha256;
        forgedLoadedRegression.seal.checkpointSha256 = sha256Text(
          canonicalJson(forgedLoadedRegression.seal));
        forgedLoadedRegression.bootstrapLoadedAtRestore = false;
        delete forgedLoadedRegression.evidenceSha256;
        forgedLoadedRegression.evidenceSha256 = sha256Text(canonicalJson(forgedLoadedRegression));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: asyncResult.manifest, artifact: forgedLoadedRegression }),
        (error) => error && error.code === "runtime_module_bootstrap_loaded_semantics_invalid");
        const forgedLoadedType = JSON.parse(JSON.stringify(asyncResult.artifact));
        forgedLoadedType.checkpoints[0].bootstrapLoaded = "false";
        delete forgedLoadedType.checkpoints[0].checkpointSha256;
        forgedLoadedType.checkpoints[0].checkpointSha256 = sha256Text(
          canonicalJson(forgedLoadedType.checkpoints[0]));
        delete forgedLoadedType.evidenceSha256;
        forgedLoadedType.evidenceSha256 = sha256Text(canonicalJson(forgedLoadedType));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: asyncResult.manifest, artifact: forgedLoadedType }),
        (error) => error && error.code === "runtime_module_checkpoint_invalid");
        const forgedResolverDigest = JSON.parse(JSON.stringify(asyncResult.artifact));
        forgedResolverDigest.checkpoints[0].resolverMachinerySha256 = "0".repeat(64);
        delete forgedResolverDigest.checkpoints[0].checkpointSha256;
        forgedResolverDigest.checkpoints[0].checkpointSha256 = sha256Text(
          canonicalJson(forgedResolverDigest.checkpoints[0]));
        delete forgedResolverDigest.evidenceSha256;
        forgedResolverDigest.evidenceSha256 = sha256Text(canonicalJson(forgedResolverDigest));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: asyncResult.manifest, artifact: forgedResolverDigest }),
        (error) => error && error.code === "runtime_module_checkpoint_invalid");
        const forgedFileRequest = JSON.parse(JSON.stringify(result.artifact));
        const fileRequestEvent = forgedFileRequest.events.find((entry) =>
          entry.kind === "file" && entry.request === "./dependency");
        assert.ok(fileRequestEvent);
        fileRequestEvent.request = "./bootstrap";
        delete forgedFileRequest.evidenceSha256;
        forgedFileRequest.evidenceSha256 = sha256Text(canonicalJson(forgedFileRequest));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: result.manifest, artifact: forgedFileRequest }),
        (error) => error && error.code === "runtime_module_event_resolution_invalid");
        ["_resolveFilename", "_findPath", "_resolveLookupPaths", "_nodeModulePaths"]
          .forEach((name) => {
            const originalDescriptor = Object.getOwnPropertyDescriptor(NodeModule, name);
            Object.defineProperty(NodeModule, name, Object.assign({}, originalDescriptor, {
              value: function forgedResolverHelper() { return dependencyPath; },
            }));
            try {
              assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
                root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
              }), (error) => error
                && error.code === "runtime_module_resolver_machinery_invalid", name);
            } finally {
              Object.defineProperty(NodeModule, name, originalDescriptor);
            }
          });
        const originalPathDirnameDescriptor = Object.getOwnPropertyDescriptor(path, "dirname");
        Object.defineProperty(path, "dirname", Object.assign({}, originalPathDirnameDescriptor, {
          value: function forgedDirname() { return projectRoot; },
        }));
        try {
          assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
            root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
          }), (error) => error
            && error.code === "runtime_module_resolver_machinery_invalid");
        } finally {
          Object.defineProperty(path, "dirname", originalPathDirnameDescriptor);
        }
        const originalPathCacheDescriptor = Object.getOwnPropertyDescriptor(
          NodeModule, "_pathCache");
        Object.defineProperty(NodeModule, "_pathCache", Object.assign({},
          originalPathCacheDescriptor, { value: Object.create(null) }));
        try {
          assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
            root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
          }), (error) => error
            && error.code === "runtime_module_resolver_machinery_invalid");
        } finally {
          Object.defineProperty(NodeModule, "_pathCache", originalPathCacheDescriptor);
        }
        const poisonKey = "./bootstrap\0" + path.dirname(domainPath);
        const priorPoisonDescriptor = Object.getOwnPropertyDescriptor(
          NodeModule._pathCache, poisonKey);
        NodeModule._pathCache[poisonKey] = dependencyPath;
        try {
          const poisonedParent = new NodeModule(domainPath);
          poisonedParent.filename = domainPath;
          poisonedParent.paths = NodeModule._nodeModulePaths(path.dirname(domainPath));
          assert.strictEqual(NodeModule._resolveFilename(
            "./bootstrap", poisonedParent, false), dependencyPath);
          assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
            root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
          }), (error) => error && error.code === "runtime_module_event_resolution_invalid");
        } finally {
          if (priorPoisonDescriptor) {
            Object.defineProperty(NodeModule._pathCache, poisonKey, priorPoisonDescriptor);
          } else {
            delete NodeModule._pathCache[poisonKey];
          }
        }
        const originalGlobalPathsDescriptor = Object.getOwnPropertyDescriptor(
          NodeModule, "globalPaths");
        Object.defineProperty(NodeModule, "globalPaths", Object.assign({},
          originalGlobalPathsDescriptor, { value: originalGlobalPathsDescriptor.value.slice() }));
        try {
          assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
            root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
          }), (error) => error
            && error.code === "runtime_module_resolver_machinery_invalid");
        } finally {
          Object.defineProperty(NodeModule, "globalPaths", originalGlobalPathsDescriptor);
        }
        const originalJsExtensionDescriptor = Object.getOwnPropertyDescriptor(
          NodeModule._extensions, ".js");
        Object.defineProperty(NodeModule._extensions, ".js", Object.assign({},
          originalJsExtensionDescriptor, { value: function forgedJsExtension() {} }));
        try {
          assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({
            root: projectRoot, manifest: result.manifest, artifact: forgedFileRequest,
          }), (error) => error
            && error.code === "runtime_module_resolver_extensions_invalid");
        } finally {
          Object.defineProperty(NodeModule._extensions, ".js", originalJsExtensionDescriptor);
        }
        const forgedBuiltin = JSON.parse(JSON.stringify(result.artifact));
        forgedBuiltin.events.find((entry) => entry.kind === "builtin").resolved = "fs";
        delete forgedBuiltin.evidenceSha256;
        forgedBuiltin.evidenceSha256 = sha256Text(canonicalJson(forgedBuiltin));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: result.manifest, artifact: forgedBuiltin }),
        (error) => error && error.code === "runtime_module_builtin_event_invalid");
        const forgedCheckpoint = JSON.parse(JSON.stringify(result.artifact));
        forgedCheckpoint.checkpoints[0].eventCount = 0;
        delete forgedCheckpoint.checkpoints[0].checkpointSha256;
        forgedCheckpoint.checkpoints[0].checkpointSha256 = sha256Text(
          canonicalJson(forgedCheckpoint.checkpoints[0]));
        delete forgedCheckpoint.evidenceSha256;
        forgedCheckpoint.evidenceSha256 = sha256Text(canonicalJson(forgedCheckpoint));
        assert.throws(() => RuntimeModuleJournal.verifyRuntimeModuleJournal({ root: projectRoot,
          manifest: result.manifest, artifact: forgedCheckpoint }),
        (error) => error && error.code === "runtime_module_checkpoint_semantics_invalid");
        const expectedFailures = new Map([
          ["cache_injected", "runtime_module_cache_injected"],
          ["cache_non_enumerable", "runtime_module_cache_entry_invalid"],
          ["cache_delete", "runtime_module_manifest_coverage_mismatch"],
          ["cache_identity_swap", "runtime_module_cache_identity_changed"],
          ["cache_accessor", "runtime_module_cache_entry_invalid"],
          ["cache_symbol", "runtime_module_cache_symbol_forbidden"],
          ["forged_parent", "runtime_module_parent_identity_invalid"],
          ["undeclared_builtin", "runtime_module_builtin_not_declared"],
          ["hook_replace", "runtime_module_hook_replaced"],
          ["extension_replace", "runtime_module_extensions_replaced"],
          ["resolver_find_path_replace", "runtime_module_resolver_machinery_invalid"],
          ["resolver_lookup_paths_replace", "runtime_module_resolver_machinery_invalid"],
          ["resolver_node_paths_replace", "runtime_module_resolver_machinery_invalid"],
          ["resolver_path_cache_replace", "runtime_module_resolver_machinery_invalid"],
          ["post_seal", "runtime_module_load_after_seal"],
          ["preexisting_extra", "runtime_module_preexisting_cache_mismatch"],
          ["initial_loaded_true", "runtime_module_bootstrap_initial_loaded_invalid"],
          ["bootstrap_loaded_regress", "runtime_module_bootstrap_loaded_regressed"],
          ["bootstrap_identity_swap", "runtime_module_bootstrap_cache_invalid"],
          ["bootstrap_cache_accessor", "runtime_module_cache_entry_invalid"],
          ["bootstrap_loaded_accessor_swallow",
            "runtime_module_bootstrap_loaded_descriptor_invalid"],
          ["bootstrap_loaded_missing", "runtime_module_bootstrap_loaded_descriptor_invalid"],
          ["bootstrap_loaded_nonwritable", "runtime_module_bootstrap_loaded_descriptor_invalid"],
          ["bootstrap_loaded_nonenumerable", "runtime_module_bootstrap_loaded_descriptor_invalid"],
          ["bootstrap_loaded_nonconfigurable",
            "runtime_module_bootstrap_loaded_descriptor_invalid"],
        ]);
        expectedFailures.forEach((expectedCode, mode) => {
          const negative = runChild(mode);
          assert.strictEqual(negative.status, 0, mode + ": " + String(negative.stderr || ""));
          const negativeResult = JSON.parse(String(negative.stdout || "{}"));
          assert.strictEqual(negativeResult.ok, false, mode + " unexpectedly passed");
          assert.strictEqual(negativeResult.code, expectedCode, mode + ": " + negativeResult.message);
        });
        const undeclared = runChild("positive", entries.filter((entry) =>
          ![dependencyPath, externalPath].includes(entry.filePath)));
        const undeclaredResult = JSON.parse(String(undeclared.stdout || "{}"));
        assert.strictEqual(undeclaredResult.ok, false);
        assert.strictEqual(undeclaredResult.code, "runtime_module_external_not_declared");
        const unusedBuiltin = runChild("positive", entries, [
          { name: "module", risk: "high_risk_explicit" }, { name: "fs", risk: "standard" },
        ]);
        const unusedBuiltinResult = JSON.parse(String(unusedBuiltin.stdout || "{}"));
        assert.strictEqual(unusedBuiltinResult.ok, false);
        assert.strictEqual(unusedBuiltinResult.code, "runtime_module_builtin_coverage_mismatch");
        const mutation = runChild("manifest_mutation");
        const mutationResult = JSON.parse(String(mutation.stdout || "{}"));
        assert.strictEqual(mutationResult.ok, true,
          mutationResult.code + ": " + mutationResult.message);
        assert.throws(() => RuntimeModuleJournal.buildExplicitModuleManifest({ root: projectRoot,
           requiredPhases: ["after_domain", "after_async", "terminal"],
          builtins: [{ name: "module", risk: "standard" }], entries }),
        (error) => error && error.code === "module_manifest_builtin_invalid");
        assert.throws(() => RuntimeModuleJournal.buildExplicitModuleManifest({ root: projectRoot,
           requiredPhases: ["after_domain", "after_async", "terminal"],
          builtins: [{ name: "module", risk: "high_risk_explicit" }],
          entries: entries.map((entry) => entry.filePath === domainPath
            ? Object.assign({}, entry, { preexisting: true }) : entry) }),
        (error) => error && error.code === "module_manifest_entries_invalid");
        assert.throws(() => RuntimeModuleJournal.buildExplicitModuleManifest({ root: projectRoot,
          requiredPhases: ["after_domain", "terminal"],
          builtins: [{ name: "module", risk: "high_risk_explicit" }],
          entries: entries.map((entry) => entry.filePath === externalPath
            ? Object.assign({}, entry, { role: "domain_module" }) : entry) }),
        (error) => error && error.code === "module_manifest_scope_mismatch");
        const junctionTarget = path.join(root, "journal-junction-target");
        const junctionPath = path.join(fixtureRoot, "junction");
        fs.mkdirSync(junctionTarget, { recursive: true });
        fs.writeFileSync(path.join(junctionTarget, "linked.js"), "module.exports=1;\n", "utf8");
        fs.symlinkSync(junctionTarget, junctionPath, "junction");
        assert.throws(() => RuntimeModuleJournal.buildExplicitModuleManifest({ root: projectRoot,
          requiredPhases: ["after_domain", "terminal"],
          builtins: [{ name: "module", risk: "high_risk_explicit" }],
          entries: entries.concat([{ filePath: path.join(junctionPath, "linked.js"),
            role: "domain_module", loadable: true, preexisting: false }]) }),
        (error) => error && error.code === "exact_file_invalid");
      } finally {
        fs.rmSync(fixtureRoot, { recursive: true, force: true });
      }
    });
    const capture = stageOwnedCapture({ root, runDir, ownedBaseRelative, capturesDir,
      sourcePath: source, artifactId: "capture-fixture" });
    await test("capture stages and rehashes", async () => {
      const verified = verifyOwnedCapture({ root, runDir, ownedBaseRelative, capture });
      assert.strictEqual(verified.sha256, capture.sha256);
      assert.strictEqual(verified.mediaType, "image/png");
    });
    await test("capture path escape fails closed", async () => {
      assert.throws(() => verifyOwnedCapture({ root, runDir, ownedBaseRelative,
        capture: Object.assign({}, capture, { relativePath: "../../source.png" }) }),
      (error) => error && error.code === "capture_path_escape");
    });
    await test("owned run base rejects parent absolute drive-relative and sibling escapes", async () => {
      const siblingBase = path.join(root, "tmp", "workbench-live-e2e-sibling");
      const siblingRun = path.join(siblingBase, "run");
      fs.mkdirSync(siblingRun, { recursive: true });
      ["..", ".", path.resolve(root, "tmp"), "C:drive-relative"].forEach((ownedBase) => {
        assert.throws(() => assertOwnedRunDirectory(root, runDir, ownedBase, "owned_base_test"),
          (error) => error && error.code === "owned_base_relative_invalid");
      });
      assert.throws(() => assertOwnedRunDirectory(root, siblingRun,
        ownedBaseRelative, "owned_base_test"),
      (error) => error && error.code === "owned_run_directory_invalid");
    });

    const records = [{ lineNumber: 11, body: "one" }, { lineNumber: 12, body: "two" }];
    const recordsDigest = canonicalRecordsDigest(records);
    await test("canonical record digest verifies", async () => {
      assert.strictEqual(verifyCanonicalRecords({ records, digest: recordsDigest,
        watermarkTotal: 10, finalTotal: 12 }), records);
    });
    await test("record tamper fails closed", async () => {
      assert.throws(() => verifyCanonicalRecords({
        records: [records[0], { lineNumber: 12, body: "tampered" }],
        digest: recordsDigest, watermarkTotal: 10, finalTotal: 12,
      }), (error) => error && error.code === "records_digest_mismatch");
    });

    const request = {
      schema: REQUEST_SCHEMA,
      requestId: "fixture-request",
      step: "capture_step",
      issuedAt: "2026-08-03T00:00:00.000Z",
      expiresAt: "2026-08-03T00:10:00.000Z",
      allowedTransports: ["fallback"],
      requiresCommitAuthorization: false,
      requiresCaptureSha256: true,
    };
    const ack = {
      schema: ACK_SCHEMA,
      requestId: request.requestId,
      transport: "fallback",
      result: "completed",
      completedAt: "2026-08-03T00:05:00.000Z",
      captureSha256: capture.sha256,
      capture,
    };
    const controlOptions = { root, runDir, ownedBaseRelative, requestSchema: REQUEST_SCHEMA,
      ackSchema: ACK_SCHEMA, allowedTransports: TRANSPORTS, allowedResults: RESULTS,
      maximumTtlMs: 3600000 };
    await test("control exchange verifies TTL and capture bytes", async () => {
      const result = verifyControlExchange(Object.assign({}, controlOptions, { request, ack }));
      assert.strictEqual(result.capture.sha256, capture.sha256);
    });
    await test("late acknowledgement fails closed", async () => {
      const late = Object.assign({}, ack, { completedAt: "2026-08-03T00:10:00.001Z" });
      assert.throws(() => verifyControlExchange(Object.assign({}, controlOptions,
        { request, ack: late })), (error) => error && error.code === "control_ack_time_invalid");
    });
    await test("exact control set rejects tail requests", async () => {
      const extra = Object.assign({}, request, { requestId: "fixture-extra", step: "extra" });
      assert.throws(() => assertExactControlSet(Object.assign({}, controlOptions, {
        requests: [request, extra], acks: [ack], requiredSteps: ["capture_step"],
      })), (error) => error && error.code === "control_set_count_invalid");
    });
    await test("capability fallback needs trusted evidence", async () => {
      const artifact = { schema: "fixture.start.v1", mode: "fallback-only" };
      const artifactSha256 = sha256Text(canonicalJson(artifact));
      assert.deepStrictEqual(verifyCapabilityDecision({
        capability: { available: false, source: "start_contract", artifact, artifactSha256 },
        trustedSources: ["start_contract"], selectedTransport: "fallback",
        preferredTransport: "preferred", fallbackTransport: "fallback", fallbackAllowed: true,
      }), { available: false, source: "start_contract", artifactSha256,
        selectedTransport: "fallback" });
      assert.throws(() => verifyCapabilityDecision({
        capability: { available: false, source: "operator_ack", artifact, artifactSha256 },
        trustedSources: ["start_contract"], selectedTransport: "fallback",
        preferredTransport: "preferred", fallbackTransport: "fallback", fallbackAllowed: true,
      }), (error) => error && error.code === "capability_evidence_untrusted");
    });
    await test("one-shot authorization binds one request and ack", async () => {
      const decision = { schema: "fixture.authorization.v1", decisionId: "decision-fixture",
        source: "cli", issuedAt: request.issuedAt, oneShot: true, scope: { mutation: "fixture" } };
      const decisionSha256 = sha256Text(canonicalJson(decision));
      const authorizedRequest = Object.assign({}, request, {
        requestId: "authorized-request",
        step: "commit",
        requiresCommitAuthorization: true,
        authorizationRef: { decisionId: decision.decisionId, decisionSha256 },
      });
      const authorizedAck = Object.assign({}, ack, {
        requestId: authorizedRequest.requestId,
        authorizationDecisionId: decision.decisionId,
      });
      verifyControlExchange(Object.assign({}, controlOptions,
        { request: authorizedRequest, ack: authorizedAck }));
      assert.strictEqual(verifyOneShotAuthorization({
        decision, decisionSha256, decisionSchema: decision.schema, trustedSources: ["cli"],
        requests: [authorizedRequest], acks: [authorizedAck], expectedStep: "commit",
      }).requestId, authorizedRequest.requestId);
    });

    await test("candidate identity resolves before mutation", async () => {
      const order = [];
      const result = resolveBeforeMutation({
        assertNoRuntime() { order.push("exclusive"); },
        resolveIdentity() { order.push("identity"); return { runtimeMode: "isolated_candidate" }; },
        prepareMutation() { order.push("mutation"); return { slot: "fixture" }; },
      });
      assert.deepStrictEqual(order, ["exclusive", "identity", "mutation"]);
      assert.strictEqual(result.preparation.slot, "fixture");
    });
    await test("isolated candidate identity is validated before clone mutation", async () => {
      const candidateRoot = path.join(root, "tmp", "runtime-candidates", "v2", "candidate-fixture");
      fs.mkdirSync(path.join(candidateRoot, "runtime"), { recursive: true });
      const coreExe = Buffer.from("fixture-core-exe");
      const coreDll = Buffer.from("fixture-core-dll");
      const buildIdentity = "2".repeat(64);
      const payloadClosure = "3".repeat(64);
      fs.writeFileSync(path.join(candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
        coreExe, { flag: "wx" });
      fs.writeFileSync(path.join(candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.dll"),
        coreDll, { flag: "wx" });
      fs.writeFileSync(path.join(candidateRoot, "runtime", "cf7-runtime-manifest.tsv"), [
        "cf7-runtime-manifest-v2",
        "buildIdentityHash\t" + buildIdentity,
        "payloadClosureHash\t" + payloadClosure,
        "file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.dll\t" + coreDll.length
          + "\t" + sha256Bytes(coreDll).toUpperCase(),
        "",
      ].join("\n"), { encoding: "utf8", flag: "wx" });
      fs.writeFileSync(path.join(candidateRoot, "runtime-build-metadata.v2.json"), JSON.stringify({
        schema: "cf7-runtime-candidate-metadata.v2",
        buildIdentityHash: buildIdentity,
        payloadClosureHash: payloadClosure,
      }), { encoding: "utf8", flag: "wx" });
      const order = [];
      const result = resolveCandidateIdentityBeforeMutation({ root, candidateRoot,
        assertNoRuntime() { order.push("exclusive"); },
        prepareClone(resolved, artifact) {
          order.push("clone");
          assert.ok(Object.isFrozen(resolved));
          assert.strictEqual(artifact.identitySha256, sha256Text(canonicalJson(resolved)));
          return { slot: "cf7_agent_fixture" };
        } });
      assert.deepStrictEqual(order, ["exclusive", "clone"]);
      assert.strictEqual(result.identity.runtimeMode, "isolated_candidate");
      assert.strictEqual(result.identity.coreSha256, sha256Bytes(coreDll).toUpperCase());
    });

    await test("offline recovery CLI rejects ambiguous or under-authorized arguments", async () => {
      assert.throws(() => OfflineCloneRecovery.parseArguments([
        "inspect", "--slot", "cf7_agent_cli_parse", "--unknown", "x",
      ]), (error) => error && error.code === "offline_recovery_arguments_invalid");
      assert.throws(() => OfflineCloneRecovery.parseArguments([
        "clear-no-recovery-lock", "--slot", "cf7_agent_cli_parse",
        "--expected-lock-sha256", "a".repeat(64),
      ]), (error) => error && error.code === "offline_recovery_arguments_invalid");
      assert.throws(() => OfflineCloneRecovery.parseArguments([
        "restore-record-only", "--slot", "cf7_agent_cli_parse",
        "--expected-lock-sha256", "a".repeat(64),
        "--expected-recovery-sha256", "b".repeat(64),
        "--expected-recovery-status", "prepared_pending_release",
        "--allow-offline-recovery",
      ]), (error) => error && error.code === "offline_recovery_arguments_invalid");
      assert.throws(() => OfflineCloneRecovery.parseArguments([
        "inspect", "--slot", "cf7_agent_cli_parse", "--slot", "cf7_agent_duplicate",
      ]), (error) => error && error.code === "offline_recovery_arguments_invalid");
      const parsed = OfflineCloneRecovery.parseArguments([
        "restore-from-recovery", "--expected-recovery-status", "manual_recovery_required",
        "--expected-recovery-sha256", "B".repeat(64),
        "--slot", "cf7_agent_cli_parse", "--allow-offline-recovery",
        "--expected-lock-sha256", "A".repeat(64),
      ]);
      assert.strictEqual(parsed.expectedLockSha256, "a".repeat(64));
      assert.strictEqual(parsed.expectedRecoveryRecordSha256, "b".repeat(64));
    });

    await test("offline pre-mutation lock clearance is owner, digest, runtime, and receipt bound", async () => {
      const activeSlot = "cf7_agent_offline_active_owner";
      const activeRun = path.join(root, ownedBaseRelative, "offline-active-owner");
      fs.mkdirSync(activeRun, { recursive: true });
      const activeLock = CloneGuard.acquireCloneLock({ root, slot: activeSlot,
        runDir: activeRun, ownedBaseRelative });
      assert.throws(() => CloneGuard.clearAbandonedNoRecoveryCloneLock({ root,
        slot: activeSlot, expectedLockSha256: activeLock.recordSha256,
        assertNoRuntime() { return false; } }),
      (error) => error && error.code === "clone_offline_runtime_not_excluded");
      assert.throws(() => CloneGuard.clearAbandonedNoRecoveryCloneLock({ root,
        slot: activeSlot, expectedLockSha256: activeLock.recordSha256,
        assertNoRuntime() { return true; } }),
      (error) => error && error.code === "clone_offline_lock_owner_not_absent");
      CloneGuard.releaseCloneLock(activeLock);

      const targetSlot = "cf7_agent_offline_empty_orphan";
      const orphanRun = path.join(root, ownedBaseRelative, "offline-empty-orphan");
      fs.mkdirSync(orphanRun, { recursive: true });
      const childSource = [
        "'use strict';",
        "const guard=require(process.env.CF7_TEST_CLONE_GUARD_MODULE);",
        "guard.acquireCloneLock({root:process.env.CF7_TEST_CLONE_ROOT,",
        " slot:process.env.CF7_TEST_CLONE_TARGET_SLOT,",
        " runDir:process.env.CF7_TEST_CLONE_RUN_DIR,",
        " ownedBaseRelative:process.env.CF7_TEST_CLONE_OWNED_BASE});",
        "process.exit(77);",
      ].join("\n");
      const orphan = childProcess.spawnSync(process.execPath, ["-e", childSource], {
        encoding: "utf8", windowsHide: true, timeout: 30000,
        env: Object.assign({}, process.env, {
          CF7_TEST_CLONE_GUARD_MODULE: path.join(__dirname, "clone-save-guard.js"),
          CF7_TEST_CLONE_ROOT: root,
          CF7_TEST_CLONE_RUN_DIR: orphanRun,
          CF7_TEST_CLONE_OWNED_BASE: ownedBaseRelative,
          CF7_TEST_CLONE_TARGET_SLOT: targetSlot,
        }),
      });
      assert.strictEqual(orphan.status, 77, String(orphan.stderr || ""));
      const inspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      assert.strictEqual(inspection.ownerState, "owner_absent");
      assert.strictEqual(inspection.recoveryPresent, false);
      assert.throws(() => CloneGuard.clearAbandonedNoRecoveryCloneLock({ root,
        slot: targetSlot, expectedLockSha256: "0".repeat(64),
        assertNoRuntime() { return true; } }),
      (error) => error && error.code === "clone_offline_lock_changed");
      const output = OfflineCloneRecovery.executeOfflineRecovery({ root, appData,
        argv: ["clear-no-recovery-lock", "--slot", targetSlot,
          "--expected-lock-sha256", inspection.recordSha256,
          "--allow-offline-recovery"],
        dependencies: {
          queryLauncherCoreProcesses() { return []; },
          assertExclusiveLauncherProcess(processes, authenticatedPid) {
            assert.deepStrictEqual(processes, []);
            assert.strictEqual(authenticatedPid, null);
            return true;
          },
        } });
      assert.strictEqual(output.ok, true);
      assert.strictEqual(output.result.lockFileAbsent, true);
      const receiptPath = path.join(root, output.receipt.relativePath.replace(/\//g, path.sep));
      const receiptBytes = fs.readFileSync(receiptPath);
      assert.strictEqual(sha256Bytes(receiptBytes), output.receipt.sha256);
      assert.strictEqual(CloneGuard.inspectCloneLock({ root, slot: targetSlot }).lockPresent, false);
    });

    await test("existing target JSON and SOL are backed up and replaced under one lock", async () => {
      const seedSlot = "fixture_seed";
      const targetSlot = "cf7_agent_clone_existing";
      writeSave(seedSlot, { version: 1, lastSaved: "seed", payload: { value: 7 } });
      writeSave(targetSlot, { version: 1, lastSaved: "old", payload: { value: 1 } });
      fs.writeFileSync(ownedSolPath(targetSlot), Buffer.from("old-sol"), { flag: "wx" });
      const beforeSeed = CloneGuard.captureSlotArtifactSet({ root, slot: seedSlot, appData });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot, runDir,
        ownedBaseRelative });
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot, runDir,
        ownedBaseRelative }), (error) => error && error.code === "clone_lock_unavailable");
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData, runDir,
        ownedBaseRelative, seedSlot, targetSlot, lock, transformId: "fixture-transform.v1",
        validateSeed(value) { return value && value.payload && value.payload.value === 7; },
        transformJson(value) { value.lastSaved = "clone"; return value; },
        validateTarget(value) { return value.lastSaved === "clone"; } });
      assert.strictEqual(preparation.targetBefore.artifacts.length, 2);
      assert.strictEqual(preparation.backups.length, 2);
      assert.strictEqual(CloneGuard.findOwnedSolFiles({ root, slot: targetSlot, appData }).length, 0);
      assert.strictEqual(JSON.parse(fs.readFileSync(CloneGuard.saveJsonPath(root, targetSlot), "utf8"))
        .lastSaved, "clone");
      CloneGuard.assertArtifactSetInvariant(beforeSeed,
        CloneGuard.captureSlotArtifactSet({ root, slot: seedSlot, appData }));
      const release = CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
      assert.strictEqual(release.lockRelease.lockFileAbsent, true);
      assert.strictEqual(release.recoveryClear.recoveryFileAbsent, true);
    });

    await test("seed drift at clone release retains the lock and durable recovery", async () => {
      const seedSlot = "fixture_release_seed_drift";
      const targetSlot = "cf7_agent_release_seed_drift";
      const failureRun = path.join(root, ownedBaseRelative, "release-seed-drift");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 11 } });
      writeSave(targetSlot, { version: 1, payload: { value: 1 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      writeSave(seedSlot, { version: 1, payload: { value: 12 } });
      assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
        (error) => error && error.code === "clone_release_manual_recovery_required");
      assertRetainedCloneFailure(targetSlot, failureRun, "manual_recovery_required");
    });

    await test("missing target at clone release retains the lock and durable recovery", async () => {
      const seedSlot = "fixture_release_target_missing";
      const targetSlot = "cf7_agent_release_target_missing";
      const failureRun = path.join(root, ownedBaseRelative, "release-target-missing");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 21 } });
      writeSave(targetSlot, { version: 1, payload: { value: 2 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      fs.unlinkSync(CloneGuard.saveJsonPath(root, targetSlot));
      assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
        (error) => error && error.code === "clone_release_manual_recovery_required");
      assertRetainedCloneFailure(targetSlot, failureRun, "manual_recovery_required");
    });

    await test("backup drift at clone release retains the lock and durable recovery", async () => {
      const seedSlot = "fixture_release_backup_drift";
      const targetSlot = "cf7_agent_release_backup_drift";
      const failureRun = path.join(root, ownedBaseRelative, "release-backup-drift");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 31 } });
      writeSave(targetSlot, { version: 1, payload: { value: 3 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      const backupPath = path.resolve(failureRun,
        preparation.backups[0].backupRelativePath.replace(/\//g, path.sep));
      fs.writeFileSync(backupPath, Buffer.from("tampered-backup"));
      assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
        (error) => error && error.code === "clone_release_manual_recovery_required");
      assertRetainedCloneFailure(targetSlot, failureRun, "manual_recovery_required");
    });

    await test("recovery transition write failure retains prepared record and lock", async () => {
      const seedSlot = "fixture_release_recovery_write";
      const targetSlot = "cf7_agent_release_recovery_write";
      const failureRun = path.join(root, ownedBaseRelative, "release-recovery-write");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 41 } });
      writeSave(targetSlot, { version: 1, payload: { value: 4 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      writeSave(seedSlot, { version: 1, payload: { value: 42 } });
      const recoveryPath = path.join(root, "tmp", "workbench-live-e2e", "manual-recovery",
        targetSlot + ".json");
      const originalWriteFileSync = fs.writeFileSync;
      fs.writeFileSync = function injectedRecoveryWriteFailure(filePath) {
        if (String(filePath).startsWith(recoveryPath + ".")) {
          const error = new Error("injected recovery transition write failure");
          error.code = "EIO";
          throw error;
        }
        return originalWriteFileSync.apply(fs, arguments);
      };
      try {
        assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
          (error) => error && error.code === "clone_recovery_record_failed");
      } finally {
        fs.writeFileSync = originalWriteFileSync;
      }
      assertRetainedCloneFailure(targetSlot, failureRun, "prepared_pending_release");
    });

    await test("private lock unlink failure retains prepared record and lock", async () => {
      const seedSlot = "fixture_release_unlink";
      const targetSlot = "cf7_agent_release_unlink";
      const failureRun = path.join(root, ownedBaseRelative, "release-unlink");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 51 } });
      writeSave(targetSlot, { version: 1, payload: { value: 5 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      const originalUnlinkSync = fs.unlinkSync;
      fs.unlinkSync = function injectedLockUnlinkFailure(filePath) {
        if (path.resolve(String(filePath)) === path.resolve(lock.path)) {
          const error = new Error("injected lock unlink failure");
          error.code = "EACCES";
          throw error;
        }
        return originalUnlinkSync.apply(fs, arguments);
      };
      try {
        assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
          (error) => error && error.code === "EACCES");
      } finally {
        fs.unlinkSync = originalUnlinkSync;
      }
      assertRetainedCloneFailure(targetSlot, failureRun, "prepared_pending_release");
    });

    await test("recovery clear failure leaves a prepared record for offline rollback", async () => {
      const seedSlot = "fixture_release_clear";
      const targetSlot = "cf7_agent_release_clear";
      const failureRun = path.join(root, ownedBaseRelative, "release-clear");
      fs.mkdirSync(failureRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: 61 } });
      writeSave(targetSlot, { version: 1, payload: { value: 6 } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: failureRun, ownedBaseRelative, seedSlot, targetSlot, lock });
      const recoveryPath = path.join(root, "tmp", "workbench-live-e2e", "manual-recovery",
        targetSlot + ".json");
      const originalUnlinkSync = fs.unlinkSync;
      fs.unlinkSync = function injectedRecoveryClearFailure(filePath) {
        if (path.resolve(String(filePath)) === path.resolve(recoveryPath)) {
          const error = new Error("injected recovery clear failure");
          error.code = "EACCES";
          throw error;
        }
        return originalUnlinkSync.apply(fs, arguments);
      };
      try {
        assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
          (error) => error && error.code === "EACCES");
      } finally {
        fs.unlinkSync = originalUnlinkSync;
      }
      const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
      assert.strictEqual(recovery.status, "prepared_pending_release");
      const recordOnlyInspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      assert.strictEqual(recordOnlyInspection.lockPresent, false);
      assert.strictEqual(recordOnlyInspection.recoveryPresent, true);
      assert.strictEqual(recordOnlyInspection.recoveryStatus, "prepared_pending_release");
      assert.strictEqual(recordOnlyInspection.recoveryRecordSha256, recovery.recordSha256);
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative }),
      (error) => error && error.code === "clone_manual_recovery_required");
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative, recoveryMode: true }),
      (error) => error && error.code === "clone_prepared_release_offline_recovery_required");
      const restored = CloneGuard.restoreAbandonedCloneFromRecovery({ root,
        slot: targetSlot, appData, expectedRecoveryRecordSha256: recovery.recordSha256,
        expectedRecoveryStatus: "prepared_pending_release", recordOnly: true,
        assertNoRuntime() { return true; } });
      assert.strictEqual(restored.recoveryFileAbsent, true);
      assert.strictEqual(restored.lockFileAbsent, true);
      assert.strictEqual(restored.recordOnly, true);
      assert.strictEqual(JSON.parse(fs.readFileSync(CloneGuard.saveJsonPath(root, targetSlot), "utf8"))
        .payload.value, 6);
      const ordinary = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: failureRun, ownedBaseRelative });
      CloneGuard.releaseCloneLock(ordinary);
    });

    await test("stable slot artifact capture binds the complete JSON and SOL set", async () => {
      const slot = "fixture_stable_seed";
      writeSave(slot, { version: 1, lastSaved: "stable", payload: { value: 8 } });
      fs.writeFileSync(ownedSolPath(slot), Buffer.from("stable-sol"), { flag: "wx" });
      const evidence = await CloneGuard.captureStableSlotArtifactSet({ root, appData, slot,
        stableMs: 2, pollMs: 1, timeoutMs: 100 });
      assert.strictEqual(evidence.apiVersion, CloneGuard.API_VERSION);
      assert.strictEqual(evidence.set.artifacts.length, 2);
      assert.ok(evidence.samples >= 2);
      assert.strictEqual(evidence.evidenceSha256,
        sha256Text(canonicalJson(Object.assign({}, evidence, { evidenceSha256: undefined }))));
    });

    await test("clone lock inspection is read-only on a pristine root", async () => {
      const pristineRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-clone-inspect-"));
      try {
        fs.mkdirSync(path.join(pristineRoot, "saves"), { recursive: true });
        const evidence = CloneGuard.inspectCloneLock({ root: pristineRoot,
          slot: "cf7_agent_pristine_inspection" });
        assert.strictEqual(evidence.lockPresent, false);
        assert.strictEqual(fs.existsSync(path.join(pristineRoot, "tmp")), false);
      } finally {
        fs.rmSync(pristineRoot, { recursive: true, force: true });
      }
    });

    await test("validation failure occurs before target mutation", async () => {
      const seedSlot = "fixture_seed";
      const targetSlot = "cf7_agent_validate_fail";
      writeSave(targetSlot, { version: 1, lastSaved: "old", payload: { value: 2 } });
      fs.writeFileSync(ownedSolPath(targetSlot), Buffer.from("validate-sol"), { flag: "wx" });
      const before = CloneGuard.captureSlotArtifactSet({ root, slot: targetSlot, appData });
      const validateRun = path.join(root, ownedBaseRelative, "validate-run");
      fs.mkdirSync(validateRun, { recursive: true });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot, runDir: validateRun,
        ownedBaseRelative });
      assert.throws(() => CloneGuard.prepareDedicatedClone({ root, appData, runDir: validateRun,
        ownedBaseRelative, seedSlot, targetSlot, lock,
        transformId: "fixture-invalid.v1", transformJson(value) { return value; },
        validateTarget() { return false; } }),
      (error) => error && error.code === "clone_target_contract_invalid");
      CloneGuard.assertArtifactSetInvariant(before,
        CloneGuard.captureSlotArtifactSet({ root, slot: targetSlot, appData }));
      assert.strictEqual(CloneGuard.readCloneRecovery(root, targetSlot, true), null);
      CloneGuard.releaseCloneLock(lock);
    });

    await test("target JSON changed after backup is never overwritten unbacked", async () => {
      const seedSlot = "fixture_target_compare_changed";
      const targetSlot = "cf7_agent_target_compare_changed";
      const compareRun = path.join(root, ownedBaseRelative, "target-compare-changed");
      fs.mkdirSync(compareRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: "C" } });
      writeSave(targetSlot, { version: 1, payload: { value: "A" } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: compareRun, ownedBaseRelative });
      assert.throws(() => CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: compareRun, ownedBaseRelative, seedSlot, targetSlot, lock,
        beforeJsonReplace() {
          writeSave(targetSlot, { version: 1, payload: { value: "B" } });
        } }),
      (error) => error && error.code === "clone_prepare_manual_recovery_required");
      assert.strictEqual(JSON.parse(fs.readFileSync(CloneGuard.saveJsonPath(root, targetSlot), "utf8"))
        .payload.value, "B");
      assertRetainedCloneFailure(targetSlot, compareRun, "manual_recovery_required");
    });

    await test("target JSON created after absent capture is never overwritten unbacked", async () => {
      const seedSlot = "fixture_target_compare_created";
      const targetSlot = "cf7_agent_target_compare_created";
      const compareRun = path.join(root, ownedBaseRelative, "target-compare-created");
      fs.mkdirSync(compareRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: "C" } });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: compareRun, ownedBaseRelative });
      assert.throws(() => CloneGuard.prepareDedicatedClone({ root, appData,
        runDir: compareRun, ownedBaseRelative, seedSlot, targetSlot, lock,
        beforeJsonReplace() {
          writeSave(targetSlot, { version: 1, payload: { value: "B" } });
        } }),
      (error) => error && error.code === "clone_prepare_manual_recovery_required");
      assert.strictEqual(JSON.parse(fs.readFileSync(CloneGuard.saveJsonPath(root, targetSlot), "utf8"))
        .payload.value, "B");
      assertRetainedCloneFailure(targetSlot, compareRun, "manual_recovery_required");
    });

    await test("clone release rejects a copied replacement lock handle", async () => {
      const seedSlot = "fixture_seed";
      const targetSlot = "cf7_agent_release_lock_swap";
      writeSave(targetSlot, { version: 1, lastSaved: "old", payload: { value: 4 } });
      const lockRun = path.join(root, ownedBaseRelative, "lock-swap-run");
      fs.mkdirSync(lockRun, { recursive: true });
      const firstLock = CloneGuard.acquireCloneLock({ root, slot: targetSlot, runDir: lockRun,
        ownedBaseRelative });
      const preparation = CloneGuard.prepareDedicatedClone({ root, appData, runDir: lockRun,
        ownedBaseRelative, seedSlot, targetSlot, lock: firstLock });
      assert.throws(() => CloneGuard.releaseCloneLock(firstLock),
        (error) => error && error.code === "clone_lock_release_blocked");
      const replacement = Object.assign({}, firstLock);
      assert.throws(() => CloneGuard.releaseDedicatedClone({ preparation, lock: replacement, appData }),
        (error) => error && error.code === "clone_lock_invalid");
      assert.strictEqual(CloneGuard.inspectCloneLock({ root, slot: targetSlot }).lockPresent, true);
      assert.strictEqual(CloneGuard.readCloneRecovery(root, targetSlot, false).status,
        "prepared_pending_release");
    });

    await test("post-SOL JSON failure retains an active-owner recovery barrier", async () => {
      const seedSlot = "fixture_seed";
      const targetSlot = "cf7_agent_manual_recovery";
      writeSave(targetSlot, { version: 1, lastSaved: "old", payload: { value: 3 } });
      fs.writeFileSync(ownedSolPath(targetSlot), Buffer.from("recovery-sol"), { flag: "wx" });
      const recoveryRun = path.join(root, ownedBaseRelative, "recovery-run");
      fs.mkdirSync(recoveryRun, { recursive: true });
      const lock = CloneGuard.acquireCloneLock({ root, slot: targetSlot, runDir: recoveryRun,
        ownedBaseRelative });
      assert.throws(() => CloneGuard.prepareDedicatedClone({ root, appData, runDir: recoveryRun,
        ownedBaseRelative, seedSlot, targetSlot, lock,
        beforeJsonReplace() { throw new Error("injected replace failure"); } }),
      (error) => error && error.code === "clone_prepare_manual_recovery_required");
      const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
      assert.strictEqual(recovery.status, "manual_recovery_required");
      assert.strictEqual(recovery.mutationProgress.filter((entry) => entry.operation === "sol_removed").length, 1);
      assert.throws(() => CloneGuard.releaseCloneLock(lock),
        (error) => error && error.code === "clone_lock_release_blocked");
      const retained = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      assert.strictEqual(retained.lockPresent, true);
      assert.strictEqual(retained.ownerState, "owner_active");
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: recoveryRun, ownedBaseRelative }),
      (error) => error && error.code === "clone_manual_recovery_required");
      assert.throws(() => CloneGuard.restoreAbandonedCloneFromRecovery({ root,
        slot: targetSlot, appData, expectedLockSha256: retained.recordSha256,
        expectedRecoveryRecordSha256: recovery.recordSha256,
        expectedRecoveryStatus: "manual_recovery_required",
        assertNoRuntime() { return true; } }),
      (error) => error && error.code === "clone_offline_lock_owner_not_absent");
    });

    await test("orphaned manual and prepared recoveries restore exact target bytes", async () => {
      const cases = [
        { name: "manual", status: "manual_recovery_required", exitCode: 78 },
        { name: "prepared", status: "prepared_pending_release", exitCode: 79 },
      ];
      for (const fixture of cases) {
        const seedSlot = "fixture_offline_" + fixture.name + "_seed";
        const targetSlot = "cf7_agent_offline_" + fixture.name + "_restore";
        const childRun = path.join(root, ownedBaseRelative,
          "offline-" + fixture.name + "-restore");
        fs.mkdirSync(childRun, { recursive: true });
        writeSave(seedSlot, { version: 1, payload: { value: "seed-" + fixture.name } });
        writeSave(targetSlot, { version: 1, payload: { value: "target-" + fixture.name } });
        fs.writeFileSync(ownedSolPath(targetSlot),
          Buffer.from("sol-" + fixture.name), { flag: "wx" });
        const childSource = [
          "'use strict';",
          "const guard=require(process.env.CF7_TEST_CLONE_GUARD_MODULE);",
          "const options={root:process.env.CF7_TEST_CLONE_ROOT,",
          " appData:process.env.CF7_TEST_CLONE_APPDATA,",
          " runDir:process.env.CF7_TEST_CLONE_RUN_DIR,",
          " ownedBaseRelative:process.env.CF7_TEST_CLONE_OWNED_BASE,",
          " seedSlot:process.env.CF7_TEST_CLONE_SEED_SLOT,",
          " targetSlot:process.env.CF7_TEST_CLONE_TARGET_SLOT};",
          "const lock=guard.acquireCloneLock({root:options.root,slot:options.targetSlot,",
          " runDir:options.runDir,ownedBaseRelative:options.ownedBaseRelative});",
          "if(process.env.CF7_TEST_CLONE_MODE==='manual'){",
          " try{guard.prepareDedicatedClone(Object.assign({},options,{lock,",
          "   beforeJsonReplace(){throw new Error('injected manual recovery');}}));}",
          " catch(error){process.exit(error.code==='clone_prepare_manual_recovery_required'?78:88);}",
          " process.exit(89);",
          "}",
          "guard.prepareDedicatedClone(Object.assign({},options,{lock}));",
          "process.exit(79);",
        ].join("\n");
        const child = childProcess.spawnSync(process.execPath, ["-e", childSource], {
          encoding: "utf8", windowsHide: true, timeout: 30000,
          env: Object.assign({}, process.env, {
            CF7_TEST_CLONE_GUARD_MODULE: path.join(__dirname, "clone-save-guard.js"),
            CF7_TEST_CLONE_ROOT: root,
            CF7_TEST_CLONE_APPDATA: appData,
            CF7_TEST_CLONE_RUN_DIR: childRun,
            CF7_TEST_CLONE_OWNED_BASE: ownedBaseRelative,
            CF7_TEST_CLONE_SEED_SLOT: seedSlot,
            CF7_TEST_CLONE_TARGET_SLOT: targetSlot,
            CF7_TEST_CLONE_MODE: fixture.name,
          }),
        });
        assert.strictEqual(child.status, fixture.exitCode, String(child.stderr || ""));
        const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
        const inspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
        assert.strictEqual(recovery.status, fixture.status);
        assert.strictEqual(inspection.ownerState, "owner_absent");
        const restored = CloneGuard.restoreAbandonedCloneFromRecovery({ root, appData,
          slot: targetSlot, expectedLockSha256: inspection.recordSha256,
          expectedRecoveryRecordSha256: recovery.recordSha256,
          expectedRecoveryStatus: fixture.status,
          assertNoRuntime() { return true; } });
        assert.strictEqual(restored.lockFileAbsent, true);
        assert.strictEqual(restored.recoveryFileAbsent, true);
        assert.strictEqual(JSON.parse(fs.readFileSync(
          CloneGuard.saveJsonPath(root, targetSlot), "utf8")).payload.value,
        "target-" + fixture.name);
        assert.strictEqual(fs.readFileSync(ownedSolPath(targetSlot), "utf8"),
          "sol-" + fixture.name);
        const ordinary = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
          runDir: childRun, ownedBaseRelative });
        CloneGuard.releaseCloneLock(ordinary);
      }
    });

    await test("backup drift retains orphan lock, recovery record, and retry path", async () => {
      const seedSlot = "fixture_offline_backup_seed";
      const targetSlot = "cf7_agent_offline_backup_drift";
      const childRun = path.join(root, ownedBaseRelative, "offline-backup-drift");
      fs.mkdirSync(childRun, { recursive: true });
      writeSave(seedSlot, { version: 1, payload: { value: "seed-backup" } });
      writeSave(targetSlot, { version: 1, payload: { value: "target-backup" } });
      const childSource = [
        "'use strict';",
        "const guard=require(process.env.CF7_TEST_CLONE_GUARD_MODULE);",
        "const root=process.env.CF7_TEST_CLONE_ROOT;",
        "const appData=process.env.CF7_TEST_CLONE_APPDATA;",
        "const runDir=process.env.CF7_TEST_CLONE_RUN_DIR;",
        "const ownedBaseRelative=process.env.CF7_TEST_CLONE_OWNED_BASE;",
        "const seedSlot=process.env.CF7_TEST_CLONE_SEED_SLOT;",
        "const targetSlot=process.env.CF7_TEST_CLONE_TARGET_SLOT;",
        "const lock=guard.acquireCloneLock({root,slot:targetSlot,runDir,ownedBaseRelative});",
        "guard.prepareDedicatedClone({root,appData,runDir,ownedBaseRelative,seedSlot,targetSlot,lock});",
        "process.exit(80);",
      ].join("\n");
      const child = childProcess.spawnSync(process.execPath, ["-e", childSource], {
        encoding: "utf8", windowsHide: true, timeout: 30000,
        env: Object.assign({}, process.env, {
          CF7_TEST_CLONE_GUARD_MODULE: path.join(__dirname, "clone-save-guard.js"),
          CF7_TEST_CLONE_ROOT: root,
          CF7_TEST_CLONE_APPDATA: appData,
          CF7_TEST_CLONE_RUN_DIR: childRun,
          CF7_TEST_CLONE_OWNED_BASE: ownedBaseRelative,
          CF7_TEST_CLONE_SEED_SLOT: seedSlot,
          CF7_TEST_CLONE_TARGET_SLOT: targetSlot,
        }),
      });
      assert.strictEqual(child.status, 80, String(child.stderr || ""));
      const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
      const inspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      const backupPath = path.resolve(childRun,
        recovery.backups[0].backupRelativePath.replace(/\//g, path.sep));
      const originalBackup = fs.readFileSync(backupPath);
      fs.writeFileSync(backupPath, Buffer.from("tampered-offline-backup"));
      assert.throws(() => CloneGuard.restoreAbandonedCloneFromRecovery({ root, appData,
        slot: targetSlot, expectedLockSha256: inspection.recordSha256,
        expectedRecoveryRecordSha256: recovery.recordSha256,
        expectedRecoveryStatus: "prepared_pending_release",
        assertNoRuntime() { return true; } }),
      (error) => error && error.code === "clone_backup_digest_mismatch");
      const retained = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      assert.strictEqual(retained.recordSha256, inspection.recordSha256);
      assert.strictEqual(retained.recoveryRecordSha256, recovery.recordSha256);
      fs.writeFileSync(backupPath, originalBackup);
      const restored = CloneGuard.restoreAbandonedCloneFromRecovery({ root, appData,
        slot: targetSlot, expectedLockSha256: inspection.recordSha256,
        expectedRecoveryRecordSha256: recovery.recordSha256,
        expectedRecoveryStatus: "prepared_pending_release",
        assertNoRuntime() { return true; } });
      assert.strictEqual(restored.lockFileAbsent, true);
      assert.strictEqual(restored.recoveryFileAbsent, true);
    });

    await test("hard crash fail-closes until exact stale lock evidence is handled offline", async () => {
      const seedSlot = "fixture_seed";
      const targetSlot = "cf7_agent_hard_crash_recovery";
      writeSave(targetSlot, { version: 1, lastSaved: "old", payload: { value: 5 } });
      fs.writeFileSync(ownedSolPath(targetSlot), Buffer.from("hard-crash-sol"), { flag: "wx" });
      const crashRun = path.join(root, ownedBaseRelative, "hard-crash-run");
      fs.mkdirSync(crashRun, { recursive: true });
      const childSource = [
        "'use strict';",
        "const guard=require(process.env.CF7_TEST_CLONE_GUARD_MODULE);",
        "const root=process.env.CF7_TEST_CLONE_ROOT;",
        "const appData=process.env.CF7_TEST_CLONE_APPDATA;",
        "const runDir=process.env.CF7_TEST_CLONE_RUN_DIR;",
        "const ownedBaseRelative=process.env.CF7_TEST_CLONE_OWNED_BASE;",
        "const seedSlot=process.env.CF7_TEST_CLONE_SEED_SLOT;",
        "const targetSlot=process.env.CF7_TEST_CLONE_TARGET_SLOT;",
        "const lock=guard.acquireCloneLock({root,slot:targetSlot,runDir,ownedBaseRelative});",
        "guard.prepareDedicatedClone({root,appData,runDir,ownedBaseRelative,seedSlot,targetSlot,lock,",
        "  beforeJsonReplace(){process.exit(73);}});",
        "process.exit(72);",
      ].join("\n");
      const crashed = childProcess.spawnSync(process.execPath, ["-e", childSource], {
        encoding: "utf8", windowsHide: true, timeout: 30000,
        env: Object.assign({}, process.env, {
          CF7_TEST_CLONE_GUARD_MODULE: path.join(__dirname, "clone-save-guard.js"),
          CF7_TEST_CLONE_ROOT: root,
          CF7_TEST_CLONE_APPDATA: appData,
          CF7_TEST_CLONE_RUN_DIR: crashRun,
          CF7_TEST_CLONE_OWNED_BASE: ownedBaseRelative,
          CF7_TEST_CLONE_SEED_SLOT: seedSlot,
          CF7_TEST_CLONE_TARGET_SLOT: targetSlot,
        }),
      });
      assert.strictEqual(crashed.status, 73,
        "hard-crash child did not stop at the mutation boundary: " + String(crashed.stderr || ""));
      const recovery = CloneGuard.readCloneRecovery(root, targetSlot, false);
      assert.strictEqual(recovery.status, "mutation_in_progress");
      assert.strictEqual(CloneGuard.findOwnedSolFiles({ root, slot: targetSlot, appData }).length, 0);
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: crashRun, ownedBaseRelative }),
      (error) => error && error.code === "clone_manual_recovery_required");
      assert.throws(() => CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: crashRun, ownedBaseRelative, recoveryMode: true }),
      (error) => error && error.code === "clone_lock_unavailable");
      const inspection = CloneGuard.inspectCloneLock({ root, slot: targetSlot });
      assert.strictEqual(inspection.lockPresent, true);
      assert.strictEqual(inspection.ownerState, "owner_absent");
      assert.strictEqual(inspection.recoveryRecordSha256, recovery.recordSha256);
      const exactStaleBytes = fs.readFileSync(inspection.lockPath);
      assert.strictEqual(sha256Bytes(exactStaleBytes), inspection.recordSha256);
      const exactStaleRecord = JSON.parse(exactStaleBytes.toString("utf8"));
      assert.strictEqual(exactStaleRecord.pid, inspection.ownerPid);
      assert.strictEqual(exactStaleRecord.ownerProcessStartUtcTicks,
        inspection.ownerProcessStartUtcTicks);
      const restored = CloneGuard.restoreAbandonedCloneFromRecovery({ root, appData,
        slot: targetSlot, expectedLockSha256: inspection.recordSha256,
        expectedRecoveryRecordSha256: recovery.recordSha256,
        expectedRecoveryStatus: "mutation_in_progress",
        assertNoRuntime() { return true; } });
      assert.strictEqual(restored.recoveryFileAbsent, true);
      assert.strictEqual(restored.lockFileAbsent, true);
      assert.strictEqual(fs.readFileSync(ownedSolPath(targetSlot), "utf8"), "hard-crash-sol");
      const ordinary = CloneGuard.acquireCloneLock({ root, slot: targetSlot,
        runDir: crashRun, ownedBaseRelative });
      CloneGuard.releaseCloneLock(ordinary);
    });

    await test("authenticated legacy HTTP session exposes lifecycle only", async () => {
      const portsFile = path.join(root, "launcher_ports.json");
      const credentialFile = path.join(root, "legacy-http-credential.json");
      fs.writeFileSync(portsFile, JSON.stringify({ pid: 7001, httpPort: 18080, socketPort: 18081 }), "utf8");
      fs.writeFileSync(credentialFile, JSON.stringify({ token: "fixture" }), "utf8");
      const calls = [];
      const context = { projectRoot: root, portsFile, pid: 7001, httpPort: 18080, socketPort: 18081,
        authorizationHeaders: { "X-CF7-Automation-Token": "x" },
        credential: { path: credentialFile, header: "X-CF7-Automation-Token",
          token: "secret-token-not-public", pid: 7001, processStartUtcTicks: "638900000000000001",
          lifecycleId: "fixture-life-one", capabilities: ["legacy.console", "legacy.status",
            "legacy.task", "legacy.logs"] } };
      const session = LauncherObservation.openAuthenticatedLegacyHttpSession({ root,
        contextReader() { return context; }, requestImpl(_context, method, pathname, body) {
          calls.push({ method, pathname, body });
          if (pathname.startsWith("/logs")) return Promise.resolve({ statusCode: 200,
            text: JSON.stringify({ success: true, total: 0, lines: [] }) });
          return Promise.resolve({ statusCode: 200, text: JSON.stringify({ success: true, ok: true }) });
        } });
      await session.getStatus();
      await session.agentControl("start", { slot: "cf7_agent_fixture", fresh: false });
      await session.requestFixedAgentEnter();
      const emptyLog = await session.readTerminalLogSnapshot(2000);
      assert.strictEqual(emptyLog.total, 0);
      await assert.rejects(() => session.agentControl("openEquipmentTuning", {}),
        (error) => error && error.code === "agent_control_action_forbidden");
      assert.strictEqual(JSON.stringify(session.evidence).includes("secret-token-not-public"), false);
      assert.deepStrictEqual(calls.map((entry) => entry.pathname),
        ["/status", "/task", "/console", "/logs?lines=2000"]);

      const httpModule = require("http");
      const originalHttpRequest = httpModule.request;
      let observedRequestOptions = null;
      try {
        httpModule.request = function requestProbe(options, callback) {
          observedRequestOptions = options;
          const requestListeners = {};
          return {
            on(name, handler) { requestListeners[name] = handler; return this; },
            destroy(error) {
              if (error && requestListeners.error) requestListeners.error(error);
            },
            end() {
              const responseListeners = {};
              const response = {
                statusCode: 200,
                on(name, handler) { responseListeners[name] = handler; return this; },
              };
              callback(response);
              process.nextTick(() => {
                responseListeners.data(Buffer.from(JSON.stringify({ success: true, ok: true })));
                responseListeners.end();
              });
            },
          };
        };
        const defaultRequestSession = LauncherObservation.openAuthenticatedLegacyHttpSession({ root,
          contextReader() { return context; } });
        await defaultRequestSession.getStatus();
        assert.strictEqual(observedRequestOptions.hostname, "localhost");
        assert.strictEqual(observedRequestOptions.path, "/status");
        assert.strictEqual(observedRequestOptions.method, "GET");
      } finally {
        httpModule.request = originalHttpRequest;
      }

      const identity = { pid: 7001,
        processPath: path.join(root, "candidate", "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe") };
      const attestation = LauncherObservation.attestAuthenticatedLauncherProcess({ root,
        sessionEvidence: session.evidence, runtimeIdentity: identity,
        observeProcess() { return { pid: 7001, processPath: identity.processPath,
          processStartUtcTicks: "638900000000000001",
          commandLine: '"' + identity.processPath + '" --project-root "' + root
            + '" --legacy-http-automation' }; } });
      assert.strictEqual(attestation.agentRuntimeAdmission, false);
      assert.throws(() => LauncherObservation.attestAuthenticatedLauncherProcess({ root,
        sessionEvidence: session.evidence, runtimeIdentity: identity,
        observeProcess() { return { pid: 7001, processPath: identity.processPath,
          processStartUtcTicks: "638900000000000001",
          commandLine: '"' + identity.processPath + '" --project-root "' + root + '"' }; } }),
      (error) => error && error.code === "launcher_process_contract_mismatch");
      assert.throws(() => LauncherObservation.attestAuthenticatedLauncherProcess({ root,
        sessionEvidence: session.evidence, runtimeIdentity: identity,
        observeProcess() { return { pid: 7001, processPath: identity.processPath,
          processStartUtcTicks: "638900000000000001",
          commandLine: '"' + identity.processPath + '" --project-root "' + root
            + '-spoof" --legacy-http-automation "' + root + '"' }; } }),
      (error) => error && error.code === "launcher_process_contract_mismatch");
      assert.deepStrictEqual(parseWindowsCommandLine('"C:\\Program Files\\Core.exe" --flag "x y"'),
        ["C:\\Program Files\\Core.exe", "--flag", "x y"]);
    });

    await test("terminal boundary uses full tail total and rejects gaps", async () => {
      const first = normalizeFixtureLog({ success: true, total: 3,
        lines: ["one", "two", "three"] }, 10, "2026-08-03T00:00:00.000Z");
      const boundary = LauncherObservation.createTerminalLogBoundary(first);
      const final = normalizeFixtureLog({ success: true, total: 6,
        lines: ["one", "two", "three", "four", "five", "six"] }, 10,
      "2026-08-03T00:00:01.000Z");
      assert.deepStrictEqual(LauncherObservation.recordsAfterTerminalBoundary(boundary, final)
        .map((entry) => entry.lineNumber), [4, 5, 6]);
      assert.throws(() => normalizeFixtureLog({ success: true, total: 6,
        lines: ["five", "six"] }, 10),
      (error) => error && error.code === "log_tail_incomplete");
      const narrow = normalizeFixtureLog({ success: true, total: 20,
        lines: ["18", "19", "20"] }, 3);
      assert.throws(() => LauncherObservation.recordsAfterTerminalBoundary(boundary, narrow),
        (error) => error && error.code === "log_gap_after_boundary");
      const tamperedBoundary = Object.assign({}, boundary, { terminalTotal: 2 });
      assert.throws(() => LauncherObservation.verifyTerminalLogBoundary(tamperedBoundary),
        (error) => error && error.code === "log_terminal_boundary_mismatch");
    });

    await test("terminal boundary rejects reset catch-up lifecycle drift and lost overlap", async () => {
      const firstSession = sealedSessionEvidence({ lifecycleId: "log-life-one" });
      const secondSession = sealedSessionEvidence({ lifecycleId: "log-life-two",
        pid: 2, processStartUtcTicks: "638900000000000002" });
      const first = normalizeFixtureLog({ success: true, total: 2,
        lines: ["A", "B"] }, 2000, "2026-08-03T00:00:00.000Z", firstSession);
      const boundary = LauncherObservation.createTerminalLogBoundary(first);
      const resetCatchUp = normalizeFixtureLog({ success: true, total: 3,
        lines: ["X", "Y", "Z"] }, 2000, "2026-08-03T00:00:01.000Z", firstSession);
      assert.throws(() => LauncherObservation.recordsAfterTerminalBoundary(boundary, resetCatchUp),
        (error) => error && error.code === "log_overlap_changed_after_boundary");
      const crossLifecycle = normalizeFixtureLog({ success: true, total: 3,
        lines: ["A", "B", "C"] }, 2000, "2026-08-03T00:00:01.000Z", secondSession);
      assert.throws(() => LauncherObservation.recordsAfterTerminalBoundary(boundary, crossLifecycle),
        (error) => error && error.code === "log_lifecycle_changed_after_boundary");
      const overlapTampered = normalizeFixtureLog({ success: true, total: 3,
        lines: ["A", "tampered-B", "C"] }, 2000,
      "2026-08-03T00:00:01.000Z", firstSession);
      assert.throws(() => LauncherObservation.recordsAfterTerminalBoundary(boundary, overlapTampered),
        (error) => error && error.code === "log_overlap_changed_after_boundary");
      const twoThousandNewLines = Array.from({ length: 2000 }, (_value, index) =>
        "new-" + String(index + 2));
      const noOverlap = normalizeFixtureLog({ success: true, total: 2002,
        lines: twoThousandNewLines }, 2000, "2026-08-03T00:00:02.000Z", firstSession);
      assert.throws(() => LauncherObservation.recordsAfterTerminalBoundary(boundary, noOverlap),
        (error) => error && error.code === "log_overlap_missing_after_boundary");
    });

    await test("archive receipt binds exact fresh tail order and disk bytes", async () => {
      const slot = "cf7_agent_archive_fixture";
      writeSave(slot, { version: 1, value: "persisted" });
      const jsonPath = CloneGuard.saveJsonPath(root, slot);
      const characters = fs.readFileSync(jsonPath, "utf8").length;
      const first = normalizeFixtureLog({ success: true, total: 1,
        lines: ["baseline"] }, 10, "2026-08-03T00:00:00.000Z");
      const boundary = LauncherObservation.createTerminalLogBoundary(first);
      const final = normalizeFixtureLog({ success: true, total: 3,
        lines: ["baseline", "00:00:01.000 [Frame:UI] sample count=1 q:1|sv:1|q:1|sv:2|q:1",
          "00:00:02.000 [ArchiveTask] Shadow saved: " + slot + " (" + characters
            + " chars) path=" + jsonPath] }, 10, "2026-08-03T00:00:04.000Z");
      const evidence = LauncherObservation.verifyArchiveSaveEvidence({ root, slot,
        boundary, snapshot: final, requiredOrder: ["sv1", "sv2", "archive"] });
      assert.strictEqual(evidence.disk.textCharacters, characters);
      assert.strictEqual(evidence.positions.sv1.lineNumber, evidence.positions.sv2.lineNumber);
      assert.ok(evidence.positions.sv1.offset < evidence.positions.sv2.offset);
      const extra = normalizeFixtureLog({ success: true, total: 4,
        lines: final.records.map((entry) => entry.line).concat(
          "00:00:03.000 [ArchiveTask] Shadow saved: " + slot + " (" + characters
            + " chars) path=" + jsonPath) }, 10);
      assert.throws(() => LauncherObservation.verifyArchiveSaveEvidence({ root, slot,
        boundary, snapshot: extra, requiredOrder: ["sv1", "sv2", "archive"] }),
      (error) => error && error.code === "archive_save_record_count_invalid");
      const failedSave = normalizeFixtureLog({ success: true, total: 4,
        lines: final.records.map((entry) => entry.line).concat(
          "00:00:03.000 [Frame:UI] sample count=1 sv:3") }, 10);
      assert.throws(() => LauncherObservation.verifyArchiveSaveEvidence({ root, slot,
        boundary, snapshot: failedSave, requiredOrder: ["sv1", "sv2", "archive"] }),
      (error) => error && error.code === "archive_save_record_count_invalid");
    });

    await test("runtime readiness is bound to terminal tail, slot, attempt, and one fixed enter", async () => {
      const empty = normalizeFixtureLog({ success: true, total: 0, lines: [] }, 2000,
        "2026-08-03T00:00:00.000Z");
      const boundary = LauncherObservation.createTerminalLogBoundary(empty);
      let entered = false;
      const attemptId = "attempt-fixture";
      function status() {
        return { success: true, ok: true, launchState: "Ready", revealPerformed: true,
          socketConnected: true, readyForRuntimeAutomation: entered,
          runtimeReadyBlockedBy: entered ? [] : ["runtime_save_not_loaded"],
          gameEnteredObserved: entered, gameEnteredAttemptId: entered ? attemptId : null,
          save: { decision: "snapshot", kind: "Snapshot", slot: "cf7_agent_fixture",
            attemptId },
          saveRuntime: entered ? { loaded: true, savePath: "cf7_agent_fixture",
            attemptId, role: "fixture", level: 10 } : null };
      }
      const session = {
        agentControl() { return Promise.resolve(status()); },
        readTerminalLogSnapshot() { return Promise.resolve(normalizeFixtureLog({
          success: true, total: 2, lines: [HANDOFF_LINE(), TITLE_LINE()] }, 2000)); },
        requestFixedAgentEnter() { entered = true; return Promise.resolve({ success: true }); },
      };
      function HANDOFF_LINE() { return "00:00:01.000 [BootstrapAS] event=handoff"; }
      function TITLE_LINE() { return "00:00:02.000 [LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared"; }
      const ready = await LauncherObservation.waitForRuntimeReady(session, {
        startBoundary: boundary, slot: "cf7_agent_fixture", timeoutMs: 1000, pollMs: 1,
      });
      assert.strictEqual(ready.enterRequestCount, 1);
      assert.strictEqual(ready.expectedAttemptId, attemptId);
    });

    await test("fresh restart binds PID attempt and authenticated credential lifecycle", async () => {
      const base = { runtimeMode: "isolated_candidate", processPath: "C:\\candidate\\runtime\\core.exe",
        coreSha256: "1".repeat(64), buildIdentity: "2".repeat(64), payloadClosure: "3".repeat(64) };
      const first = Object.assign({}, base, { pid: 7001 });
      const restart = Object.assign({}, base, { pid: 7002 });
      assert.strictEqual(assertFreshRestartIdentity({ first, restart,
        firstAttemptId: "attempt-one", restartAttemptId: "attempt-two" }).restartPid, 7002);
      const result = LauncherObservation.assertFreshAuthenticatedRestart({ first, restart,
        firstAttemptId: "attempt-one", restartAttemptId: "attempt-two",
        firstSession: sealedSessionEvidence({ pid: 7001, lifecycleId: "life-one",
          processStartUtcTicks: "638900000000000001", credentialFileSha256: "a".repeat(64),
          credentialTokenSha256: "c".repeat(64) }),
        restartSession: sealedSessionEvidence({ pid: 7002, httpPort: 10003, socketPort: 10004,
          lifecycleId: "life-two", processStartUtcTicks: "638900000000000002",
          credentialFileSha256: "b".repeat(64), credentialTokenSha256: "d".repeat(64) }) });
      assert.strictEqual(result.restartLifecycleId, "life-two");
    });

    await test("PID ports rendezvous and credential residue require stable absence", async () => {
      const absentPorts = path.join(root, "absent-launcher-ports.json");
      const absentCredential = path.join(root, "absent-credential.json");
      const sessionEvidence = sealedSessionEvidence({ pid: 9001, httpPort: 19001,
        socketPort: 19002, portsFile: absentPorts, credentialFile: absentCredential });
      const options = { root,
        runtimeIdentity: { pid: 9001, processPath: "C:\\candidate\\runtime\\core.exe" },
        sessionEvidence,
        cdpBinding: { port: 19003 }, queryProcesses() { return []; },
        probePort() { return Promise.resolve(false); }, timeoutMs: 1000, pollMs: 1, stableSamples: 2 };
      const residue = await LauncherObservation.waitForCleanResidue(options);
      assert.strictEqual(residue.stableSamples, 2);
      LauncherObservation.assertResidueClean(residue);
      const unexpectedGlobalProcess = Object.assign({}, residue, { observedLauncherPids: [9002] });
      delete unexpectedGlobalProcess.evidenceSha256;
      unexpectedGlobalProcess.evidenceSha256 = sha256Text(canonicalJson(unexpectedGlobalProcess));
      assert.throws(() => LauncherObservation.assertResidueClean(unexpectedGlobalProcess),
        (error) => error && error.code === "runtime_residue_not_clean");
    });

    await test("diagnostic source fingerprint follows literal local requires without admission authority", async () => {
      const projectRoot = path.resolve(__dirname, "..", "..", "..");
      const fixtureRoot = fs.mkdtempSync(path.join(projectRoot, "tmp", "source-fingerprint-selftest-"));
      try {
        const entry = path.join(fixtureRoot, "entry.js");
        const dependency = path.join(fixtureRoot, "dependency.js");
        fs.writeFileSync(entry, "\"use strict\"; module.exports=require('./dependency');\n", "utf8");
        fs.writeFileSync(dependency, "\"use strict\"; const fs=require('fs'); module.exports=fs.sep;\n", "utf8");
        const relativeEntry = path.relative(projectRoot, entry);
        const begin = SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "before_clone", entrypoints: [relativeEntry] });
        const end = SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "after_shutdown", entrypoints: [relativeEntry] });
        assert.ok(begin.files.some((file) => file.relativePath.endsWith("source-fingerprint.js")));
        assert.strictEqual(begin.admissionEligible, false);
        assert.strictEqual(begin.admissionStatus, "DIAGNOSTIC_ONLY");
        assert.ok(begin.files.some((file) => file.relativePath.endsWith("dependency.js")));
        assert.strictEqual(SourceFingerprint.verifySourceFingerprintPhases({ root: projectRoot,
          fingerprints: [begin, end], requiredPhases: ["before_clone", "after_shutdown"] })
          .contentSha256, begin.contentSha256);
        fs.writeFileSync(dependency, "\"use strict\"; module.exports='changed';\n", "utf8");
        assert.throws(() => SourceFingerprint.verifySourceFingerprint({ root: projectRoot,
          fingerprint: begin }),
        (error) => error && error.code === "source_fingerprint_mismatch");
        fs.writeFileSync(dependency, "\"use strict\"; const fs=require('fs'); module.exports=fs.sep;\n", "utf8");
        const dynamic = path.join(fixtureRoot, "dynamic.js");
        fs.writeFileSync(dynamic, "const name='./dependency'; module.exports=require(name);\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "dynamic", entrypoints: [path.relative(projectRoot, dynamic)] }),
        (error) => error && error.code === "source_dynamic_require_forbidden");
        const bracket = path.join(fixtureRoot, "bracket.js");
        fs.writeFileSync(bracket, "module.exports=globalThis['require']('./dependency');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "bracket", entrypoints: [path.relative(projectRoot, bracket)] }),
        (error) => error && error.code === "source_dynamic_property_forbidden");
        const computed = path.join(fixtureRoot, "computed.js");
        fs.writeFileSync(computed,
          "const key='requ'+'ire'; module.exports=module[key]('./dependency');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "computed", entrypoints: [path.relative(projectRoot, computed)] }),
        (error) => error && error.code === "source_dynamic_property_forbidden");
        const aliasedModule = path.join(fixtureRoot, "aliased-module.js");
        fs.writeFileSync(aliasedModule,
          "const m=module; module.exports=m['re'+'quire']('./dependency');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "aliased_module", entrypoints: [path.relative(projectRoot, aliasedModule)] }),
        (error) => error && error.code === "source_loader_global_reference_forbidden");
        const aliasedProcess = path.join(fixtureRoot, "aliased-process.js");
        fs.writeFileSync(aliasedProcess,
          "const p=process; module.exports=p['get'+'BuiltinModule']('fs');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "aliased_process", entrypoints: [path.relative(projectRoot, aliasedProcess)] }),
        (error) => error && error.code === "source_loader_global_reference_forbidden");
        const loaderBuiltin = path.join(fixtureRoot, "loader-builtin.js");
        fs.writeFileSync(loaderBuiltin, "module.exports=require('module');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "loader_builtin", entrypoints: [path.relative(projectRoot, loaderBuiltin)] }),
        (error) => error && error.code === "source_loader_builtin_forbidden");
        const escapedIdentifier = path.join(fixtureRoot, "escaped-identifier.js");
        fs.writeFileSync(escapedIdentifier,
          "module.exports=mod\\u0075le['re'+'quire']('./dependency');\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "escaped_identifier", entrypoints: [path.relative(projectRoot, escapedIdentifier)] }),
        (error) => error && error.code === "source_identifier_escape_forbidden");
        const constructorEscape = path.join(fixtureRoot, "constructor-escape.js");
        fs.writeFileSync(constructorEscape,
          "module.exports=console.log['con'+'structor']('return process')().pid;\n", "utf8");
        const constructorDiagnostic = SourceFingerprint.buildTransitiveSourceFingerprint({
          root: projectRoot, phase: "constructor_escape_diagnostic",
          entrypoints: [path.relative(projectRoot, constructorEscape)] });
        assert.strictEqual(constructorDiagnostic.admissionEligible, false);
        const interpolated = path.join(fixtureRoot, "interpolated.js");
        fs.writeFileSync(interpolated,
          "module.exports=`fixture:${require('./dependency')}`;\n", "utf8");
        const interpolatedFingerprint = SourceFingerprint.buildTransitiveSourceFingerprint({
          root: projectRoot, phase: "interpolated",
          entrypoints: [path.relative(projectRoot, interpolated)] });
        assert.ok(interpolatedFingerprint.files.some((file) =>
          file.relativePath.endsWith("dependency.js")));
        const external = path.join(fixtureRoot, "external.js");
        const externalArtifact = path.join(fixtureRoot, "external-lock.json");
        fs.writeFileSync(external, "module.exports=require('fixture-external');\n", "utf8");
        fs.writeFileSync(externalArtifact, "{\"fixture\":true}\n", "utf8");
        assert.throws(() => SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "external_missing", entrypoints: [path.relative(projectRoot, external)] }),
        (error) => error && error.code === "source_external_artifact_required");
        const externalBound = SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
          phase: "external_bound", entrypoints: [path.relative(projectRoot, external)],
          externalArtifacts: [{ specifier: "fixture-external",
            artifactPath: path.relative(projectRoot, externalArtifact) }] });
        assert.strictEqual(externalBound.externalArtifacts[0].specifier, "fixture-external");
        assert.throws(() => SourceFingerprint.verifySourceFingerprintPhases({ root: projectRoot,
          fingerprints: [begin, end], requiredPhases: ["before_clone", "before_clone"] }),
        (error) => error && error.code === "source_phase_set_invalid");
      } finally {
        fs.rmSync(fixtureRoot, { recursive: true, force: true });
      }
    });
    await test("diagnostic fingerprint never promotes the legacy recursive closure to admission", async () => {
      const projectRoot = path.resolve(__dirname, "..", "..", "..");
      const entrypoints = ["evidence-artifact.js", "control-contract.js", "runtime-guard.js",
        "clone-save-guard.js", "launcher-observation.js", "source-fingerprint.js"]
        .map((name) => path.relative(projectRoot, path.join(__dirname, name)));
      const before = SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
        phase: "freeze_before", entrypoints });
      const after = SourceFingerprint.buildTransitiveSourceFingerprint({ root: projectRoot,
        phase: "freeze_after", entrypoints });
      assert.strictEqual(before.files.length, 9);
      assert.strictEqual(before.externalArtifacts.length, 0);
      assert.strictEqual(before.admissionEligible, false);
      assert.strictEqual(SourceFingerprint.verifySourceFingerprintPhases({ root: projectRoot,
        fingerprints: [before, after], requiredPhases: ["freeze_before", "freeze_after"] })
        .contentSha256, before.contentSha256);
    });
    await test("WebView debug environment restores caller state", async () => {
      const oldArgs = process.env.CF7_WEBVIEW2_ARGS;
      const oldMode = process.env.CF7_WEBVIEW2_DEV_MODE;
      delete process.env.CF7_WEBVIEW2_ARGS;
      delete process.env.CF7_WEBVIEW2_DEV_MODE;
      try {
        withWebViewDebugEnvironment(19444, () => {
          assert.strictEqual(process.env.CF7_WEBVIEW2_ARGS, "--remote-debugging-port=19444");
          assert.strictEqual(process.env.CF7_WEBVIEW2_DEV_MODE, "1");
        });
        assert.strictEqual(process.env.CF7_WEBVIEW2_ARGS, undefined);
      } finally {
        if (oldArgs === undefined) delete process.env.CF7_WEBVIEW2_ARGS;
        else process.env.CF7_WEBVIEW2_ARGS = oldArgs;
        if (oldMode === undefined) delete process.env.CF7_WEBVIEW2_DEV_MODE;
        else process.env.CF7_WEBVIEW2_DEV_MODE = oldMode;
      }
    });
    await test("runtime CDP attestation selects the exact IPv4 endpoint from dual-stack listeners", async () => {
      const runtimePid = 4200;
      const ipv4Pid = 4300;
      const ipv6Pid = 4400;
      const port = 19445;
      const userDataRoot = "C:\\fixture\\overlay-profile";
      const otherUserDataRoot = "C:\\fixture\\bootstrap-profile";
      const executablePath = "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\fixture\\msedgewebview2.exe";
      const originalSpawnSync = childProcess.spawnSync;
      let calls = 0;
      childProcess.spawnSync = function mockedPowerShell() {
        calls += 1;
        if (calls === 1) {
          return { status: 0, stderr: "", stdout: JSON.stringify([
            { LocalAddress: "::1", LocalPort: port, OwningProcess: ipv6Pid },
            { LocalAddress: "127.0.0.1", LocalPort: port, OwningProcess: ipv4Pid },
          ]) };
        }
        if (calls === 2) {
          return { status: 0, stderr: "", stdout: JSON.stringify([
            { ProcessId: runtimePid, ParentProcessId: 1,
              ExecutablePath: "C:\\fixture\\Core.exe", CommandLine: "C:\\fixture\\Core.exe" },
            { ProcessId: ipv4Pid, ParentProcessId: runtimePid, ExecutablePath: executablePath,
              CommandLine: '"' + executablePath + '" --user-data-dir="' + userDataRoot
                + '" --remote-debugging-port=' + port },
            { ProcessId: ipv6Pid, ParentProcessId: runtimePid, ExecutablePath: executablePath,
              CommandLine: '"' + executablePath + '" --user-data-dir="' + otherUserDataRoot
                + '" --remote-debugging-port=' + port },
          ]) };
        }
        throw new Error("unexpected PowerShell observation");
      };
      try {
        const attestation = attestLoopbackCdpEndpoint({ port, runtimePid,
          expectedUserDataRoot: userDataRoot, expectedExecutableName: "msedgewebview2.exe" });
        assert.strictEqual(attestation.listenerPid, ipv4Pid);
        assert.strictEqual(attestation.listenerLocalAddress, "127.0.0.1");
        assert.deepStrictEqual(attestation.ancestorPids, [ipv4Pid, runtimePid]);
        assert.strictEqual(calls, 2);
      } finally {
        childProcess.spawnSync = originalSpawnSync;
      }
    });
    await test("runtime CDP binding is PID-exact", async () => {
      const identity = { pid: 4200 };
      const userDataRoot = "C:\\fixture\\webview-profile";
      const executablePath = "C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application\\fixture\\msedgewebview2.exe";
      const pageIdentity = { url: "https://overlay.local/overlay.html", origin: "https://overlay.local",
        timeOrigin: 1, readyState: "complete", userAgent: "fixture" };
      const binding = { port: 19445, runtimePid: 4200, exclusiveBeforeLaunch: true,
        configurationSource: "CF7_WEBVIEW2_ARGS", developerMode: true,
        expectedPageUrl: "https://overlay.local/overlay.html",
        allocatedAt: "2026-08-03T00:00:00.000Z",
        pageIdentity,
        pageIdentitySha256: sha256Text(canonicalJson(pageIdentity)),
        pageContentSha256: "c".repeat(64),
        pageContentBytes: 1234,
        pageContentCapturedAt: "2026-08-03T00:00:01.000Z",
        attestation: {
          observedAt: "2026-08-03T00:00:01.000Z",
          port: 19445,
          runtimePid: 4200,
          listenerPid: 4300,
          ancestorPids: [4300, 4200],
          listenerExecutablePath: executablePath,
          commandLineSha256: "b".repeat(64),
          argvSha256: "a".repeat(64),
          exactPortArgument: true,
          exactUserDataRoot: true,
          userDataRoot,
          listenerExecutable: "msedgewebview2.exe",
        } };
      const trusted = { expectedPageUrl: "https://overlay.local/overlay.html",
        expectedPageOrigin: "https://overlay.local", expectedUserDataRoot: userDataRoot,
        expectedListenerExecutableName: "msedgewebview2.exe",
        expectedListenerExecutablePath: executablePath,
        expectedPageContentSha256: "c".repeat(64), expectedPageContentBytes: 1234 };
      assert.strictEqual(assertRuntimeCdpBinding(binding, identity, trusted), binding);
      assert.throws(() => assertRuntimeCdpBinding(binding, identity),
        (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(Object.assign({}, binding, { runtimePid: 1 }),
        identity, trusted),
        (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(Object.assign({}, binding, {
        attestation: Object.assign({}, binding.attestation, { exactUserDataRoot: false }),
      }), identity, trusted), (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(Object.assign({}, binding, {
        attestation: Object.assign({}, binding.attestation, { listenerExecutable: "evil.exe" }),
      }), identity, trusted), (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(Object.assign({}, binding, {
        pageContentSha256: "d".repeat(63),
      }), identity, trusted), (error) => error && error.code === "cdp_runtime_binding_invalid");
      const fakePageIdentity = Object.assign({}, pageIdentity, {
        url: "https://attacker.invalid/fake.html", origin: "https://attacker.invalid" });
      const fakePage = Object.assign({}, binding, {
        expectedPageUrl: fakePageIdentity.url, pageIdentity: fakePageIdentity,
        pageIdentitySha256: sha256Text(canonicalJson(fakePageIdentity)) });
      assert.throws(() => assertRuntimeCdpBinding(fakePage, identity, trusted),
        (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(binding, identity,
        Object.assign({}, trusted, { expectedPageOrigin: "https://attacker.invalid" })),
      (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(binding, identity,
        Object.assign({}, trusted, { expectedUserDataRoot: "C:\\attacker-profile" })),
      (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(binding, identity,
        Object.assign({}, trusted, { expectedListenerExecutableName: "evil.exe" })),
      (error) => error && error.code === "cdp_runtime_binding_invalid");
      assert.throws(() => assertRuntimeCdpBinding(binding, identity,
        Object.assign({}, trusted, { expectedListenerExecutablePath:
          "C:\\tmp\\msedgewebview2.exe" })),
      (error) => error && error.code === "cdp_runtime_binding_invalid");
    });
    await test("byte invariant is exact", async () => {
      assert.deepStrictEqual(assertByteInvariant({ sha256: "a", bytes: 1 },
        { sha256: "a", bytes: 1 }), { sha256: "a", bytes: 1 });
      assert.throws(() => assertByteInvariant({ sha256: "a", bytes: 1 },
        { sha256: "b", bytes: 1 }), (error) => error && error.code === "byte_invariant_changed");
    });
    await test("OS assigns a bounded exclusive loopback CDP port", async () => {
      const binding = await allocateLoopbackCdpPort();
      assert.ok(binding.port >= 1024 && binding.port <= 65535);
      assert.strictEqual(binding.exclusiveBeforeLaunch, true);
    });
    await test("browser child resource closure binds exact served bytes and executable", async () => {
      const browserRoot = path.join(root, "browser-root");
      fs.mkdirSync(path.join(browserRoot, "nested"), { recursive:true });
      fs.writeFileSync(path.join(browserRoot, "a.js"), "window.a=1;", "utf8");
      fs.writeFileSync(path.join(browserRoot, "nested", "b.css"), ".b{}", "utf8");
      const inventory = BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
        inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
          files:["a.js", "nested/b.css"] } });
      const ledger = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      const first = ledger.begin("/a.js?first=1", path.join(browserRoot, "a.js"));
      first.success(fs.readFileSync(path.join(browserRoot, "a.js")), "text/javascript");
      const second = ledger.begin("/nested/b.css", path.join(browserRoot, "nested", "b.css"));
      second.success(fs.readFileSync(path.join(browserRoot, "nested", "b.css")), "text/css");
      const repeated = ledger.begin("/a.js?again=1", path.join(browserRoot, "a.js"));
      repeated.success(fs.readFileSync(path.join(browserRoot, "a.js")), "text/javascript");
      const receipt = BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory, ledger:ledger.snapshot() });
      assert.strictEqual(receipt.resourceCount, 2);
      assert.strictEqual(receipt.occurrenceCount, 3);
      assert(/^[a-f0-9]{64}$/.test(receipt.evidenceSha256));
      const executable = BrowserChildResourceClosure.browserExecutableReceipt({
        expectedPath:source, launchedPath:source });
      assert.strictEqual(executable.bytes, fs.statSync(source).size);
      assert(/^[a-f0-9]{64}$/.test(executable.sha256));
      assert.strictEqual(BrowserChildResourceClosure.resourceManifestEntries(inventory).length, 2);
      const optionalInventory = BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
        inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
          files:["a.js"], optionalFiles:["nested/b.css"] } });
      const optionalLedger = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      optionalLedger.begin("/a.js", path.join(browserRoot, "a.js"))
        .success(fs.readFileSync(path.join(browserRoot, "a.js")), "text/javascript");
      const optionalReceipt = BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory:optionalInventory, ledger:optionalLedger.snapshot() });
      assert.deepStrictEqual({ observed:optionalReceipt.resourceCount,
        required:optionalReceipt.requiredResourceCount,
        allowed:optionalReceipt.allowedResourceCount }, { observed:1, required:1, allowed:2 });
    });
    await test("browser child resource closure rejects malformed, incomplete, and drifting evidence", async () => {
      const browserRoot = path.join(root, "browser-negative");
      fs.mkdirSync(browserRoot, { recursive:true });
      const firstPath = path.join(browserRoot, "a.js");
      const secondPath = path.join(browserRoot, "b.js");
      fs.writeFileSync(firstPath, "a", "utf8");
      fs.writeFileSync(secondPath, "b", "utf8");
      assert.throws(() => BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
        inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
          files:["b.js", "a.js"] } }), (error) => error.code === "browser_resource_inventory_invalid");
      assert.throws(() => BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
        inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
          files:["../escape.js"] } }), (error) => error.code === "browser_resource_path_invalid");
      const pending = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      pending.begin("/a.js", firstPath);
      assert.throws(() => pending.snapshot(),
        (error) => error.code === "browser_resource_occurrence_incomplete");
      const inventory = BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
        inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
          files:["a.js", "b.js"] } });
      const wrongRoute = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      assert.throws(() => wrongRoute.begin("/b.js", firstPath),
        (error) => error.code === "browser_resource_route_mismatch");
      const incomplete = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      incomplete.begin("/a.js", firstPath).success(Buffer.from("a"), "text/javascript");
      const incompleteArtifact = incomplete.snapshot();
      assert.throws(() => BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory, ledger:incompleteArtifact }),
      (error) => error.code === "browser_resource_exact_set_mismatch");
      const complete = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
      complete.begin("/a.js", firstPath).success(Buffer.from("a"), "text/javascript");
      complete.begin("/b.js", secondPath).success(Buffer.from("b"), "text/javascript");
      const completeArtifact = complete.snapshot();
      const resealedRoute = JSON.parse(JSON.stringify(completeArtifact));
      resealedRoute.occurrences[0].requestPath = "/b.js?wrong-target=1";
      delete resealedRoute.evidenceSha256;
      resealedRoute.evidenceSha256 = sha256Text(canonicalJson(resealedRoute));
      assert.throws(() => BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory, ledger:resealedRoute }),
      (error) => error.code === "browser_resource_route_mismatch");
      const resealedProjection = JSON.parse(JSON.stringify(completeArtifact));
      resealedProjection.occurrences[1] = Object.assign({}, resealedProjection.occurrences[0], {
        sequence:2, requestPath:"/a.js?second-occurrence=1",
      });
      delete resealedProjection.evidenceSha256;
      resealedProjection.evidenceSha256 = sha256Text(canonicalJson(resealedProjection));
      assert.throws(() => BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory, ledger:resealedProjection }),
      (error) => error.code === "browser_resource_ledger_resource_projection_invalid");
      fs.writeFileSync(secondPath, "changed", "utf8");
      assert.throws(() => BrowserChildResourceClosure.verifyServedResourceClosure({
        root:browserRoot, inventory, ledger:completeArtifact }),
      (error) => error.code === "browser_resource_exact_set_mismatch");
      assert.throws(() => BrowserChildResourceClosure.browserExecutableReceipt({
        expectedPath:firstPath, launchedPath:secondPath }),
      (error) => error.code === "browser_executable_path_mismatch");
      const outsideRoot = path.join(path.dirname(root), path.basename(root) + "-outside");
      const linked = path.join(browserRoot, "linked");
      try {
        fs.mkdirSync(outsideRoot, { recursive:true });
        fs.writeFileSync(path.join(outsideRoot, "escape.js"), "outside", "utf8");
        fs.symlinkSync(outsideRoot, linked, process.platform === "win32" ? "junction" : "dir");
        assert.throws(() => BrowserChildResourceClosure.loadResourceInventory({ root:browserRoot,
          inventory:{ schema:BrowserChildResourceClosure.INVENTORY_SCHEMA,
            files:["linked/escape.js"] } }),
        (error) => error.code === "browser_resource_link_component"
          || error.code === "browser_resource_realpath_escape");
        const linkedLedger = BrowserChildResourceClosure.createServedResourceLedger({ root:browserRoot });
        assert.throws(() => linkedLedger.begin("/linked/escape.js",
          path.join(linked, "escape.js")),
        (error) => error.code === "browser_resource_link_component"
          || error.code === "browser_resource_realpath_escape");
      } finally {
        try { fs.unlinkSync(linked); } catch (_) {}
        fs.rmSync(outsideRoot, { recursive:true, force:true });
      }
    });
    return { passed };
  } finally {
    const tempRoot = path.resolve(os.tmpdir());
    if (path.dirname(root) === tempRoot && path.basename(root).startsWith("cf7-live-e2e-lib-")) {
      fs.rmSync(root, { recursive: true, force: true });
    }
  }
}

module.exports = { runSelfTests };

if (require.main === module) {
  runSelfTests().then((result) => {
    console.log("Workbench live-E2E shared self-tests passed: " + result.passed + "/" + result.passed);
  }).catch((error) => {
    console.error(error.stack || error.message);
    process.exit(1);
  });
}
