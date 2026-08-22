#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const sourcePath = path.join(root, "scripts", "compile_action.jsfl");
const source = fs.readFileSync(sourcePath, "utf8");
const compileTestSource = fs.readFileSync(
  path.join(root, "scripts", "compile_test.ps1"),
  "utf8",
);

function uriToPlatformPath(uri) {
  const decoded = decodeURI(String(uri));
  return decoded
    .replace(/^file:\/\/\/([A-Za-z])\|\//, "$1:/")
    .replace(/\//g, "\\");
}

function platformPathToURI(platformPath) {
  const slashPath = String(platformPath).replace(/\\/g, "/");
  const driveUri = slashPath.replace(/^([A-Za-z]):\//, "$1|/");
  return `file:///${encodeURI(driveUri)}`;
}

function runHarness(options = {}) {
  const projectURI = "file:///C|/Program Files (x86)/CF7/resources";
  const targetURI = `${projectURI}/scripts/asLoader/asLoader.xfl`;
  const canonicalTargetURI = platformPathToURI(uriToPlatformPath(targetURI));
  const configPath = "file:///flash-config/Commands/flash_project_path.cfg";
  const targetCfg = `${projectURI}/scripts/compile_target.cfg`;
  const modeCfg = `${projectURI}/scripts/compile_mode.cfg`;
  const quitCfg = `${projectURI}/scripts/compile_quit_after_publish.cfg`;
  const doneMarker = `${projectURI}/scripts/publish_done.marker`;
  const errorMarker = `${projectURI}/scripts/publish_error.marker`;
  const reopenMarker = `${projectURI}/scripts/compile_reopen.marker`;
  const outputLog = `${projectURI}/scripts/compile_output.txt`;
  const compilerErrorsLog = `${projectURI}/scripts/compiler_errors.txt`;

  const files = new Map([
    [configPath, projectURI],
    [targetCfg, targetURI],
    [modeCfg, options.compileMode || "publish"],
    [targetURI, "PROXY-CS5"],
    [canonicalTargetURI, "PROXY-CS5"],
  ]);
  if (options.quitAfterPublish) files.set(quitCfg, "quit");
  const traces = [];
  const opened = [];
  const closed = [];
  const outputSaves = [];
  const published = [];
  const tested = [];
  const quitCalls = [];

  const document = {
    name: "asLoader.xfl",
    pathURI: canonicalTargetURI,
    publish() {
      published.push(this.name);
    },
    testMovie() {
      tested.push(this.name);
    },
  };

  const foreignDocument = {
    name: "素材库-物品技能图标.xfl*",
    pathURI: `${projectURI}/flashswf/arts/素材库-物品技能图标.xfl`,
  };

  const initialDocuments = options.initialDocuments === false ? [] : [document];
  if (options.includeForeignDocument) initialDocuments.unshift(foreignDocument);

  const fl = {
    configURI: "file:///flash-config/",
    documents: initialDocuments,
    outputPanel: {
      clear() {},
      save(uri) {
        outputSaves.push(uri);
        files.set(uri, traces.join("\n"));
      },
    },
    compilerErrors: {
      clear() {},
      save(uri) {
        files.set(uri, "0 errors, 0 warnings");
      },
    },
    trace(message) {
      traces.push(String(message));
    },
    closeDocument(doc) {
      closed.push(doc.pathURI);
      const index = this.documents.indexOf(doc);
      if (index >= 0) this.documents.splice(index, 1);
    },
    openDocument(uri) {
      opened.push(uri);
      if (options.throwOnOpen) throw new Error("simulated openDocument failure");
      if (/\s/.test(uri)) throw new Error(`raw whitespace in URI: ${uri}`);
      this.documents.push(document);
      return document;
    },
    getDocumentDOM() {
      return this.documents[0] || null;
    },
    quit(saveChanges) {
      quitCalls.push(saveChanges);
    },
  };

  const FLfile = {
    read(uri) {
      return files.get(uri) || "";
    },
    write(uri, value) {
      files.set(uri, String(value));
      return true;
    },
    exists(uri) {
      return files.has(uri);
    },
    remove(uri) {
      return files.delete(uri);
    },
    uriToPlatformPath,
    platformPathToURI,
  };

  vm.runInNewContext(source, {
    fl,
    FLfile,
    encodeURI,
    decodeURI,
    parseInt,
  }, { filename: sourcePath });

  return {
    files,
    traces,
    opened,
    closed,
    outputSaves,
    published,
    tested,
    quitCalls,
    canonicalTargetURI,
    doneMarker,
    errorMarker,
    reopenMarker,
    outputLog,
    compilerErrorsLog,
  };
}

function testTwoPhaseCanonicalOpenAndPublish() {
  const closePhase = runHarness();
  assert.deepEqual(closePhase.opened, []);
  assert.equal(closePhase.closed.length, 1);
  assert.deepEqual(closePhase.published, []);
  assert.equal(closePhase.files.has(closePhase.doneMarker), false);
  assert.match(closePhase.files.get(closePhase.reopenMarker), /asLoader\.xfl\npublish$/);

  const publishPhase = runHarness({
    initialDocuments: false,
    includeForeignDocument: true,
  });
  assert.deepEqual(publishPhase.opened, [publishPhase.canonicalTargetURI]);
  assert.match(publishPhase.opened[0], /Program%20Files/);
  assert.doesNotMatch(publishPhase.opened[0], /\s/);
  assert.deepEqual(publishPhase.closed, [publishPhase.canonicalTargetURI]);
  assert.deepEqual(publishPhase.published, ["asLoader.xfl"]);
  assert.deepEqual(publishPhase.tested, []);
  assert.deepEqual(publishPhase.quitCalls, []);
  assert.equal(publishPhase.files.get(publishPhase.doneMarker), "ok");
  assert.equal(publishPhase.files.has(publishPhase.errorMarker), false);
  assert.equal(publishPhase.files.get(publishPhase.compilerErrorsLog), "0 errors, 0 warnings");
  assert.ok(publishPhase.outputSaves.includes(publishPhase.outputLog));
}

function testExplicitQuitRunsAfterSuccessfulPublish() {
  const quitPhase = runHarness({
    initialDocuments: false,
    quitAfterPublish: true,
  });
  assert.deepEqual(quitPhase.published, ["asLoader.xfl"]);
  assert.deepEqual(quitPhase.closed, [quitPhase.canonicalTargetURI]);
  assert.equal(quitPhase.files.get(quitPhase.doneMarker), "ok");
  assert.deepEqual(quitPhase.quitCalls, [false]);
  assert.match(quitPhase.files.get(quitPhase.outputLog), /quit Flash after completed publish/);
}

function testMovieKeepsDebugTargetOpen() {
  const testPhase = runHarness({
    initialDocuments: false,
    compileMode: "test",
  });
  assert.deepEqual(testPhase.opened, [testPhase.canonicalTargetURI]);
  assert.deepEqual(testPhase.published, []);
  assert.deepEqual(testPhase.tested, ["asLoader.xfl"]);
  assert.deepEqual(testPhase.closed, []);
  assert.equal(testPhase.files.get(testPhase.doneMarker), "ok");
}

function testOpenFailureTerminatesImmediately() {
  const result = runHarness({ throwOnOpen: true, initialDocuments: false });
  assert.equal(result.files.has(result.doneMarker), false);
  assert.match(result.files.get(result.errorMarker), /phase=open_target_from_disk/);
  assert.match(result.files.get(result.errorMarker), /simulated openDocument failure/);
  assert.ok(result.outputSaves.includes(result.outputLog));
}

function testPowerShellHandshakeIsBounded() {
  assert.doesNotMatch(source, /FLfile\.uriToPlatformPath\s*\(/);
  assert.match(compileTestSource, /compile_reopen\.marker/);
  assert.match(compileTestSource, /\$reopenRequestCount -ge 1/);
  assert.match(compileTestSource, /\$reopenTargetUri -ceq \$targetUri/);
  assert.match(compileTestSource, /JSFL 已关闭目标；触发二阶段重开/);
  assert.match(compileTestSource, /QuitFlashAfterPublish/);
  assert.match(compileTestSource, /compile_quit_after_publish\.cfg/);
}

testTwoPhaseCanonicalOpenAndPublish();
testExplicitQuitRunsAfterSuccessfulPublish();
testMovieKeepsDebugTargetOpen();
testOpenFailureTerminatesImmediately();
testPowerShellHandshakeIsBounded();
console.log("[flash-compile-jsfl] ok 5/5");
