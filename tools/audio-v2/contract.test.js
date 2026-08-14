#!/usr/bin/env node

"use strict";

var assert = require("assert");
var cp = require("child_process");
var fs = require("fs");
var os = require("os");
var path = require("path");
var validator = require("./validate-contract.js");

var ROOT = path.resolve(__dirname, "../..");
var manifestBytes = fs.readFileSync(path.join(ROOT, validator.MANIFEST_PATH));
var manifest = validator.parseJsonBuffer(manifestBytes, "manifest fixture");
var r3ManifestBytes = fs.readFileSync(path.join(ROOT, validator.R3_MANIFEST_PATH));
var r3Manifest = validator.parseJsonBuffer(r3ManifestBytes, "R3 manifest fixture");
var r4ManifestBytes = fs.readFileSync(path.join(ROOT, validator.R4_MANIFEST_PATH));
var r4Manifest = validator.parseJsonBuffer(r4ManifestBytes, "R4 manifest fixture");
var r5ManifestBytes = fs.readFileSync(path.join(ROOT, validator.R5_MANIFEST_PATH));
var r5Manifest = validator.parseJsonBuffer(r5ManifestBytes, "R5 manifest fixture");

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function leaves(value, prefix, output) {
    output = output || [];
    prefix = prefix || [];
    if (Array.isArray(value)) {
        value.forEach(function (entry, index) { leaves(entry, prefix.concat(index), output); });
    } else if (value && typeof value === "object") {
        Object.keys(value).forEach(function (key) { leaves(value[key], prefix.concat(key), output); });
    } else {
        output.push(prefix);
    }
    return output;
}

function setAt(value, parts, replacement) {
    var cursor = value;
    for (var index = 0; index < parts.length - 1; index++) cursor = cursor[parts[index]];
    cursor[parts[parts.length - 1]] = replacement;
}

function mutate(value) {
    if (typeof value === "string") return value + "__mutation";
    if (typeof value === "number") return value + 1;
    if (typeof value === "boolean") return !value;
    if (value === null) return "not-null";
    throw new Error("unsupported leaf mutation");
}

function getAt(value, parts) {
    return parts.reduce(function (cursor, part) { return cursor[part]; }, value);
}

function expectThrows(fn, pattern) {
    var thrown = null;
    try { fn(); } catch (error) { thrown = error; }
    assert(thrown, "expected function to throw");
    if (pattern) assert(pattern.test(thrown.message), "unexpected error: " + thrown.message);
}

function testAllLeafMutationsInvalidateDigest() {
    var acceptedDigest = validator.sha256(validator.canonicalBytes(manifest));
    var proposal = {
        bindings: {},
        commit: "1".repeat(40),
        manifest: manifest,
        tree: "2".repeat(40)
    };
    proposal.bindings[validator.MANIFEST_PATH] = { blobOid: "3".repeat(40), sha256: acceptedDigest };
    proposal.bindings[validator.ADR_PATH] = { blobOid: "4".repeat(40) };
    proposal.bindings["tools/audio-v2/validate-contract.js"] = { blobOid: "5".repeat(40) };
    proposal.bindings["tools/audio-v2/contract.test.js"] = { blobOid: "6".repeat(40) };
    var receipt = {
        authorization: { deploymentState: "NOT_DEPLOYED", phases: ["A1", "A2", "A3", "A4", "A5", "A6"], promotionAuthorized: false },
        contract: {
            adrBlobOid: "4".repeat(40),
            adrPath: validator.ADR_PATH,
            manifestBlobOid: "3".repeat(40),
            manifestPath: validator.MANIFEST_PATH,
            manifestSha256: acceptedDigest,
            proposalCommit: proposal.commit,
            proposalTree: proposal.tree,
            testBlobOid: "6".repeat(40),
            testPath: "tools/audio-v2/contract.test.js",
            validatorBlobOid: "5".repeat(40),
            validatorPath: "tools/audio-v2/validate-contract.js"
        },
        decision: "accepted",
        recordedAtUtc: "2026-08-09T00:00:00Z",
        reviewer: {
            channel: "test",
            role: "human-maintainer",
            verbatim: [
                "H1_IMPLEMENTATION_ACCEPTANCE",
                "scopeRevision=" + manifest.scopeRevision,
                "proposalCommit=" + proposal.commit,
                "proposalTree=" + proposal.tree,
                "manifestPath=" + validator.MANIFEST_PATH,
                "manifestSha256=" + acceptedDigest,
                "promotionAuthorized=false",
                "decision=accepted"
            ].join("\n")
        },
        schema: "cf7.audio-v2.h1-implementation-acceptance.v2",
        scopeRevision: manifest.scopeRevision
    };
    validator.validateReceiptBinding(receipt, proposal);
    var rejectionWrapped = clone(receipt);
    rejectionWrapped.reviewer.verbatim = "I REJECT THIS\ndecision=rejected\n\n" + receipt.reviewer.verbatim;
    expectThrows(function () { validator.validateReceiptBinding(rejectionWrapped, proposal); }, /must equal/);
    var invalidMetadata = clone(receipt);
    invalidMetadata.recordedAtUtc = "not-a-time";
    invalidMetadata.reviewer.channel = "";
    expectThrows(function () { validator.validateReceiptBinding(invalidMetadata, proposal); });
    var paths = leaves(manifest);
    assert(paths.length > 250, "manifest leaf coverage unexpectedly small");
    paths.forEach(function (leafPath) {
        var changed = clone(manifest);
        setAt(changed, leafPath, mutate(getAt(changed, leafPath)));
        var changedDigest = validator.sha256(validator.canonicalBytes(changed));
        assert.notStrictEqual(changedDigest, acceptedDigest, "mutation did not invalidate digest: " + leafPath.join("."));
        expectThrows(function () { validator.validateManifest(changed); });
        var changedProposal = Object.assign({}, proposal, { bindings: Object.assign({}, proposal.bindings), manifest: changed });
        changedProposal.bindings[validator.MANIFEST_PATH] = { blobOid: "7".repeat(40), sha256: changedDigest };
        expectThrows(function () { validator.validateReceiptBinding(receipt, changedProposal); });
    });
}

function makeH1Receipt(proposal, profile) {
    var manifestBinding = proposal.bindings[profile.manifestPath];
    return {
        authorization: { deploymentState: "NOT_DEPLOYED", phases: ["A1", "A2", "A3", "A4", "A5", "A6"], promotionAuthorized: false },
        contract: {
            adrBlobOid: proposal.bindings[validator.ADR_PATH].blobOid,
            adrPath: validator.ADR_PATH,
            manifestBlobOid: manifestBinding.blobOid,
            manifestPath: profile.manifestPath,
            manifestSha256: manifestBinding.sha256,
            proposalCommit: proposal.commit,
            proposalTree: proposal.tree,
            testBlobOid: proposal.bindings["tools/audio-v2/contract.test.js"].blobOid,
            testPath: "tools/audio-v2/contract.test.js",
            validatorBlobOid: proposal.bindings["tools/audio-v2/validate-contract.js"].blobOid,
            validatorPath: "tools/audio-v2/validate-contract.js"
        },
        decision: "accepted",
        recordedAtUtc: "2026-08-13T00:00:00Z",
        reviewer: { channel: "test", role: "human-maintainer", verbatim: validator.formatH1Proposal(proposal) },
        schema: profile.h1ReceiptSchema,
        scopeRevision: profile.scopeRevision
    };
}

function testR3AllLeafMutationsFailClosed() {
    assert.deepStrictEqual(r3ManifestBytes, validator.canonicalBytes(r3Manifest));
    assert.strictEqual(validator.sha256(r3ManifestBytes), validator.R3_EXPECTED_MANIFEST_SHA256);
    validator.validateManifest(r3Manifest, validator.R3_PROFILE);
    var paths = leaves(r3Manifest);
    assert(paths.length > leaves(manifest).length, "R3 manifest must add governed leaves");
    paths.forEach(function (leafPath) {
        var changed = clone(r3Manifest);
        setAt(changed, leafPath, mutate(getAt(changed, leafPath)));
        expectThrows(function () { validator.validateManifest(changed, validator.R3_PROFILE); });
    });
    var mockProposal = {
        bindings: {}, commit: "a".repeat(40), manifest: r3Manifest,
        profile: validator.R3_PROFILE, tree: "b".repeat(40)
    };
    mockProposal.bindings[validator.R3_MANIFEST_PATH] = { blobOid: "c".repeat(40), sha256: validator.R3_EXPECTED_MANIFEST_SHA256 };
    mockProposal.bindings[validator.ADR_PATH] = { blobOid: "d".repeat(40) };
    mockProposal.bindings["tools/audio-v2/validate-contract.js"] = { blobOid: "e".repeat(40) };
    mockProposal.bindings["tools/audio-v2/contract.test.js"] = { blobOid: "f".repeat(40) };
    var receipt = makeH1Receipt(mockProposal, validator.R3_PROFILE);
    validator.validateReceiptBinding(receipt, mockProposal);
    var oldSchema = clone(receipt);
    oldSchema.schema = "cf7.audio-v2.h1-implementation-acceptance.v2";
    expectThrows(function () { validator.validateReceiptBinding(oldSchema, mockProposal); }, /unexpected H1 receipt schema/);
    var wrapped = clone(receipt);
    wrapped.reviewer.verbatim = "accepted\n" + wrapped.reviewer.verbatim;
    expectThrows(function () { validator.validateReceiptBinding(wrapped, mockProposal); }, /must equal/);
}

function testR4AllLeafMutationsFailClosed() {
    assert.deepStrictEqual(r4ManifestBytes, validator.canonicalBytes(r4Manifest));
    assert.strictEqual(validator.sha256(r4ManifestBytes), validator.R4_EXPECTED_MANIFEST_SHA256);
    validator.validateManifest(r4Manifest, validator.R4_PROFILE);
    var paths = leaves(r4Manifest);
    assert(paths.length > leaves(r3Manifest).length, "R4 manifest must add governed leaves");
    paths.forEach(function (leafPath) {
        var changed = clone(r4Manifest);
        setAt(changed, leafPath, mutate(getAt(changed, leafPath)));
        expectThrows(function () { validator.validateManifest(changed, validator.R4_PROFILE); });
    });
    var mockProposal = {
        bindings: {}, commit: "1".repeat(40), manifest: r4Manifest,
        profile: validator.R4_PROFILE, tree: "2".repeat(40)
    };
    mockProposal.bindings[validator.R4_MANIFEST_PATH] = { blobOid: "3".repeat(40), sha256: validator.R4_EXPECTED_MANIFEST_SHA256 };
    mockProposal.bindings[validator.ADR_PATH] = { blobOid: "4".repeat(40) };
    mockProposal.bindings["tools/audio-v2/validate-contract.js"] = { blobOid: "5".repeat(40) };
    mockProposal.bindings["tools/audio-v2/contract.test.js"] = { blobOid: "6".repeat(40) };
    var receipt = makeH1Receipt(mockProposal, validator.R4_PROFILE);
    validator.validateReceiptBinding(receipt, mockProposal);
    var oldSchema = clone(receipt);
    oldSchema.schema = "cf7.audio-v2.h1-implementation-acceptance.v3";
    expectThrows(function () { validator.validateReceiptBinding(oldSchema, mockProposal); }, /unexpected H1 receipt schema/);
}

function testR5AllLeafMutationsFailClosed() {
    assert.deepStrictEqual(r5ManifestBytes, validator.canonicalBytes(r5Manifest));
    assert.strictEqual(validator.sha256(r5ManifestBytes), validator.R5_EXPECTED_MANIFEST_SHA256);
    validator.validateManifest(r5Manifest, validator.R5_PROFILE);
    var paths = leaves(r5Manifest);
    assert(paths.length > leaves(r4Manifest).length, "R5 manifest must add governed leaves");
    paths.forEach(function (leafPath) {
        var changed = clone(r5Manifest);
        setAt(changed, leafPath, mutate(getAt(changed, leafPath)));
        expectThrows(function () { validator.validateManifest(changed, validator.R5_PROFILE); });
    });
    var mockProposal = {
        bindings: {}, commit: "7".repeat(40), manifest: r5Manifest,
        profile: validator.R5_PROFILE, tree: "8".repeat(40)
    };
    mockProposal.bindings[validator.R5_MANIFEST_PATH] = { blobOid: "9".repeat(40), sha256: validator.R5_EXPECTED_MANIFEST_SHA256 };
    mockProposal.bindings[validator.ADR_PATH] = { blobOid: "a".repeat(40) };
    mockProposal.bindings["tools/audio-v2/validate-contract.js"] = { blobOid: "b".repeat(40) };
    mockProposal.bindings["tools/audio-v2/contract.test.js"] = { blobOid: "c".repeat(40) };
    var receipt = makeH1Receipt(mockProposal, validator.R5_PROFILE);
    validator.validateReceiptBinding(receipt, mockProposal);
    var oldSchema = clone(receipt);
    oldSchema.schema = "cf7.audio-v2.h1-implementation-acceptance.v4";
    expectThrows(function () { validator.validateReceiptBinding(oldSchema, mockProposal); }, /unexpected H1 receipt schema/);
}

function testRuntimePayloadOrdinalOracle() {
    var rows = [
        { bytes: 55, path: "runtime/libHarfBuzzSharp.dll", sha256: "E".repeat(64) },
        { bytes: 33, path: "runtime/ClearScript.Core.dll", sha256: "C".repeat(64) },
        { bytes: 11, path: "CRAZYFLASHER7MercenaryEmpire.exe", sha256: "A".repeat(64) },
        { bytes: 66, path: "runtime/miniaudio.dll", sha256: "F".repeat(64) },
        { bytes: 44, path: "runtime/THIRD-PARTY-NOTICES.txt", sha256: "D".repeat(64) },
        { bytes: 22, path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", sha256: "B".repeat(64) }
    ];
    var expectedOrdinalPaths = [
        "CRAZYFLASHER7MercenaryEmpire.exe",
        "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll",
        "runtime/ClearScript.Core.dll",
        "runtime/THIRD-PARTY-NOTICES.txt",
        "runtime/libHarfBuzzSharp.dll",
        "runtime/miniaudio.dll"
    ];
    var ordinalClosure = "E6E6F5527FF8175EDEF69D1F942B37CB0FA1665A4E7399B487D1B83AAC981202";
    var zhCnLocaleClosure = "11C334EB971A61FD1403C6F8639EE31C9EB31CCF15A45BD715BAFA2B20B7BE9B";
    assert.strictEqual(validator.runtimePayloadClosureHash(rows), ordinalClosure);
    var localeRows = rows.slice().sort(function (left, right) { return left.path.localeCompare(right.path, "zh-CN"); });
    assert.notDeepStrictEqual(localeRows.map(function (row) { return row.path; }), expectedOrdinalPaths);
    var localeCanonical = localeRows.map(function (row) { return row.path + "\t" + row.bytes + "\t" + row.sha256; }).join("\n") + "\n";
    assert.strictEqual(validator.sha256(Buffer.from(localeCanonical, "utf8")), zhCnLocaleClosure);
    assert.notStrictEqual(ordinalClosure, zhCnLocaleClosure);

    var artifactSourceHash = "1".repeat(64);
    var producerRecipeHash = "2".repeat(64);
    var toolchainLockHash = "3".repeat(64);
    var identity = validator.runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash);
    var manifestText = [
        "cf7-runtime-manifest-v2",
        "publishMode\tframework-dependent",
        "artifactSourceHash\t" + artifactSourceHash,
        "producerRecipeHash\t" + producerRecipeHash,
        "toolchainLockHash\t" + toolchainLockHash,
        "toolchainBaseline\ttest-locked",
        "buildIdentityHash\t" + identity,
        "payloadClosureHash\t" + ordinalClosure
    ].concat(localeRows.map(function (row) { return "file\t" + row.path + "\t" + row.bytes + "\t" + row.sha256; })).join("\n") + "\n";
    var manifestBuffer = Buffer.from(manifestText, "utf8");
    expectThrows(function () {
        validator.validateCandidateManifestBytes(manifestBuffer, {
            buildIdentity: identity,
            coreBytes: 22,
            coreSha256: "B".repeat(64),
            manifestBytes: manifestBuffer.length,
            manifestSha256: validator.sha256(manifestBuffer),
            miniaudioBytes: 66,
            miniaudioSha256: "F".repeat(64),
            payloadClosure: ordinalClosure
        });
    }, /canonical ordinal order/);
}

function testCanonicalEncodingGuards() {
    assert.deepStrictEqual(manifestBytes, validator.canonicalBytes(manifest));
    expectThrows(function () { validator.parseJsonBuffer(Buffer.concat([Buffer.from([0xEF, 0xBB, 0xBF]), manifestBytes]), "BOM"); }, /BOM/);
    expectThrows(function () { validator.parseJsonBuffer(Buffer.from(manifestBytes.toString("utf8").replace(/\n/g, "\r\n")), "CRLF"); }, /CRLF/);
}

function testStructuralDriftGuards() {
    var extra = clone(manifest);
    extra.unexpected = true;
    expectThrows(function () { validator.validateManifest(extra); }, /keys differ/);
    var missing = clone(manifest);
    delete missing.backend;
    expectThrows(function () { validator.validateManifest(missing); }, /keys differ/);
    var wrongType = clone(manifest);
    wrongType.authorization.promotionAuthorized = "false";
    expectThrows(function () { validator.validateManifest(wrongType); }, /must not authorize promotion/);
    var stale = clone(manifest);
    stale.generation.staleRule = "allow_side_effect";
    expectThrows(function () { validator.validateManifest(stale); }, /zero side effects/);
}

function testRevisionSchemaSurfaceBindings() {
    validator.validateSchemaSurfaces(ROOT, validator.R2_PROFILE);
    validator.validateSchemaSurfaces(ROOT, validator.R3_PROFILE);
    validator.validateSchemaSurfaces(ROOT, validator.R4_PROFILE);
    validator.validateSchemaSurfaces(ROOT, validator.R5_PROFILE);
    expectThrows(function () {
        validator.validateSchemaSurfaces(ROOT, Object.assign({}, validator.R3_PROFILE, { manifestSchemaId: "cf7.audio-v2.h1-decision-manifest.schema.r3" }));
    }, /contract schema IDs drift/);
    expectThrows(function () {
        validator.validateSchemaSurfaces(ROOT, Object.assign({}, validator.R3_PROFILE, { h1SchemaId: "cf7.audio-v2.h1-implementation-acceptance.schema.r3" }));
    }, /contract schema IDs drift/);
}

function testRecoveryStateGuards() {
    var expected = {
        markers: ["H1_STATE=pending", "H2_STATE=not_applicable_before_A6"],
        state: "PROPOSED / HUMAN_ACCEPTANCE_REQUIRED / IMPLEMENTATION_BLOCKED / NOT_DEPLOYED"
    };
    var valid = "# ADR\n\n**状态**：`" + expected.state + "`。\n\n**机器恢复标记**：`H1_STATE=pending`；`H2_STATE=not_applicable_before_A6`。\n";
    validator.validateTopRecoveryState(valid, expected, "test ADR");
    expectThrows(function () {
        validator.validateTopRecoveryState(valid + "\n**状态**：`ACCEPTED / IMPLEMENTATION_AUTHORIZED_A1_A6 / PROMOTION_BLOCKED / NOT_DEPLOYED`。\n", expected, "contradictory ADR");
    }, /exactly one top-level state line/);
    expectThrows(function () {
        validator.validateTopRecoveryState(valid.replace("H2_STATE=not_applicable_before_A6", "H2_STATE=accepted"), expected, "premature H2 ADR");
    }, /machine recovery markers mismatch/);
}

function runGit(root, args) {
    return cp.execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function writeFile(root, rel, bytes) {
    var full = path.join(root, rel.replace(/\//g, path.sep));
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, bytes);
    return full;
}

function writeJson(root, rel, value) {
    return writeFile(root, rel, validator.canonicalBytes(value));
}

function proposalAdr(profile) {
    return Buffer.from([
        "# " + profile.revision + " proposal fixture", "",
        "**状态**：`PROPOSED / HUMAN_ACCEPTANCE_REQUIRED / IMPLEMENTATION_BLOCKED / NOT_DEPLOYED`。", "",
        "**机器恢复标记**：`H1_STATE=pending_exact_human_acceptance`；`H2_STATE=not_applicable_before_A6`。", "",
        profile.scopeRevision, profile.manifestPath,
        profile.revision + " decision manifest SHA-256：`" + profile.manifestSha256 + "`", ""
    ].join("\n"), "utf8");
}

function acceptedAdr(profile) {
    profile = profile || validator.R3_PROFILE;
    return Buffer.from([
        "# " + profile.revision + " accepted fixture", "",
        "**状态**：`ACCEPTED / IMPLEMENTATION_AUTHORIZED_A1_A6 / PROMOTION_BLOCKED / NOT_DEPLOYED`。", "",
        "**机器恢复标记**：`H1_STATE=accepted`；`H2_STATE=not_applicable_before_A6`。", "",
        "| " + profile.revision + " H1 | accepted |", "| " + profile.revision + " implementation | authorized_A1_A6 |", "当前 " + profile.revision + " H1 已有效", ""
    ].join("\n"), "utf8");
}

function proposalMemo(profile) {
    profile = profile || validator.R3_PROFILE;
    return Buffer.from("# " + profile.revision + " memo fixture\n\n**状态**：`READ_ONLY_RESEARCH_COMPLETE / IMPLEMENTATION_BLOCKED / NOT_DEPLOYED`。\n\n**机器恢复标记**：`H1_STATE=pending_exact_human_acceptance`。\n", "utf8");
}

function acceptedMemo(profile) {
    profile = profile || validator.R3_PROFILE;
    return Buffer.from("# " + profile.revision + " memo fixture\n\n**状态**：`READ_ONLY_RESEARCH_COMPLETE / IMPLEMENTATION_AUTHORIZED_A1_A6 / NOT_DEPLOYED`。\n\n**机器恢复标记**：`H1_STATE=accepted`。\n\n当前 " + profile.revision + " H1 已有效\n", "utf8");
}

function testR3ProposalAndActivationGitChain() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-r3-chain-"));
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        validator.R3_FROZEN_CONTRACT_PATHS.forEach(function (rel) {
            if ([validator.R3_MANIFEST_PATH, validator.R3_PROFILE.manifestSchemaPath, validator.R3_PROFILE.h1SchemaPath].indexOf(rel) >= 0) return;
            var source = path.join(ROOT, rel.replace(/\//g, path.sep));
            if (fs.existsSync(source)) writeFile(temp, rel, fs.readFileSync(source));
            else writeFile(temp, rel, Buffer.from("base fixture: " + rel + "\n", "utf8"));
        });
        writeFile(temp, validator.ADR_PATH, Buffer.from("# prior ADR\n", "utf8"));
        writeFile(temp, validator.MEMO_PATH, Buffer.from("# prior memo\n", "utf8"));
        writeJson(temp, validator.H1_RECEIPT_PATH, { accepted: true, schema: "historical-r2-fixture" });
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "P2 accepted state"]);
        var p2 = runGit(temp, ["rev-parse", "HEAD"]);
        var p2Tree = runGit(temp, ["rev-parse", "HEAD^{tree}"]);
        var testProfile = Object.assign({}, validator.R3_PROFILE, { proposalParentCommit: p2, proposalParentTree: p2Tree });

        writeFile(temp, validator.R3_MANIFEST_PATH, r3ManifestBytes);
        writeFile(temp, validator.R3_PROFILE.manifestSchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.manifestSchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.R3_PROFILE.h1SchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.h1SchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.ADR_PATH, proposalAdr(testProfile));
        writeFile(temp, validator.MEMO_PATH, proposalMemo());
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// R3 validator fixture\n", "utf8"));
        writeFile(temp, "tools/audio-v2/contract.test.js", Buffer.from("// R3 tests fixture\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "P3 exact seven paths"]);
        var p3 = runGit(temp, ["rev-parse", "HEAD"]);
        var proposal = validator.resolveProposal(p3, temp, testProfile);
        assert.strictEqual(proposal.profile.revision, "R3");
        assert.deepStrictEqual(validator.validateProposalShape(p3, temp, testProfile).paths.slice().sort(), testProfile.proposalExactPaths.slice().sort());
        validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp);

        runGit(temp, ["checkout", "-q", "-B", "bad-p3-missing", p3 + "^"]);
        writeFile(temp, validator.R3_MANIFEST_PATH, r3ManifestBytes);
        writeFile(temp, validator.R3_PROFILE.manifestSchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.manifestSchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.R3_PROFILE.h1SchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.h1SchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.ADR_PATH, proposalAdr(testProfile));
        writeFile(temp, validator.MEMO_PATH, proposalMemo());
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// R3 validator fixture\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "bad P3 missing test"]);
        expectThrows(function () { validator.validateProposalShape("HEAD", temp, testProfile); }, /did not introduce\/update required path/);

        runGit(temp, ["checkout", "-q", "-B", "bad-p3-extra", p3 + "^"]);
        writeFile(temp, validator.R3_MANIFEST_PATH, r3ManifestBytes);
        writeFile(temp, validator.R3_PROFILE.manifestSchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.manifestSchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.R3_PROFILE.h1SchemaPath, fs.readFileSync(path.join(ROOT, validator.R3_PROFILE.h1SchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.ADR_PATH, proposalAdr(testProfile));
        writeFile(temp, validator.MEMO_PATH, proposalMemo());
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// R3 validator fixture\n", "utf8"));
        writeFile(temp, "tools/audio-v2/contract.test.js", Buffer.from("// R3 tests fixture\n", "utf8"));
        writeFile(temp, "extra-p3.txt", Buffer.from("extra\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "bad P3 extra"]);
        expectThrows(function () { validator.validateProposalShape("HEAD", temp, testProfile); }, /unauthorized path/);

        runGit(temp, ["checkout", "-q", "-B", "bad-p3-parent", p3]);
        writeFile(temp, validator.ADR_PATH, Buffer.concat([proposalAdr(testProfile), Buffer.from("wrong parent\n", "utf8")]));
        runGit(temp, ["add", validator.ADR_PATH]);
        runGit(temp, ["commit", "-q", "-m", "bad P3 parent"]);
        expectThrows(function () { validator.validateProposalShape("HEAD", temp, testProfile); }, /parent commit mismatch/);

        runGit(temp, ["checkout", "-q", "-B", "h3-cases", p3]);

        writeJson(temp, validator.R3_H1_RECEIPT_PATH, makeH1Receipt(proposal, validator.R3_PROFILE));
        writeFile(temp, validator.ADR_PATH, acceptedAdr());
        writeFile(temp, validator.MEMO_PATH, acceptedMemo());
        writeFile(temp, "extra.txt", Buffer.from("not allowed in H3\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "bad H3 extra path"]);
        var badReceiptFile = { buffer: fs.readFileSync(path.join(temp, validator.R3_H1_RECEIPT_PATH.replace(/\//g, path.sep))), value: JSON.parse(fs.readFileSync(path.join(temp, validator.R3_H1_RECEIPT_PATH.replace(/\//g, path.sep)), "utf8")) };
        expectThrows(function () { validator.validateH1Activation(proposal, badReceiptFile, temp); }, /changed paths must be exactly/);

        runGit(temp, ["checkout", "-q", "-B", "good-h3", p3]);
        writeJson(temp, validator.R3_H1_RECEIPT_PATH, makeH1Receipt(proposal, validator.R3_PROFILE));
        writeFile(temp, validator.ADR_PATH, acceptedAdr());
        writeFile(temp, validator.MEMO_PATH, acceptedMemo());
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "H3 exact acceptance"]);
        var goodH3 = runGit(temp, ["rev-parse", "HEAD"]);
        var receiptPath = path.join(temp, validator.R3_H1_RECEIPT_PATH.replace(/\//g, path.sep));
        var receiptFile = { buffer: fs.readFileSync(receiptPath), value: JSON.parse(fs.readFileSync(receiptPath, "utf8")) };
        validator.validateReceiptBinding(receiptFile.value, proposal);
        validator.validateH1Activation(proposal, receiptFile, temp);
        validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp);

        writeJson(temp, validator.H1_RECEIPT_PATH, { accepted: false, schema: "mutated-history" });
        runGit(temp, ["add", validator.H1_RECEIPT_PATH]);
        runGit(temp, ["commit", "-q", "-m", "mutate prior receipt"]);
        expectThrows(function () { validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp); }, /changed or was replaced/);
        runGit(temp, ["checkout", "-q", "-B", "remove-prior", goodH3]);
        fs.unlinkSync(path.join(temp, validator.H1_RECEIPT_PATH.replace(/\//g, path.sep)));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "remove prior receipt"]);
        expectThrows(function () { validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp); }, /not tracked/);

        runGit(temp, ["checkout", "-q", "-B", "non-direct", p3]);
        writeFile(temp, "intermediate.txt", Buffer.from("intermediate\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "intermediate"]);
        writeJson(temp, validator.R3_H1_RECEIPT_PATH, makeH1Receipt(proposal, validator.R3_PROFILE));
        writeFile(temp, validator.ADR_PATH, acceptedAdr());
        writeFile(temp, validator.MEMO_PATH, acceptedMemo());
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "non-direct H3"]);
        var nonDirectBytes = fs.readFileSync(path.join(temp, validator.R3_H1_RECEIPT_PATH.replace(/\//g, path.sep)));
        expectThrows(function () { validator.validateH1Activation(proposal, { buffer: nonDirectBytes, value: JSON.parse(nonDirectBytes.toString("utf8")) }, temp); }, /direct single-parent child/);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

function testR4ProposalAndActivationGitChain() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-r4-chain-"));
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        validator.R4_FROZEN_CONTRACT_PATHS.forEach(function (rel) {
            if ([validator.R4_MANIFEST_PATH, validator.R4_PROFILE.manifestSchemaPath, validator.R4_PROFILE.h1SchemaPath].indexOf(rel) >= 0) return;
            var source = path.join(ROOT, rel.replace(/\//g, path.sep));
            if (fs.existsSync(source)) writeFile(temp, rel, fs.readFileSync(source));
            else writeFile(temp, rel, Buffer.from("base fixture: " + rel + "\n", "utf8"));
        });
        writeFile(temp, validator.ADR_PATH, Buffer.from("# accepted R3 ADR\n", "utf8"));
        writeFile(temp, validator.MEMO_PATH, Buffer.from("# accepted R3 memo\n", "utf8"));
        writeJson(temp, validator.H1_RECEIPT_PATH, { accepted: true, schema: "historical-r2-fixture" });
        writeJson(temp, validator.R3_H1_RECEIPT_PATH, { accepted: true, schema: "historical-r3-fixture" });
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "S11 accepted R3 state"]);
        var s11 = runGit(temp, ["rev-parse", "HEAD"]);
        var s11Tree = runGit(temp, ["rev-parse", "HEAD^{tree}"]);
        var testProfile = Object.assign({}, validator.R4_PROFILE, { proposalParentCommit: s11, proposalParentTree: s11Tree });

        writeFile(temp, validator.R4_MANIFEST_PATH, r4ManifestBytes);
        writeFile(temp, validator.R4_PROFILE.manifestSchemaPath, fs.readFileSync(path.join(ROOT, validator.R4_PROFILE.manifestSchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.R4_PROFILE.h1SchemaPath, fs.readFileSync(path.join(ROOT, validator.R4_PROFILE.h1SchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.ADR_PATH, proposalAdr(testProfile));
        writeFile(temp, validator.MEMO_PATH, proposalMemo(testProfile));
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// R4 validator fixture\n", "utf8"));
        writeFile(temp, "tools/audio-v2/contract.test.js", Buffer.from("// R4 tests fixture\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "P4 exact seven paths"]);
        var p4 = runGit(temp, ["rev-parse", "HEAD"]);
        var proposal = validator.resolveProposal(p4, temp, testProfile);
        assert.strictEqual(proposal.profile.revision, "R4");
        assert.deepStrictEqual(validator.validateProposalShape(p4, temp, testProfile).paths.slice().sort(), testProfile.proposalExactPaths.slice().sort());
        validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp);
        validator.validateImmutableReceiptPath(validator.R3_H1_RECEIPT_PATH, "HEAD", temp);

        writeJson(temp, validator.R4_H1_RECEIPT_PATH, makeH1Receipt(proposal, validator.R4_PROFILE));
        writeFile(temp, validator.ADR_PATH, acceptedAdr(validator.R4_PROFILE));
        writeFile(temp, validator.MEMO_PATH, acceptedMemo(validator.R4_PROFILE));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "H4 exact acceptance"]);
        var receiptPath = path.join(temp, validator.R4_H1_RECEIPT_PATH.replace(/\//g, path.sep));
        var receiptBytes = fs.readFileSync(receiptPath);
        validator.validateReceiptBinding(JSON.parse(receiptBytes.toString("utf8")), proposal);
        validator.validateH1Activation(proposal, { buffer: receiptBytes, value: JSON.parse(receiptBytes.toString("utf8")) }, temp);
        validator.validateImmutableReceiptPath(validator.H1_RECEIPT_PATH, "HEAD", temp);
        validator.validateImmutableReceiptPath(validator.R3_H1_RECEIPT_PATH, "HEAD", temp);

        writeJson(temp, validator.R3_H1_RECEIPT_PATH, { accepted: false, schema: "mutated-r3" });
        runGit(temp, ["add", validator.R3_H1_RECEIPT_PATH]);
        runGit(temp, ["commit", "-q", "-m", "mutate R3 receipt"]);
        expectThrows(function () { validator.validateImmutableReceiptPath(validator.R3_H1_RECEIPT_PATH, "HEAD", temp); }, /changed or was replaced/);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

function testR5ProposalAndActivationGitChain() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-r5-chain-"));
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        validator.R5_FROZEN_CONTRACT_PATHS.forEach(function (rel) {
            if ([validator.R5_MANIFEST_PATH, validator.R5_PROFILE.manifestSchemaPath, validator.R5_PROFILE.h1SchemaPath].indexOf(rel) >= 0) return;
            var source = path.join(ROOT, rel.replace(/\//g, path.sep));
            if (fs.existsSync(source)) writeFile(temp, rel, fs.readFileSync(source));
            else writeFile(temp, rel, Buffer.from("base fixture: " + rel + "\n", "utf8"));
        });
        writeFile(temp, validator.ADR_PATH, Buffer.from("# accepted R4 ADR\n", "utf8"));
        writeFile(temp, validator.MEMO_PATH, Buffer.from("# accepted R4 memo\n", "utf8"));
        writeJson(temp, validator.H1_RECEIPT_PATH, { accepted: true, schema: "historical-r2-fixture" });
        writeJson(temp, validator.R3_H1_RECEIPT_PATH, { accepted: true, schema: "historical-r3-fixture" });
        writeJson(temp, validator.R4_H1_RECEIPT_PATH, { accepted: true, schema: "historical-r4-fixture" });
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "R4 source state"]);
        var source = runGit(temp, ["rev-parse", "HEAD"]);
        var sourceTree = runGit(temp, ["rev-parse", "HEAD^{tree}"]);
        var testProfile = Object.assign({}, validator.R5_PROFILE, { proposalParentCommit: source, proposalParentTree: sourceTree });

        writeFile(temp, validator.R5_MANIFEST_PATH, r5ManifestBytes);
        writeFile(temp, validator.R5_PROFILE.manifestSchemaPath, fs.readFileSync(path.join(ROOT, validator.R5_PROFILE.manifestSchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.R5_PROFILE.h1SchemaPath, fs.readFileSync(path.join(ROOT, validator.R5_PROFILE.h1SchemaPath.replace(/\//g, path.sep))));
        writeFile(temp, validator.ADR_PATH, proposalAdr(testProfile));
        writeFile(temp, validator.MEMO_PATH, proposalMemo(testProfile));
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// R5 validator fixture\n", "utf8"));
        writeFile(temp, "tools/audio-v2/contract.test.js", Buffer.from("// R5 tests fixture\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "P5 exact seven paths"]);
        var p5 = runGit(temp, ["rev-parse", "HEAD"]);
        var proposal = validator.resolveProposal(p5, temp, testProfile);
        assert.strictEqual(proposal.profile.revision, "R5");
        assert.deepStrictEqual(validator.validateProposalShape(p5, temp, testProfile).paths.slice().sort(), testProfile.proposalExactPaths.slice().sort());
        validator.R5_PROFILE.priorReceiptPaths.forEach(function (rel) { validator.validateImmutableReceiptPath(rel, "HEAD", temp); });

        writeJson(temp, validator.R5_H1_RECEIPT_PATH, makeH1Receipt(proposal, validator.R5_PROFILE));
        writeFile(temp, validator.ADR_PATH, acceptedAdr(validator.R5_PROFILE));
        writeFile(temp, validator.MEMO_PATH, acceptedMemo(validator.R5_PROFILE));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "H5 exact acceptance"]);
        var receiptPath = path.join(temp, validator.R5_H1_RECEIPT_PATH.replace(/\//g, path.sep));
        var receiptBytes = fs.readFileSync(receiptPath);
        validator.validateReceiptBinding(JSON.parse(receiptBytes.toString("utf8")), proposal);
        validator.validateH1Activation(proposal, { buffer: receiptBytes, value: JSON.parse(receiptBytes.toString("utf8")) }, temp);
        validator.R5_PROFILE.priorReceiptPaths.forEach(function (rel) { validator.validateImmutableReceiptPath(rel, "HEAD", temp); });
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

function trackedArtifact(root, rel, schema) {
    var full = path.join(root, rel.replace(/\//g, path.sep));
    var bytes = fs.readFileSync(full);
    return {
        blobOid: runGit(root, ["hash-object", rel]),
        bytes: bytes.length,
        kind: "tracked_blob",
        path: rel,
        schema: schema,
        sha256: validator.sha256(bytes)
    };
}

function makePcmWave(sampleRate, channels, seconds, nonZero, amplitude) {
    var frames = sampleRate * seconds;
    var dataBytes = frames * channels * 2;
    var buffer = Buffer.alloc(44 + dataBytes);
    buffer.write("RIFF", 0, "ascii");
    buffer.writeUInt32LE(36 + dataBytes, 4);
    buffer.write("WAVE", 8, "ascii");
    buffer.write("fmt ", 12, "ascii");
    buffer.writeUInt32LE(16, 16);
    buffer.writeUInt16LE(1, 20);
    buffer.writeUInt16LE(channels, 22);
    buffer.writeUInt32LE(sampleRate, 24);
    buffer.writeUInt32LE(sampleRate * channels * 2, 28);
    buffer.writeUInt16LE(channels * 2, 32);
    buffer.writeUInt16LE(16, 34);
    buffer.write("data", 36, "ascii");
    buffer.writeUInt32LE(dataBytes, 40);
    if (nonZero) {
        amplitude = amplitude || 1024;
        for (var offset = 44; offset < buffer.length; offset += 2) buffer.writeInt16LE((offset / 2) % 2 ? amplitude : -amplitude, offset);
    }
    return buffer;
}

function qualificationRunnerFixture() {
    "use strict";
    var crypto = require("crypto");
    var fs = require("fs");
    var path = require("path");
    function arg(name) {
        var index = process.argv.indexOf(name);
        if (index < 0 || !process.argv[index + 1]) throw new Error("missing " + name);
        return process.argv[index + 1];
    }
    function sha(bytes) { return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase(); }
    function sorted(value) {
        if (Array.isArray(value)) return value.map(sorted);
        if (value && typeof value === "object") {
            var output = {};
            Object.keys(value).sort().forEach(function (key) { output[key] = sorted(value[key]); });
            return output;
        }
        return value;
    }
    function canonical(value) { return Buffer.from(JSON.stringify(sorted(value), null, 2) + "\n", "utf8"); }
    function parseJson(file) { return JSON.parse(fs.readFileSync(file, "utf8")); }
    var reportPath = arg("--report");
    var configurationPath = arg("--configuration");
    var inputPath = arg("--input-manifest");
    var candidateRoot = arg("--candidate-root");
    var reportBytes = fs.readFileSync(reportPath);
    var configurationBytes = fs.readFileSync(configurationPath);
    var report = JSON.parse(reportBytes.toString("utf8"));
    var configuration = JSON.parse(configurationBytes.toString("utf8"));
    var input = parseJson(inputPath);
    var dependencyManifest = parseJson(path.resolve(report.provenance.producerDependencyManifestArtifact.path));
    if (configuration.reportId !== report.reportId || input.reportId !== report.reportId) throw new Error("report provenance ID mismatch");
    if (input.closureSha256 !== sha(canonical(input.inputs))) throw new Error("input closure mismatch");
    input.inputs.filter(function (entry) { return entry.kind === "candidate_artifact"; }).forEach(function (entry) {
        var bytes = fs.readFileSync(path.join(candidateRoot, entry.path.replace(/\//g, path.sep)));
        if (bytes.length !== entry.bytes || sha(bytes) !== entry.sha256) throw new Error("candidate input mismatch " + entry.path);
    });
    input.inputs.filter(function (entry) { return entry.kind === "release_source_blob"; }).forEach(function (entry) {
        var bytes = fs.readFileSync(path.resolve(entry.path));
        if (bytes.length !== entry.bytes || sha(bytes) !== entry.sha256) throw new Error("release-source input mismatch " + entry.path);
    });
    report.caseResults.forEach(function (entry) {
        var evidenceBytes = fs.readFileSync(path.resolve(entry.evidenceArtifact.path));
        if (evidenceBytes.length !== entry.evidenceArtifact.bytes || sha(evidenceBytes) !== entry.evidenceArtifact.sha256) throw new Error("case evidence mismatch " + entry.caseId);
        var evidence = JSON.parse(evidenceBytes.toString("utf8"));
        if (evidence.result !== "passed") throw new Error("case not passed " + entry.caseId);
        if (evidence.schema === "cf7.audio-v2.automated-case-evidence.v1") {
            evidence.checks.forEach(function (check) {
                if (check.result !== "passed" || check.measurement.kind !== "boolean" || check.measurement.value !== true) throw new Error("fixture check failed " + check.checkId);
            });
            evidence.captureIds.forEach(function (captureId) {
                var capturePath = path.resolve("docs/evidence/audio-v2/captures/" + captureId + ".wav");
                var captureConfiguration = parseJson(path.resolve("docs/evidence/audio-v2/capture-config/" + captureId + ".json"));
                var captureBytes = fs.readFileSync(capturePath);
                if (captureConfiguration.captureId !== captureId || captureConfiguration.captureBytes !== captureBytes.length || captureConfiguration.captureSha256 !== sha(captureBytes)) throw new Error("endpoint capture provenance mismatch " + captureId);
                var nonzeroCapture = false;
                for (var captureOffset = 44; captureOffset + 1 < captureBytes.length; captureOffset += 2) if (captureBytes.readInt16LE(captureOffset) !== 0) { nonzeroCapture = true; break; }
                if (!nonzeroCapture) throw new Error("endpoint capture is silent " + captureId);
            });
        }
        if (evidence.schema === "cf7.audio-v2.asset-eof-results.v1") {
            evidence.entries.filter(function (asset) { return asset.qualificationResult === "passed" && asset.container === "riff_wave"; }).forEach(function (asset) {
                var wave = fs.readFileSync(path.resolve(asset.path));
                var nonzero = false;
                for (var offset = 44; offset + 1 < wave.length; offset += 2) if (wave.readInt16LE(offset) !== 0) { nonzero = true; break; }
                if (!nonzero) throw new Error("silent asset claims nonzero " + asset.path);
            });
        }
    });
    var closure = report.caseResults.map(function (entry) {
        return { blobOid: entry.evidenceArtifact.blobOid, bytes: entry.evidenceArtifact.bytes, caseId: entry.caseId, path: entry.evidenceArtifact.path, schema: entry.evidenceArtifact.schema, sha256: entry.evidenceArtifact.sha256 };
    }).sort(function (left, right) { return left.caseId.localeCompare(right.caseId); });
    process.stdout.write(canonical({
        candidateBuildIdentity: report.candidateBuildIdentity,
        candidatePayloadClosure: report.candidatePayloadClosure,
        caseEvidenceClosureSha256: sha(canonical(closure)),
        caseResultsSha256: report.caseResultsSha256,
        configurationSha256: sha(configurationBytes),
        inputClosureSha256: input.closureSha256,
        producerBlobOid: report.provenance.producerBlobOid,
        producerDependencyClosureSha256: dependencyManifest.closureSha256,
        producerPath: report.provenance.producerPath,
        producerSha256: report.provenance.producerSha256,
        releaseSource: report.releaseSource,
        reportId: report.reportId,
        reportSha256: sha(reportBytes),
        result: "passed",
        schema: "cf7.audio-v2.producer-verification.v1"
    }));
}

function testGitProvenanceGuards() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-contract-"));
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        fs.mkdirSync(path.join(temp, "docs"), { recursive: true });
        fs.writeFileSync(path.join(temp, "docs", "manifest.json"), manifestBytes);
        fs.writeFileSync(path.join(temp, "docs", "large.bin"), Buffer.alloc(2 * 1024 * 1024, 0x5A));
        runGit(temp, ["add", "docs/manifest.json", "docs/large.bin"]);
        runGit(temp, ["commit", "-q", "-m", "proposal"]);
        var proposal = runGit(temp, ["rev-parse", "HEAD"]);
        var binding = validator.gitObjectBinding(proposal, "docs/manifest.json", temp);
        assert.strictEqual(binding.sha256, validator.sha256(manifestBytes));
        var largeBinding = validator.gitObjectBinding(proposal, "docs/large.bin", temp);
        assert.strictEqual(largeBinding.bytes.length, 2 * 1024 * 1024, "Git binding must recover source inputs larger than Node's default 1 MiB buffer");
        expectThrows(function () { validator.gitObjectBinding(proposal, "docs/missing.json", temp); }, /not tracked/);
        fs.writeFileSync(path.join(temp, "docs", "manifest.json"), validator.canonicalBytes(Object.assign({}, manifest, { scopeRevision: "mutated" })));
        runGit(temp, ["add", "docs/manifest.json"]);
        runGit(temp, ["commit", "-q", "-m", "mutated"]);
        var mutated = validator.gitObjectBinding("HEAD", "docs/manifest.json", temp);
        assert.notStrictEqual(mutated.blobOid, binding.blobOid);
        assert.notStrictEqual(mutated.sha256, binding.sha256);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

function testReleaseSourceFreezeGuards() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-freeze-"));
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        validator.FROZEN_CONTRACT_PATHS.forEach(function (rel) { writeFile(temp, rel, Buffer.from("proposal:" + rel + "\n", "utf8")); });
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "proposal"]);
        var proposalCommit = runGit(temp, ["rev-parse", "HEAD"]);
        var proposal = { bindings: {} };
        validator.FROZEN_CONTRACT_PATHS.forEach(function (rel) { proposal.bindings[rel] = validator.gitObjectBinding(proposalCommit, rel, temp); });
        validator.validateReleaseSourceFreeze(proposal, proposalCommit, temp);
        var driftPath = "tools/audio-v2/validate-contract.js";
        writeFile(temp, driftPath, Buffer.from("weakened source validator\n", "utf8"));
        runGit(temp, ["add", driftPath]);
        runGit(temp, ["commit", "-q", "-m", "source drift"]);
        var releaseCommit = runGit(temp, ["rev-parse", "HEAD"]);
        writeFile(temp, driftPath, proposal.bindings[driftPath].bytes);
        expectThrows(function () { validator.validateReleaseSourceFreeze(proposal, releaseCommit, temp); }, /changed frozen H1 contract bytes/);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
    }
}

function testH2EvidenceBinding() {
    var hexA = "A".repeat(64);
    var hexB = "B".repeat(64);
    var hexC = "C".repeat(64);
    var hexD = "D".repeat(64);
    var caseIds = [
        "formats_shipped_and_new", "bgm_transport_and_crossfade",
        "dense_sfx_overlap_and_throttle", "bgm_sfx_simultaneous",
        "gain_zero_default_max", "default_device_switch",
        "physical_route_bluetooth_or_hdmi", "sleep_resume",
        "quality_pop_latency_channel_loudness", "no_stale_sfx_after_recovery"
    ];
    var listening = {
        allPassed: true,
        candidateBuildIdentity: hexA,
        candidatePayloadClosure: hexB,
        cases: caseIds.map(function (caseId) { return { captureIds: validator.REQUIRED_LISTENING_CAPTURE_IDS[caseId], caseId: caseId, notes: "", result: "passed" }; }),
        recordedAtUtc: "2026-08-09T00:00:00Z",
        reviewer: "human-maintainer",
        schema: "cf7.audio-v2.human-listening-matrix.v1"
    };
    var listeningSha = validator.sha256(validator.canonicalBytes(listening));
    var listeningArtifact = { blobOid: "b".repeat(40), bytes: validator.canonicalBytes(listening).length, kind: "tracked_blob", path: "docs/evidence/audio-v2/listening.json", schema: listening.schema, sha256: listeningSha };
    var reportIds = [
        "asset_offline_eof_qualification", "native_abi_decoder_lifecycle",
        "production_backend_device_fault_injection", "csharp_capability_catalog_bridge",
        "as2_wire_publish", "launcher_affected_regression",
        "exact_candidate_bgm_endpoint_e2e", "exact_candidate_sfx_endpoint_e2e",
        "device_recovery_endpoint_e2e"
    ];
    var automatedReports = reportIds.map(function (reportId, index) {
        return {
            artifact: { blobOid: String(index + 1).repeat(40), bytes: 123 + index, kind: "tracked_blob", path: "docs/evidence/audio-v2/reports/" + reportId + ".json", schema: "cf7.audio-v2.automated-report.v1", sha256: index % 2 ? hexC : hexD },
            reportId: reportId,
            verificationArtifact: { blobOid: (index + 7).toString(16).repeat(40), bytes: 223 + index, kind: "tracked_blob", path: "docs/evidence/audio-v2/verifications/" + reportId + ".json", schema: "cf7.audio-v2.producer-verification.v1", sha256: (index + 7).toString(16).toUpperCase().repeat(64) }
        };
    });
    var endpointCases = ["bgm_playback", "sfx_playback", "bgm_sfx_mix", "device_recovery"];
    var captureShas = [hexA, hexB, hexC, hexD];
    var captures = endpointCases.map(function (caseId, index) {
        var configSha = ["1", "2", "3", "4"][index].repeat(64);
        return {
            artifact: { blobOid: String.fromCharCode(99 + index).repeat(40), bytes: 200000, kind: "tracked_blob", path: "docs/evidence/audio-v2/captures/" + caseId + ".wav", schema: "audio/wav-pcm-s16le", sha256: captureShas[index] },
            captureId: caseId,
            caseIds: [caseId],
            channels: 2,
            configurationArtifact: { blobOid: ["5", "6", "7", "8"][index].repeat(40), bytes: 321 + index, kind: "tracked_blob", path: "docs/evidence/audio-v2/capture-config/" + caseId + ".json", schema: "cf7.audio-v2.endpoint-capture-configuration.v1", sha256: configSha },
            durationSeconds: 1,
            format: "pcm_s16le",
            sampleRate: 48000,
            toolArtifact: { blobOid: "f".repeat(40), bytes: 512, kind: "tracked_blob", path: "tools/audio-v2/capture-endpoint.ps1", schema: "application/powershell", sha256: hexD }
        };
    });
    var endpointCaptures = { closureSha256: "", items: captures, maxBytesEach: 1048576, maxBytesTotal: 4194304 };
    endpointCaptures.closureSha256 = validator.endpointClosureDigest(endpointCaptures);
    var evidence = {
        automatedReports: automatedReports,
        candidate: { buildIdentity: hexA, coreBytes: 123, coreSha256: hexC, manifestBytes: 456, manifestSha256: hexD, miniaudioBytes: 789, miniaudioSha256: hexC, payloadClosure: hexB },
        candidateVerification: { artifact: { blobOid: "9".repeat(40), bytes: 321, kind: "tracked_blob", path: "docs/evidence/audio-v2/candidate/verification.json", schema: "cf7.audio-v2.candidate-verification.v1", sha256: hexD } },
        device: { audioDeviceQualified: true, channels: 2, deviceIdDigest: hexD, sampleFormat: "f32", sampleRate: 48000, selectedBackend: "wasapi", selectedDeviceName: "test endpoint" },
        endpointCaptures: endpointCaptures,
        listeningMatrix: { allPassed: true, artifact: listeningArtifact, sha256: listeningSha },
        qualificationRunner: { artifact: { blobOid: "a".repeat(40), bytes: 1024, kind: "tracked_blob", path: "tools/audio-v2/qualification-runner.js", schema: "application/javascript", sha256: hexC } },
        releaseSource: { commit: "c".repeat(40), treeOid: "d".repeat(40) },
        schema: "cf7.audio-v2.a6-evidence-manifest.v1"
    };
    validator.validateA6EvidenceManifest(evidence, listening);
    var reportCases = validator.REQUIRED_AUTOMATED_REPORT_CASES[reportIds[0]].map(function (caseId, index) {
        var evidenceSchema = caseId === "shipped_corpus_all_files" ? "cf7.audio-v2.asset-eof-results.v1" : "cf7.audio-v2.automated-case-evidence.v1";
        return { caseId: caseId, evidenceArtifact: { blobOid: String(index + 2).repeat(40), bytes: 300 + index, kind: "tracked_blob", path: "docs/evidence/audio-v2/cases/asset/" + caseId + ".json", schema: evidenceSchema, sha256: ["A", "B", "C", "D", "E"][index].repeat(64) }, result: "passed" };
    });
    var reportEnvelope = {
        candidateBuildIdentity: hexA,
        candidatePayloadClosure: hexB,
        caseResults: reportCases,
        caseResultsSha256: validator.sha256(validator.canonicalBytes(reportCases)),
        generatedAtUtc: "2026-08-09T00:00:00Z",
        provenance: {
            configurationArtifact: { blobOid: "8".repeat(40), bytes: 111, kind: "tracked_blob", path: "docs/evidence/audio-v2/config/report.json", schema: "cf7.audio-v2.automated-report-configuration.v1", sha256: hexC },
            inputClosureSha256: hexD,
            inputManifestArtifact: { blobOid: "7".repeat(40), bytes: 222, kind: "tracked_blob", path: "docs/evidence/audio-v2/inputs/report.json", schema: "cf7.audio-v2.automated-report-input-manifest.v1", sha256: hexD },
            producerBlobOid: "a".repeat(40),
            producerDependencyManifestArtifact: { blobOid: "b".repeat(40), bytes: 333, kind: "tracked_blob", path: "config/audio-v2/qualification-runner-dependencies.v1.json", schema: "cf7.audio-v2.qualification-runner-dependencies.v1", sha256: hexC },
            producerPath: "tools/audio-v2/qualification-runner.js",
            producerSha256: hexC
        },
        releaseSource: clone(evidence.releaseSource),
        reportId: reportIds[0],
        result: "passed",
        schema: "cf7.audio-v2.automated-report.v1",
        summary: { failed: 0, passed: reportCases.length, total: reportCases.length }
    };
    validator.validateAutomatedReport(reportEnvelope, reportIds[0], evidence);
    var minimalInputs = [
        { bytes: evidence.candidate.coreBytes, kind: "candidate_artifact", path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", role: "candidate_core", sha256: evidence.candidate.coreSha256 },
        { bytes: evidence.candidate.manifestBytes, kind: "candidate_artifact", path: "runtime/cf7-runtime-manifest.tsv", role: "candidate_runtime_manifest", sha256: evidence.candidate.manifestSha256 },
        { bytes: evidence.candidate.miniaudioBytes, kind: "candidate_artifact", path: "runtime/miniaudio.dll", role: "candidate_miniaudio", sha256: evidence.candidate.miniaudioSha256 },
        { blobOid: "a".repeat(40), bytes: 10, kind: "release_source_blob", path: "tools/audio-v2/qualification-runner.js", role: "shipped_audio_corpus_inventory", sha256: hexC }
    ];
    var minimalInputManifest = { candidateBuildIdentity: hexA, candidatePayloadClosure: hexB, closureSha256: validator.sha256(validator.canonicalBytes(minimalInputs)), inputs: minimalInputs, releaseSource: clone(evidence.releaseSource), reportId: reportIds[0], schema: "cf7.audio-v2.automated-report-input-manifest.v1" };
    expectThrows(function () { validator.validateReportInputManifest(minimalInputManifest, reportIds[0], evidence, "f".repeat(40)); }, /role count mismatch/);
    var emptyReport = clone(reportEnvelope);
    emptyReport.caseResults = [];
    emptyReport.caseResultsSha256 = validator.sha256(validator.canonicalBytes(emptyReport.caseResults));
    emptyReport.summary = { failed: 0, passed: 1, total: 1 };
    expectThrows(function () { validator.validateAutomatedReport(emptyReport, reportIds[0], evidence); }, /case count mismatch/);
    var trustMeReport = clone(reportEnvelope);
    trustMeReport.caseResults = [{ caseId: "trust_me", evidenceArtifact: { blobOid: "6".repeat(40), bytes: 10, kind: "tracked_blob", path: "docs/evidence/audio-v2/cases/trust.json", schema: "cf7.audio-v2.automated-case-evidence.v1", sha256: hexC }, result: "passed" }];
    trustMeReport.caseResultsSha256 = validator.sha256(validator.canonicalBytes(trustMeReport.caseResults));
    trustMeReport.summary = { failed: 0, passed: 1, total: 1 };
    expectThrows(function () { validator.validateAutomatedReport(trustMeReport, reportIds[0], evidence); }, /required case coverage mismatch/);
    var evidenceSha = validator.sha256(validator.canonicalBytes(evidence));
    var evidenceContext = { blobOid: "e".repeat(40), commit: "f".repeat(40), manifest: evidence, path: "docs/evidence/audio-v2/a6-evidence.json", sha256: evidenceSha, tree: "1".repeat(40) };
    var h2Verbatim = validator.formatH2Proposal(evidenceContext);
    var receipt = {
        authorization: { promotionAuthorized: true },
        decision: "accepted",
        evidence: { audioDeviceQualified: true, candidateVerificationSha256: evidence.candidateVerification.artifact.sha256, commit: evidenceContext.commit, endpointCaptureToolSha256: evidence.endpointCaptures.items[0].toolArtifact.sha256, endpointClosureSha256: evidence.endpointCaptures.closureSha256, listeningMatrixSha256: evidence.listeningMatrix.sha256, manifestBlobOid: evidenceContext.blobOid, manifestPath: evidenceContext.path, manifestSha256: evidenceContext.sha256, qualificationRunnerSha256: evidence.qualificationRunner.artifact.sha256, treeOid: evidenceContext.tree },
        recordedAtUtc: "2026-08-09T00:00:00Z",
        releaseSource: { buildIdentity: evidence.candidate.buildIdentity, commit: evidence.releaseSource.commit, payloadClosure: evidence.candidate.payloadClosure, treeOid: evidence.releaseSource.treeOid },
        reviewer: { channel: "test", role: "human-maintainer", verbatim: h2Verbatim },
        schema: "cf7.audio-v2.h2-promotion-acceptance.v2"
    };
    validator.validateH2ReceiptBinding(receipt, evidenceContext);
    var drifted = clone(receipt);
    drifted.releaseSource.payloadClosure = hexA;
    expectThrows(function () { validator.validateH2ReceiptBinding(drifted, evidenceContext); }, /identity\/closure mismatch/);
    var duplicateCase = clone(listening);
    duplicateCase.cases[9].caseId = duplicateCase.cases[0].caseId;
    duplicateCase.cases[9].captureIds = duplicateCase.cases[0].captureIds.slice();
    expectThrows(function () { validator.validateListeningMatrix(duplicateCase, hexA, hexB); }, /each required case exactly once/);
    var badDevice = clone(evidence);
    badDevice.device.channels = 0;
    expectThrows(function () { validator.validateA6EvidenceManifest(badDevice, listening); }, /device channels invalid/);
    var badCapture = clone(evidence);
    badCapture.endpointCaptures.items[0].artifact.bytes = 1048577;
    badCapture.endpointCaptures.closureSha256 = validator.endpointClosureDigest(badCapture.endpointCaptures);
    expectThrows(function () { validator.validateA6EvidenceManifest(badCapture, listening); }, /per-file bound/);
    var oneCaptureClaimsAllCases = clone(evidence);
    oneCaptureClaimsAllCases.endpointCaptures.items = [oneCaptureClaimsAllCases.endpointCaptures.items[0]];
    oneCaptureClaimsAllCases.endpointCaptures.items[0].caseIds = endpointCases.slice();
    oneCaptureClaimsAllCases.endpointCaptures.closureSha256 = validator.endpointClosureDigest(oneCaptureClaimsAllCases.endpointCaptures);
    expectThrows(function () { validator.validateA6EvidenceManifest(oneCaptureClaimsAllCases, listening); }, /exactly four case-specific WAVs/);
    var copiedCaptureBytes = clone(evidence);
    copiedCaptureBytes.endpointCaptures.items[3].artifact.blobOid = copiedCaptureBytes.endpointCaptures.items[0].artifact.blobOid;
    copiedCaptureBytes.endpointCaptures.items[3].artifact.sha256 = copiedCaptureBytes.endpointCaptures.items[0].artifact.sha256;
    copiedCaptureBytes.endpointCaptures.closureSha256 = validator.endpointClosureDigest(copiedCaptureBytes.endpointCaptures);
    expectThrows(function () { validator.validateA6EvidenceManifest(copiedCaptureBytes, listening); }, /distinct audio bytes/);
    var rejectedTemplate = clone(receipt);
    rejectedTemplate.reviewer.verbatim = "I REJECT THIS\ndecision=rejected\n\n" + h2Verbatim;
    expectThrows(function () { validator.validateH2ReceiptBinding(rejectedTemplate, evidenceContext); }, /must equal/);
}

function testH2GitEvidenceChain() {
    var temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-evidence-"));
    var candidateTemp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-candidate-"));
    var evidencePath = "docs/evidence/audio-v2/a6-evidence.json";
    var receiptPath = "docs/evidence/audio-v2/h2-promotion-acceptance.json";
    try {
        runGit(temp, ["init", "-q"]);
        runGit(temp, ["config", "user.email", "audio-contract@example.invalid"]);
        runGit(temp, ["config", "user.name", "Audio Contract Test"]);
        var producerPath = "tools/audio-v2/qualification-runner.js";
        var captureToolPath = "tools/audio-v2/capture-endpoint.ps1";
        var dependencyManifestPath = "config/audio-v2/qualification-runner-dependencies.v1.json";
        var reportIds = [
            "asset_offline_eof_qualification", "native_abi_decoder_lifecycle",
            "production_backend_device_fault_injection", "csharp_capability_catalog_bridge",
            "as2_wire_publish", "launcher_affected_regression",
            "exact_candidate_bgm_endpoint_e2e", "exact_candidate_sfx_endpoint_e2e",
            "device_recovery_endpoint_e2e"
        ];
        writeFile(temp, producerPath, Buffer.from("#!/usr/bin/env node\n\n(\n" + qualificationRunnerFixture.toString() + "\n)();\n", "utf8"));
        writeFile(temp, captureToolPath, Buffer.from("# S-bound endpoint capture trust-root fixture\nparam([string]$CaptureId)\n", "utf8"));
        var fixtureRunnerBytes = fs.readFileSync(path.join(temp, producerPath.replace(/\//g, path.sep)));
        var fixtureDependencies = [{ blobOid: runGit(temp, ["hash-object", producerPath]), bytes: fixtureRunnerBytes.length, path: producerPath, sha256: validator.sha256(fixtureRunnerBytes) }];
        writeJson(temp, dependencyManifestPath, {
            closureSha256: validator.sha256(validator.canonicalBytes(fixtureDependencies)),
            dependencies: fixtureDependencies,
            runnerPath: producerPath,
            schema: "cf7.audio-v2.qualification-runner-dependencies.v1"
        });
        writeFile(temp, "tools/audio-v2/validate-contract.js", Buffer.from("// frozen candidate verification fixture\n", "utf8"));
        writeJson(temp, "config/build/runtime-inputs.v2.json", {
            domains: {
                artifactSource: { fixedFiles: [captureToolPath, producerPath], trees: [] },
                policy: { fixedFiles: [], trees: [] },
                producerRecipe: { fixedFiles: ["tools/audio-v2/validate-contract.js"], trees: [] },
                toolchainLock: { fixedFiles: [dependencyManifestPath], trees: [] }
            },
            payload: {
                excludePaths: ["runtime/cf7-runtime-manifest.tsv", "runtime/runtime-build-attestation.json", "runtime/runtime-release-consensus.json"],
                excludePrefixes: ["runtime/attestations/"],
                fixedRoots: ["CRAZYFLASHER7MercenaryEmpire.exe"],
                trees: ["runtime"]
            },
            schema: "cf7-runtime-inputs.v2"
        });
        writeFile(temp, "sounds/test.wav", makePcmWave(8000, 1, 1, true, 512));
        writeFile(temp, "sounds/zero.wav", makePcmWave(8000, 1, 1, false, 512));
        writeJson(temp, "config/audio-v2/asset-qualification-waivers.v1.json", {
            schema: "cf7.audio-v2.asset-qualification-waivers.v1",
            waivers: [{ exceptionId: "TEST-SILENCE-001", owner: "audio-contract-test", path: "sounds/zero.wav", reason: "deterministic silent fixture", signalClass: "intentional_silence" }]
        });
        reportIds.forEach(function (reportId) {
            validator.REQUIRED_REPORT_INPUT_ROLES[reportId].filter(function (role) { return ["candidate_core", "candidate_miniaudio", "candidate_runtime_manifest"].indexOf(role) < 0; }).forEach(function (role) {
                writeJson(temp, "tools/audio-v2/inputs/" + reportId + "/" + role + ".json", { reportId: reportId, role: role, schema: "cf7.audio-v2.test-source-input.v1" });
            });
        });
        writeFile(temp, validator.ADR_PATH, Buffer.from("# ADR\n\n**状态**：`ACCEPTED / IMPLEMENTATION_AUTHORIZED_A1_A6 / PROMOTION_BLOCKED / NOT_DEPLOYED`。\n\n**机器恢复标记**：`H1_STATE=accepted`；`H2_STATE=not_applicable_before_A6`。\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "release source"]);
        var sourceCommit = runGit(temp, ["rev-parse", "HEAD"]);
        var sourceTree = runGit(temp, ["rev-parse", "HEAD^{tree}"]);
        var producerBinding = validator.gitObjectBinding(sourceCommit, producerPath, temp);
        var dependencyManifestArtifact = trackedArtifact(temp, dependencyManifestPath, "cf7.audio-v2.qualification-runner-dependencies.v1");
        var verifierBinding = validator.gitObjectBinding(sourceCommit, "tools/audio-v2/validate-contract.js", temp);
        var bootstrapBytes = Buffer.from("bootstrap-audio-v2-candidate", "utf8");
        var coreBytes = Buffer.from("core-audio-v2-candidate", "utf8");
        var coreExeBytes = Buffer.from("core-exe-audio-v2-candidate", "utf8");
        var miniaudioBytes = Buffer.from("miniaudio-audio-v2-candidate", "utf8");
        writeFile(candidateTemp, "CRAZYFLASHER7MercenaryEmpire.exe", bootstrapBytes);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", coreBytes);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", coreExeBytes);
        writeFile(candidateTemp, "runtime/miniaudio.dll", miniaudioBytes);
        var sourceDomains = validator.runtimeSourceDomainHashes(sourceCommit, temp);
        var artifactSourceHash = sourceDomains.artifactSourceHash;
        var producerRecipeHash = sourceDomains.producerRecipeHash;
        var toolchainLockHash = sourceDomains.toolchainLockHash;
        var identity = validator.runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash);
        var coreSha = validator.sha256(coreBytes);
        var miniaudioSha = validator.sha256(miniaudioBytes);
        var payloadFiles = [
            { bytes: bootstrapBytes.length, path: "CRAZYFLASHER7MercenaryEmpire.exe", sha256: validator.sha256(bootstrapBytes) },
            { bytes: coreBytes.length, path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", sha256: coreSha },
            { bytes: coreExeBytes.length, path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", sha256: validator.sha256(coreExeBytes) },
            { bytes: miniaudioBytes.length, path: "runtime/miniaudio.dll", sha256: miniaudioSha }
        ];
        var closure = validator.runtimePayloadClosureHash(payloadFiles);
        var candidateManifest = [
            "cf7-runtime-manifest-v2",
            "publishMode\tframework-dependent",
            "artifactSourceHash\t" + artifactSourceHash,
            "producerRecipeHash\t" + producerRecipeHash,
            "toolchainLockHash\t" + toolchainLockHash,
            "toolchainBaseline\ttest-locked",
            "buildIdentityHash\t" + identity,
            "payloadClosureHash\t" + closure,
            "file\t" + payloadFiles[0].path + "\t" + payloadFiles[0].bytes + "\t" + payloadFiles[0].sha256,
            "file\t" + payloadFiles[1].path + "\t" + payloadFiles[1].bytes + "\t" + payloadFiles[1].sha256,
            "file\t" + payloadFiles[2].path + "\t" + payloadFiles[2].bytes + "\t" + payloadFiles[2].sha256,
            "file\t" + payloadFiles[3].path + "\t" + payloadFiles[3].bytes + "\t" + payloadFiles[3].sha256,
            ""
        ].join("\n");
        var candidateManifestPath = writeFile(candidateTemp, "runtime/cf7-runtime-manifest.tsv", Buffer.from(candidateManifest, "utf8"));
        var candidateRoot = fs.realpathSync.native(candidateTemp);
        var candidate = {
            buildIdentity: identity,
            coreBytes: coreBytes.length,
            coreSha256: coreSha,
            manifestBytes: fs.readFileSync(candidateManifestPath).length,
            manifestSha256: validator.sha256(fs.readFileSync(candidateManifestPath)),
            miniaudioBytes: miniaudioBytes.length,
            miniaudioSha256: miniaudioSha,
            payloadClosure: closure
        };
        var parsedCandidateManifest = validator.validateCandidateManifestBytes(fs.readFileSync(candidateManifestPath), candidate);
        var wrongSourceDomains = Object.assign({}, sourceDomains, { artifactSourceHash: "F".repeat(64) });
        expectThrows(function () { validator.validateCandidateSourceDomains(parsedCandidateManifest, wrongSourceDomains); }, /do not derive from release source S/);
        var runtimeManifestSnapshotPath = "docs/evidence/audio-v2/candidate/cf7-runtime-manifest.tsv";
        writeFile(temp, runtimeManifestSnapshotPath, fs.readFileSync(candidateManifestPath));
        var runtimeManifestArtifact = trackedArtifact(temp, runtimeManifestSnapshotPath, "cf7.runtime-manifest.v2.tsv");
        var candidateVerificationPath = "docs/evidence/audio-v2/candidate/verification.json";
        writeJson(temp, candidateVerificationPath, {
            candidate: candidate,
            fullPayload: { buildIdentityRecomputed: true, fileCount: payloadFiles.length, payloadClosureRecomputed: true, runtimeInputsConfigBlobOid: sourceDomains.configBlobOid, runtimeInputsConfigSha256: sourceDomains.configSha256, sourceDomainsRecomputed: true, verifier: "audio_v2_validator_mirror_cf7_runtime_v2_integrity" },
            observedAtUtc: "2026-08-09T00:00:00Z",
            observedRoot: candidateRoot,
            result: "passed",
            runtimeManifestArtifact: runtimeManifestArtifact,
            schema: "cf7.audio-v2.candidate-verification.v1",
            verifier: { blobOid: verifierBinding.blobOid, path: "tools/audio-v2/validate-contract.js", sha256: verifierBinding.sha256 }
        });
        var candidateVerificationArtifact = trackedArtifact(temp, candidateVerificationPath, "cf7.audio-v2.candidate-verification.v1");
        var qualificationRunnerArtifact = trackedArtifact(temp, producerPath, "application/javascript");
        var captureToolArtifact = trackedArtifact(temp, captureToolPath, "application/powershell");
        var device = { audioDeviceQualified: true, channels: 2, deviceIdDigest: "F".repeat(64), sampleFormat: "s16", sampleRate: 8000, selectedBackend: "wasapi", selectedDeviceName: "test endpoint" };
        var endpointCases = ["bgm_playback", "sfx_playback", "bgm_sfx_mix", "device_recovery"];
        var captures = endpointCases.map(function (caseId, index) {
            var capturePath = "docs/evidence/audio-v2/captures/" + caseId + ".wav";
            writeFile(temp, capturePath, makePcmWave(8000, 2, 1, true, 1024 + index));
            var captureArtifact = trackedArtifact(temp, capturePath, "audio/wav-pcm-s16le");
            var configurationPath = "docs/evidence/audio-v2/capture-config/" + caseId + ".json";
            writeJson(temp, configurationPath, {
                candidateBuildIdentity: identity,
                candidatePayloadClosure: closure,
                captureBytes: captureArtifact.bytes,
                captureId: caseId,
                captureSha256: captureArtifact.sha256,
                caseId: caseId,
                channels: 2,
                deviceIdDigest: device.deviceIdDigest,
                durationSeconds: 1,
                format: "pcm_s16le",
                recordedAtUtc: "2026-08-09T00:00:00Z",
                runId: "test-endpoint-run-" + (index + 1),
                sampleRate: 8000,
                schema: "cf7.audio-v2.endpoint-capture-configuration.v1",
                selectedBackend: device.selectedBackend,
                tool: { blobOid: captureToolArtifact.blobOid, path: captureToolPath, sha256: captureToolArtifact.sha256 }
            });
            return {
                artifact: captureArtifact,
                captureId: caseId,
                caseIds: [caseId],
                channels: 2,
                configurationArtifact: trackedArtifact(temp, configurationPath, "cf7.audio-v2.endpoint-capture-configuration.v1"),
                durationSeconds: 1,
                format: "pcm_s16le",
                sampleRate: 8000,
                toolArtifact: captureToolArtifact
            };
        });
        var endpointCaptures = { closureSha256: "", items: captures, maxBytesEach: 1048576, maxBytesTotal: 4194304 };
        endpointCaptures.closureSha256 = validator.endpointClosureDigest(endpointCaptures);
        var reports = reportIds.map(function (reportId) {
            var rel = "docs/evidence/audio-v2/reports/" + reportId + ".json";
            var configurationPath = "docs/evidence/audio-v2/config/" + reportId + ".json";
            writeJson(temp, configurationPath, {
                argv: ["node", producerPath, "--report-id", reportId],
                environment: [],
                reportId: reportId,
                schema: "cf7.audio-v2.automated-report-configuration.v1",
                workingDirectory: "release_source_root"
            });
            var configurationArtifact = trackedArtifact(temp, configurationPath, "cf7.audio-v2.automated-report-configuration.v1");
            var inputManifestPath = "docs/evidence/audio-v2/inputs/" + reportId + ".json";
            var reportInputs = [
                { bytes: candidate.coreBytes, kind: "candidate_artifact", path: "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", role: "candidate_core", sha256: candidate.coreSha256 },
                { bytes: candidate.manifestBytes, kind: "candidate_artifact", path: "runtime/cf7-runtime-manifest.tsv", role: "candidate_runtime_manifest", sha256: candidate.manifestSha256 },
                { bytes: candidate.miniaudioBytes, kind: "candidate_artifact", path: "runtime/miniaudio.dll", role: "candidate_miniaudio", sha256: candidate.miniaudioSha256 }
            ];
            validator.REQUIRED_REPORT_INPUT_ROLES[reportId].filter(function (role) {
                return ["candidate_core", "candidate_miniaudio", "candidate_runtime_manifest"].indexOf(role) < 0;
            }).forEach(function (role) {
                var inputPath = "tools/audio-v2/inputs/" + reportId + "/" + role + ".json";
                var inputBinding = validator.gitObjectBinding(sourceCommit, inputPath, temp);
                reportInputs.push({ blobOid: inputBinding.blobOid, bytes: inputBinding.bytes.length, kind: "release_source_blob", path: inputPath, role: role, sha256: inputBinding.sha256 });
            });
            reportInputs.sort(function (left, right) { var a = left.kind + ":" + left.path; var b = right.kind + ":" + right.path; return a < b ? -1 : (a > b ? 1 : 0); });
            var inputClosureSha256 = validator.sha256(validator.canonicalBytes(reportInputs));
            writeJson(temp, inputManifestPath, {
                candidateBuildIdentity: identity,
                candidatePayloadClosure: closure,
                closureSha256: inputClosureSha256,
                inputs: reportInputs,
                releaseSource: { commit: sourceCommit, treeOid: sourceTree },
                reportId: reportId,
                schema: "cf7.audio-v2.automated-report-input-manifest.v1"
            });
            var inputManifestArtifact = trackedArtifact(temp, inputManifestPath, "cf7.audio-v2.automated-report-input-manifest.v1");
            var reportCases = validator.REQUIRED_AUTOMATED_REPORT_CASES[reportId].map(function (caseId) {
                var casePath = "docs/evidence/audio-v2/cases/" + reportId + "/" + caseId + ".json";
                var common = {
                    candidateBuildIdentity: identity,
                    candidatePayloadClosure: closure,
                    caseId: caseId,
                    configurationSha256: configurationArtifact.sha256,
                    generatedAtUtc: "2026-08-09T00:00:00Z",
                    inputClosureSha256: inputClosureSha256,
                    producerBlobOid: producerBinding.blobOid,
                    producerSha256: producerBinding.sha256,
                    releaseSource: { commit: sourceCommit, treeOid: sourceTree },
                    reportId: reportId,
                    result: "passed"
                };
                var caseSchema;
                if (reportId === "asset_offline_eof_qualification" && caseId === "shipped_corpus_all_files") {
                    var audioBinding = validator.gitObjectBinding(sourceCommit, "sounds/test.wav", temp);
                    var zeroBinding = validator.gitObjectBinding(sourceCommit, "sounds/zero.wav", temp);
                    var waiverArtifact = trackedArtifact(temp, "config/audio-v2/asset-qualification-waivers.v1.json", "cf7.audio-v2.asset-qualification-waivers.v1");
                    caseSchema = "cf7.audio-v2.asset-eof-results.v1";
                    writeJson(temp, casePath, Object.assign({}, common, {
                        entries: [
                            { blobOid: audioBinding.blobOid, bytes: audioBinding.bytes.length, codec: "pcm_or_ieee_float", container: "riff_wave", decodeToEof: true, decodedFrames: 8000, exceptionId: null, path: "sounds/test.wav", qualificationResult: "passed", sha256: audioBinding.sha256, signalClass: "nonzero_pcm" },
                            { blobOid: zeroBinding.blobOid, bytes: zeroBinding.bytes.length, codec: "pcm_or_ieee_float", container: "riff_wave", decodeToEof: true, decodedFrames: 8000, exceptionId: "TEST-SILENCE-001", path: "sounds/zero.wav", qualificationResult: "owned_exception", sha256: zeroBinding.sha256, signalClass: "intentional_silence" }
                        ],
                        inventoryExtensions: [".flac", ".m4a", ".mp3", ".mp4", ".ogg", ".opus", ".wav", ".waz"],
                        inventoryRoots: ["sounds", "music"],
                        schema: caseSchema,
                        summary: { excludedNonAudio: 0, intentionalSilence: 1, nonzeroPcm: 1, ownedExceptions: 1, passed: 1, total: 2 },
                        waiverManifestArtifact: waiverArtifact
                    }));
                } else {
                    caseSchema = "cf7.audio-v2.automated-case-evidence.v1";
                    writeJson(temp, casePath, Object.assign({}, common, {
                        captureIds: (validator.REQUIRED_CASE_CAPTURE_IDS[reportId] && validator.REQUIRED_CASE_CAPTURE_IDS[reportId][caseId]) || [],
                        checks: validator.REQUIRED_CASE_CHECKS[reportId][caseId].map(function (checkId) { return { checkId: checkId, measurement: { kind: "boolean", unit: "pass", value: true }, result: "passed" }; }),
                        schema: caseSchema
                    }));
                }
                return { caseId: caseId, evidenceArtifact: trackedArtifact(temp, casePath, caseSchema), result: "passed" };
            });
            writeJson(temp, rel, {
                candidateBuildIdentity: identity,
                candidatePayloadClosure: closure,
                caseResults: reportCases,
                caseResultsSha256: validator.sha256(validator.canonicalBytes(reportCases)),
                generatedAtUtc: "2026-08-09T00:00:00Z",
                provenance: {
                    configurationArtifact: configurationArtifact,
                    inputClosureSha256: inputClosureSha256,
                    inputManifestArtifact: inputManifestArtifact,
                    producerBlobOid: producerBinding.blobOid,
                    producerDependencyManifestArtifact: dependencyManifestArtifact,
                    producerPath: producerPath,
                    producerSha256: producerBinding.sha256
                },
                releaseSource: { commit: sourceCommit, treeOid: sourceTree },
                reportId: reportId,
                result: "passed",
                schema: "cf7.audio-v2.automated-report.v1",
                summary: { failed: 0, passed: reportCases.length, total: reportCases.length }
            });
            var verificationPath = "docs/evidence/audio-v2/verifications/" + reportId + ".json";
            var verificationBytes = cp.execFileSync(process.execPath, [
                path.join(temp, producerPath.replace(/\//g, path.sep)),
                "--verify-audio-v2-report",
                "--report", path.join(temp, rel.replace(/\//g, path.sep)),
                "--configuration", path.join(temp, configurationPath.replace(/\//g, path.sep)),
                "--input-manifest", path.join(temp, inputManifestPath.replace(/\//g, path.sep)),
                "--candidate-root", candidateRoot
            ], { cwd: temp, encoding: null, stdio: ["ignore", "pipe", "pipe"] });
            writeFile(temp, verificationPath, verificationBytes);
            return {
                artifact: trackedArtifact(temp, rel, "cf7.audio-v2.automated-report.v1"),
                reportId: reportId,
                verificationArtifact: trackedArtifact(temp, verificationPath, "cf7.audio-v2.producer-verification.v1")
            };
        });
        var listeningCases = [
            "formats_shipped_and_new", "bgm_transport_and_crossfade",
            "dense_sfx_overlap_and_throttle", "bgm_sfx_simultaneous",
            "gain_zero_default_max", "default_device_switch",
            "physical_route_bluetooth_or_hdmi", "sleep_resume",
            "quality_pop_latency_channel_loudness", "no_stale_sfx_after_recovery"
        ];
        var listening = {
            allPassed: true,
            candidateBuildIdentity: identity,
            candidatePayloadClosure: closure,
            cases: listeningCases.map(function (caseId) { return { captureIds: validator.REQUIRED_LISTENING_CAPTURE_IDS[caseId], caseId: caseId, notes: "", result: "passed" }; }),
            recordedAtUtc: "2026-08-09T00:00:00Z",
            reviewer: "human-maintainer",
            schema: "cf7.audio-v2.human-listening-matrix.v1"
        };
        var listeningPath = "docs/evidence/audio-v2/listening.json";
        writeJson(temp, listeningPath, listening);
        var listeningArtifact = trackedArtifact(temp, listeningPath, listening.schema);
        var evidence = {
            automatedReports: reports,
            candidate: candidate,
            candidateVerification: { artifact: candidateVerificationArtifact },
            device: device,
            endpointCaptures: endpointCaptures,
            listeningMatrix: { allPassed: true, artifact: listeningArtifact, sha256: listeningArtifact.sha256 },
            qualificationRunner: { artifact: qualificationRunnerArtifact },
            releaseSource: { commit: sourceCommit, treeOid: sourceTree },
            schema: "cf7.audio-v2.a6-evidence-manifest.v1"
        };
        writeJson(temp, evidencePath, evidence);
        writeFile(temp, validator.ADR_PATH, Buffer.from("# ADR\n\n**状态**：`ACCEPTED / E2E_VERIFIED / HUMAN_PROMOTION_ACCEPTANCE_REQUIRED / NOT_DEPLOYED`。\n\n**机器恢复标记**：`H1_STATE=accepted`；`H2_STATE=pending_exact_human_acceptance`；`E1_STATE=evidence_ready`。\n\nE1_EVIDENCE_READY\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "E1 evidence"]);
        var evidenceCommit = runGit(temp, ["rev-parse", "HEAD"]);
        var liveContext = validator.resolveEvidence(evidenceCommit, evidencePath, temp, candidateRoot);
        assert.strictEqual(liveContext.manifest.candidate.buildIdentity, identity);
        assert.strictEqual(liveContext.candidateVerification.liveVerified, true);
        var assetWrapper = reports.filter(function (entry) { return entry.reportId === "asset_offline_eof_qualification"; })[0];
        var assetReport = JSON.parse(fs.readFileSync(path.join(temp, assetWrapper.artifact.path.replace(/\//g, path.sep)), "utf8"));
        var assetCaseResult = assetReport.caseResults.filter(function (entry) { return entry.caseId === "shipped_corpus_all_files"; })[0];
        var assetResults = JSON.parse(fs.readFileSync(path.join(temp, assetCaseResult.evidenceArtifact.path.replace(/\//g, path.sep)), "utf8"));
        var lyingAssetResults = clone(assetResults);
        var zeroEntry = lyingAssetResults.entries.filter(function (entry) { return entry.path === "sounds/zero.wav"; })[0];
        zeroEntry.exceptionId = null;
        zeroEntry.qualificationResult = "passed";
        zeroEntry.signalClass = "nonzero_pcm";
        lyingAssetResults.summary = { excludedNonAudio: 0, intentionalSilence: 0, nonzeroPcm: 2, ownedExceptions: 0, passed: 2, total: 2 };
        var assetInputManifest = JSON.parse(fs.readFileSync(path.join(temp, assetReport.provenance.inputManifestArtifact.path.replace(/\//g, path.sep)), "utf8"));
        expectThrows(function () {
            validator.validateAssetEofResults(lyingAssetResults, assetReport, assetCaseResult, { sha256: assetReport.provenance.configurationArtifact.sha256 }, assetInputManifest, evidence, temp);
        }, /silent but claims nonzero_pcm/);
        var dirtyConfigurationPath = path.join(temp, assetReport.provenance.configurationArtifact.path.replace(/\//g, path.sep));
        var cleanConfigurationBytes = fs.readFileSync(dirtyConfigurationPath);
        fs.writeFileSync(dirtyConfigurationPath, Buffer.concat([cleanConfigurationBytes, Buffer.from(" ", "utf8")]));
        var dirtyIsolatedContext = validator.resolveEvidence(evidenceCommit, evidencePath, temp, candidateRoot);
        assert.strictEqual(dirtyIsolatedContext.manifest.candidate.buildIdentity, identity, "dirty worktree must not alter isolated S/E1 replay inputs");
        fs.writeFileSync(dirtyConfigurationPath, cleanConfigurationBytes);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", Buffer.from("drifted-non-core-payload", "utf8"));
        expectThrows(function () { validator.verifyCandidate(candidate, candidateRoot); }, /exact full candidate payload file set/);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", coreExeBytes);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", Buffer.from("drifted-core", "utf8"));
        expectThrows(function () { validator.verifyCandidate(candidate, candidateRoot); }, /Core DLL SHA\/bytes mismatch/);
        writeFile(candidateTemp, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", coreBytes);
        fs.rmSync(candidateTemp, { recursive: true, force: true });
        var context = validator.resolveEvidence(evidenceCommit, evidencePath, temp);
        assert.strictEqual(context.candidateVerification.liveVerified, false);
        var receipt = {
            authorization: { promotionAuthorized: true },
            decision: "accepted",
            evidence: { audioDeviceQualified: true, candidateVerificationSha256: candidateVerificationArtifact.sha256, commit: context.commit, endpointCaptureToolSha256: captureToolArtifact.sha256, endpointClosureSha256: evidence.endpointCaptures.closureSha256, listeningMatrixSha256: listeningArtifact.sha256, manifestBlobOid: context.blobOid, manifestPath: evidencePath, manifestSha256: context.sha256, qualificationRunnerSha256: qualificationRunnerArtifact.sha256, treeOid: context.tree },
            recordedAtUtc: "2026-08-09T00:00:00Z",
            releaseSource: { buildIdentity: identity, commit: sourceCommit, payloadClosure: closure, treeOid: sourceTree },
            reviewer: { channel: "test", role: "human-maintainer", verbatim: validator.formatH2Proposal(context) },
            schema: "cf7.audio-v2.h2-promotion-acceptance.v2"
        };
        writeJson(temp, receiptPath, receipt);
        writeFile(temp, validator.ADR_PATH, Buffer.from("# ADR\n\n**状态**：`ACCEPTED / E2E_VERIFIED / PROMOTION_AUTHORIZED / NOT_DEPLOYED`。\n\n**机器恢复标记**：`H1_STATE=accepted`；`H2_STATE=accepted`；`E1_STATE=evidence_ready`。\n\n| H2 | accepted |\n当前 H2 已有效\n", "utf8"));
        runGit(temp, ["add", "-A"]);
        runGit(temp, ["commit", "-q", "-m", "E2 H2 receipt"]);
        validator.validateH2Activation(context, receiptPath, temp);
        assert.strictEqual(validator.parseWavePcm(makePcmWave(8000, 2, 1, false), "zero wave").nonZeroSamples, 0);
    } finally {
        fs.rmSync(temp, { recursive: true, force: true });
        fs.rmSync(candidateTemp, { recursive: true, force: true });
    }
}

function main() {
    testAllLeafMutationsInvalidateDigest();
    testR3AllLeafMutationsFailClosed();
    testR4AllLeafMutationsFailClosed();
    testR5AllLeafMutationsFailClosed();
    testRuntimePayloadOrdinalOracle();
    testCanonicalEncodingGuards();
    testStructuralDriftGuards();
    testRevisionSchemaSurfaceBindings();
    testRecoveryStateGuards();
    testR3ProposalAndActivationGitChain();
    testR4ProposalAndActivationGitChain();
    testR5ProposalAndActivationGitChain();
    testGitProvenanceGuards();
    testReleaseSourceFreezeGuards();
    testH2EvidenceBinding();
    testH2GitEvidenceChain();
    console.log("audio-v2 contract tests passed; leafMutations=" + leaves(manifest).length);
}

try {
    main();
} catch (error) {
    console.error(error.stack || error.message);
    process.exit(1);
}
