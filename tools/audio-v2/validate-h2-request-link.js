"use strict";

var cp = require("child_process");
var fs = require("fs");
var path = require("path");
var contract = require("./validate-contract");

var ROOT = path.resolve(__dirname, "..", "..");
var LINK_PATH = "docs/evidence/audio-v2/h2-request-link.json";
var H2_RECEIPT_PATH = "docs/evidence/audio-v2/h2-promotion-acceptance.json";
var GITHUB_BUILDER_CONFIG_PATH = "config/build/runtime-github-builder.v2.json";
var LINK_SCHEMA = "cf7.audio-v2.h2-request-link.v1";
var LINK_KEYS = [
    "artifactSourceHash", "buildIdentityHash", "evidenceCommit", "evidenceManifestBlobOid",
    "evidenceManifestPath", "evidenceManifestSha256", "h2ReceiptBlobOid", "h2ReceiptCommit",
    "h2ReceiptPath", "h2ReceiptSha256", "policyHash", "producerRecipeHash", "releaseSourceCommit",
    "releaseSourceTree", "requestId", "requestSha256", "schema", "sourceTag", "toolchainLockHash"
];
var REQUEST_KEYS = [
    "artifactSourceHash", "buildIdentityHash", "bundleFile", "bundleSha256", "bundleTreeOid",
    "createdAtUtc", "policyHash", "producerRecipeHash", "releaseTreeOid", "requestCommitOid",
    "requestId", "requiredQuorum", "schema", "sourceCommitOid", "sourceKind", "toolchainLockHash"
];

function fail(message) {
    throw new Error(message);
}

function expect(condition, message) {
    if (!condition) fail(message);
}

function exactKeys(value, keys, label) {
    expect(value && typeof value === "object" && !Array.isArray(value), label + " must be an object");
    var actual = Object.keys(value).sort();
    var expected = keys.slice().sort();
    expect(JSON.stringify(actual) === JSON.stringify(expected), label + " keys must be exactly: " + expected.join(", "));
}

function expectHash(value, label) {
    expect(typeof value === "string" && /^[A-F0-9]{64}$/.test(value), label + " must be uppercase SHA-256");
}

function expectOid(value, label) {
    expect(typeof value === "string" && /^[a-f0-9]{40,64}$/.test(value), label + " must be a lowercase Git object ID");
}

function git(args, root, buffer) {
    return cp.execFileSync("git", ["-c", "core.quotePath=false"].concat(args), {
        cwd: root || ROOT,
        encoding: buffer ? null : "utf8",
        maxBuffer: 64 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"]
    });
}

function resolveCommit(commit, root) {
    return git(["rev-parse", commit + "^{commit}"], root).trim().toLowerCase();
}

function resolveTree(commit, root) {
    return git(["rev-parse", commit + "^{tree}"], root).trim().toLowerCase();
}

function parents(commit, root) {
    var fields = git(["rev-list", "--parents", "-n", "1", commit], root).trim().split(/\s+/);
    return fields.slice(1).map(function (value) { return value.toLowerCase(); });
}

function changedPaths(commit, root) {
    var output = git(["diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", commit], root).trim();
    return output ? output.split(/\r?\n/).filter(Boolean).sort() : [];
}

function pathExists(commit, relativePath, root) {
    var result = cp.spawnSync("git", ["cat-file", "-e", commit + ":" + relativePath], {
        cwd: root || ROOT,
        stdio: "ignore"
    });
    return result.status === 0;
}

function expectDirectCommit(commit, expectedParent, exactPaths, label, root) {
    var actualParents = parents(commit, root);
    expect(actualParents.length === 1 && actualParents[0] === expectedParent, label + " must be a direct single-parent child of " + expectedParent);
    var actualPaths = changedPaths(commit, root);
    var expectedPaths = exactPaths.slice().sort();
    expect(JSON.stringify(actualPaths) === JSON.stringify(expectedPaths), label + " changed paths must be exactly: " + expectedPaths.join(", ") + "; got: " + actualPaths.join(", "));
}

function parseCanonicalGitJson(commit, relativePath, root, label) {
    var binding = contract.gitObjectBinding(commit, relativePath, root);
    var value = contract.parseJsonBuffer(binding.bytes, label || (commit + ":" + relativePath));
    expect(binding.bytes.equals(contract.canonicalBytes(value)), (label || relativePath) + " is not canonical JSON");
    return { binding: binding, value: value };
}

function parseGitJson(commit, relativePath, root, label) {
    var binding = contract.gitObjectBinding(commit, relativePath, root);
    return {
        binding: binding,
        value: contract.parseJsonBuffer(binding.bytes, label || (commit + ":" + relativePath))
    };
}

function runtimeRequestId(releaseTreeOid, policyHash) {
    expectOid(releaseTreeOid, "request releaseTreeOid");
    expectHash(policyHash, "request policyHash");
    return contract.sha256(Buffer.from(
        "cf7-runtime-build-request.v1\nreleaseTreeOid\t" + releaseTreeOid.toLowerCase() +
        "\npolicyHash\t" + policyHash.toUpperCase() + "\n",
        "utf8"
    ));
}

function readRequest(requestPath, expectedRequestId, expectedRequestSha256) {
    expect(typeof requestPath === "string" && path.isAbsolute(requestPath), "request file must be an absolute path");
    var stat = fs.lstatSync(requestPath);
    expect(stat.isFile() && !stat.isSymbolicLink(), "request file must be a regular non-link file");
    var bytes = fs.readFileSync(requestPath);
    var sha256 = contract.sha256(bytes);
    if (expectedRequestSha256) {
        expectHash(expectedRequestSha256, "expected request SHA-256");
        expect(sha256 === expectedRequestSha256, "runtime request bytes changed after the promotion snapshot");
    }
    var text = bytes.toString("utf8").replace(/^\uFEFF/, "");
    var request;
    try { request = JSON.parse(text); }
    catch (error) { fail("runtime request is invalid JSON: " + error.message); }
    exactKeys(request, REQUEST_KEYS, "runtime request v2");
    expect(request.schema === "cf7-runtime-build-request.v2", "runtime request schema must remain cf7-runtime-build-request.v2");
    expect(request.sourceKind === "Treeish", "Audio v2 formal request must bind the exact release-source commit/tree");
    expectOid(String(request.releaseTreeOid || ""), "request releaseTreeOid");
    expectOid(String(request.sourceCommitOid || ""), "request sourceCommitOid");
    ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "policyHash", "buildIdentityHash", "requestId"].forEach(function (field) {
        expectHash(String(request[field] || ""), "request " + field);
    });
    expectedRequestId = String(expectedRequestId || "").toUpperCase();
    expectHash(expectedRequestId, "expected requestId");
    expect(request.requestId === expectedRequestId, "runtime requestId differs from the promotion requestId");
    expect(runtimeRequestId(request.releaseTreeOid, request.policyHash) === request.requestId, "runtime requestId recomputation mismatch");
    expect(contract.runtimeBuildIdentityHash(request.artifactSourceHash, request.producerRecipeHash, request.toolchainLockHash) === request.buildIdentityHash, "runtime request build identity is not recomputable from its three build domains");
    return { bytes: bytes, request: request, sha256: sha256 };
}

function validateSourceAndTag(root, sourceCommit, sourceTree, request) {
    expectOid(sourceCommit, "release source commit");
    expectOid(sourceTree, "release source tree");
    expect(resolveCommit(sourceCommit, root) === sourceCommit, "release source commit does not resolve exactly");
    expect(resolveTree(sourceCommit, root) === sourceTree, "release source tree mismatch");
    expect(request.sourceCommitOid === sourceCommit && request.releaseTreeOid === sourceTree, "request source commit/tree do not match the H2 release source");
    var configFile = parseGitJson(sourceCommit, GITHUB_BUILDER_CONFIG_PATH, root, "release-source GitHub builder config");
    var config = configFile.value;
    expect(config.schema === "cf7-runtime-github-builder.v2" && config.enabled === true, "release-source GitHub builder config is not enabled v2");
    expect(typeof config.sourceRef === "string" && /^refs\/tags\/runtime-build-v2\/[a-z0-9][a-z0-9._-]{1,80}$/.test(config.sourceRef), "release-source tag is outside the protected runtime-build-v2 namespace");
    var taggedCommit = resolveCommit(config.sourceRef, root);
    expect(taggedCommit === sourceCommit, "release source tag does not peel to S");
    expect(resolveTree(config.sourceRef, root) === sourceTree, "release source tag tree does not match S");
    return config.sourceRef;
}

function validateH1Receipts(root, headCommit, sourceCommit) {
    [contract.H1_RECEIPT_PATH, contract.R3_H1_RECEIPT_PATH, contract.R4_H1_RECEIPT_PATH].forEach(function (relativePath) {
        var immutable = contract.validateImmutableReceiptPath(relativePath, headCommit, root).binding;
        var atSource = contract.gitObjectBinding(sourceCommit, relativePath, root);
        expect(atSource.blobOid === immutable.blobOid && atSource.bytes.equals(immutable.bytes), "release source changed or removed accepted H1 receipt: " + relativePath);
    });
    var r4 = parseCanonicalGitJson(headCommit, contract.R4_H1_RECEIPT_PATH, root, "R4 H1 receipt").value;
    expect(r4.schema === "cf7.audio-v2.h1-implementation-acceptance.v4" && r4.scopeRevision === "AUDIO-V2-H1-SWEET-SPOT-R4", "R4 H1 receipt identity mismatch");
    expect(r4.decision === "accepted" && r4.authorization && r4.authorization.promotionAuthorized === false, "R4 H1 receipt must remain accepted and promotion-blocked");
}

function loadH2Context(options) {
    var root = options.root || ROOT;
    var h2Commit = resolveCommit(options.h2Commit, root);
    var h2Parents = parents(h2Commit, root);
    expect(h2Parents.length === 1, "E2 must have exactly one parent E1");
    var evidenceCommit = h2Parents[0];
    expectDirectCommit(h2Commit, evidenceCommit, [contract.ADR_PATH, H2_RECEIPT_PATH], "E2", root);
    expect(!pathExists(evidenceCommit, H2_RECEIPT_PATH, root), "H2 receipt must be introduced exactly at E2");

    var receiptFile = parseCanonicalGitJson(h2Commit, H2_RECEIPT_PATH, root, "E2 H2 receipt");
    var receipt = receiptFile.value;
    expect(receipt.evidence && receipt.evidence.commit === evidenceCommit, "H2 receipt does not bind E1");
    var evidencePath = String(receipt.evidence.manifestPath || "");
    expect(evidencePath.indexOf("docs/evidence/audio-v2/") === 0 && evidencePath.endsWith(".json"), "H2 evidence manifest path is invalid");
    var evidenceFile = parseCanonicalGitJson(evidenceCommit, evidencePath, root, "E1 evidence manifest");
    var evidence = evidenceFile.value;
    var evidenceTree = resolveTree(evidenceCommit, root);
    var context = {
        blobOid: evidenceFile.binding.blobOid,
        commit: evidenceCommit,
        manifest: evidence,
        path: evidencePath,
        sha256: evidenceFile.binding.sha256,
        tree: evidenceTree
    };
    contract.validateH2ReceiptBinding(receipt, context);

    expect(evidence.releaseSource && evidence.candidate, "E1 evidence manifest lacks release source or candidate binding");
    var sourceCommit = String(evidence.releaseSource.commit || "");
    var sourceTree = String(evidence.releaseSource.treeOid || "");
    expectDirectCommit(evidenceCommit, sourceCommit, changedPaths(evidenceCommit, root), "E1", root);
    var e1Paths = changedPaths(evidenceCommit, root);
    expect(e1Paths.indexOf(contract.ADR_PATH) >= 0 && e1Paths.indexOf(evidencePath) >= 0, "E1 must update the ADR and evidence manifest");
    e1Paths.forEach(function (relativePath) {
        expect(relativePath === contract.ADR_PATH || relativePath.indexOf("docs/evidence/audio-v2/") === 0, "E1 contains a non-evidence path: " + relativePath);
    });
    expect(!pathExists(sourceCommit, evidencePath, root), "E1 evidence manifest must be introduced after S");
    expect(evidence.candidate.buildIdentity === options.requestInfo.request.buildIdentityHash, "E1 candidate build identity differs from the request");
    var sourceTag = validateSourceAndTag(root, sourceCommit, sourceTree, options.requestInfo.request);
    validateH1Receipts(root, h2Commit, sourceCommit);

    return {
        context: context,
        evidenceFile: evidenceFile,
        h2Commit: h2Commit,
        receipt: receipt,
        receiptFile: receiptFile,
        sourceCommit: sourceCommit,
        sourceTag: sourceTag,
        sourceTree: sourceTree
    };
}

function buildH2RequestLink(options) {
    options = options || {};
    var root = options.root || ROOT;
    var requestInfo = readRequest(options.requestPath, options.expectedRequestId, options.expectedRequestSha256);
    var h2 = loadH2Context({ root: root, h2Commit: options.h2Commit || "HEAD", requestInfo: requestInfo });
    var request = requestInfo.request;
    var link = {
        artifactSourceHash: request.artifactSourceHash,
        buildIdentityHash: request.buildIdentityHash,
        evidenceCommit: h2.context.commit,
        evidenceManifestBlobOid: h2.evidenceFile.binding.blobOid,
        evidenceManifestPath: h2.context.path,
        evidenceManifestSha256: h2.evidenceFile.binding.sha256,
        h2ReceiptBlobOid: h2.receiptFile.binding.blobOid,
        h2ReceiptCommit: h2.h2Commit,
        h2ReceiptPath: H2_RECEIPT_PATH,
        h2ReceiptSha256: h2.receiptFile.binding.sha256,
        policyHash: request.policyHash,
        producerRecipeHash: request.producerRecipeHash,
        releaseSourceCommit: h2.sourceCommit,
        releaseSourceTree: h2.sourceTree,
        requestId: request.requestId,
        requestSha256: requestInfo.sha256,
        schema: LINK_SCHEMA,
        sourceTag: h2.sourceTag,
        toolchainLockHash: request.toolchainLockHash
    };
    return { bytes: contract.canonicalBytes(link), link: link };
}

function validateH2RequestLink(options) {
    options = options || {};
    var root = options.root || ROOT;
    var requestInfo = readRequest(options.requestPath, options.expectedRequestId, options.expectedRequestSha256);
    var linkCommit = resolveCommit(options.linkCommit || "HEAD", root);
    var linkParents = parents(linkCommit, root);
    expect(linkParents.length === 1, "E3 must have exactly one parent E2");
    var h2Commit = linkParents[0];
    expectDirectCommit(linkCommit, h2Commit, [LINK_PATH], "E3", root);
    expect(!pathExists(h2Commit, LINK_PATH, root), "H2 request link must be introduced exactly at E3");
    var linkFile = parseCanonicalGitJson(linkCommit, LINK_PATH, root, "E3 H2 request link");
    var link = linkFile.value;
    exactKeys(link, LINK_KEYS, "H2 request link");
    expect(link.schema === LINK_SCHEMA, "H2 request link schema mismatch");
    ["requestId", "requestSha256", "artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "policyHash", "buildIdentityHash", "evidenceManifestSha256", "h2ReceiptSha256"].forEach(function (field) {
        expectHash(String(link[field] || ""), "H2 request link " + field);
    });
    ["releaseSourceCommit", "releaseSourceTree", "evidenceCommit", "evidenceManifestBlobOid", "h2ReceiptCommit", "h2ReceiptBlobOid"].forEach(function (field) {
        expectOid(String(link[field] || ""), "H2 request link " + field);
    });
    expect(link.h2ReceiptCommit === h2Commit, "H2 request link does not bind its E2 parent");

    var h2 = loadH2Context({ root: root, h2Commit: h2Commit, requestInfo: requestInfo });
    var request = requestInfo.request;
    var expected = {
        artifactSourceHash: request.artifactSourceHash,
        buildIdentityHash: request.buildIdentityHash,
        evidenceCommit: h2.context.commit,
        evidenceManifestBlobOid: h2.evidenceFile.binding.blobOid,
        evidenceManifestPath: h2.context.path,
        evidenceManifestSha256: h2.evidenceFile.binding.sha256,
        h2ReceiptBlobOid: h2.receiptFile.binding.blobOid,
        h2ReceiptCommit: h2.h2Commit,
        h2ReceiptPath: H2_RECEIPT_PATH,
        h2ReceiptSha256: h2.receiptFile.binding.sha256,
        policyHash: request.policyHash,
        producerRecipeHash: request.producerRecipeHash,
        releaseSourceCommit: h2.sourceCommit,
        releaseSourceTree: h2.sourceTree,
        requestId: request.requestId,
        requestSha256: requestInfo.sha256,
        schema: LINK_SCHEMA,
        sourceTag: h2.sourceTag,
        toolchainLockHash: request.toolchainLockHash
    };
    LINK_KEYS.forEach(function (field) {
        expect(link[field] === expected[field], "H2 request link binding mismatch: " + field);
    });
    var receiptAtE3 = contract.gitObjectBinding(linkCommit, H2_RECEIPT_PATH, root);
    expect(receiptAtE3.blobOid === h2.receiptFile.binding.blobOid && receiptAtE3.bytes.equals(h2.receiptFile.binding.bytes), "accepted H2 receipt changed after E2");
    validateH1Receipts(root, linkCommit, h2.sourceCommit);
    return {
        linkBlobOid: linkFile.binding.blobOid,
        linkCommit: linkCommit,
        linkSha256: linkFile.binding.sha256,
        requestId: request.requestId,
        requestSha256: requestInfo.sha256
    };
}

function argumentValue(args, name, required) {
    var index = args.indexOf(name);
    if (index < 0) {
        if (required) fail(name + " is required");
        return null;
    }
    expect(index + 1 < args.length && args[index + 1].indexOf("--") !== 0, name + " requires a value");
    return args[index + 1];
}

function main() {
    var args = process.argv.slice(2);
    var emit = args.indexOf("--emit-link") >= 0;
    var verify = args.indexOf("--verify-link") >= 0;
    expect(emit !== verify, "choose exactly one of --emit-link or --verify-link");
    var requestPath = argumentValue(args, "--request-file", true);
    var requestId = argumentValue(args, "--request-id", true);
    var requestSha256 = argumentValue(args, "--request-sha256", verify);
    var allowed = [emit ? "--emit-link" : "--verify-link", "--request-file", requestPath, "--request-id", requestId];
    if (verify) allowed.push("--request-sha256", requestSha256);
    expect(args.length === allowed.length && args.every(function (arg) { return allowed.indexOf(arg) >= 0; }), "unexpected H2 request-link CLI argument");
    if (emit) {
        process.stdout.write(buildH2RequestLink({ requestPath: requestPath, expectedRequestId: requestId, h2Commit: "HEAD" }).bytes);
        return;
    }
    var result = validateH2RequestLink({
        requestPath: requestPath,
        expectedRequestId: requestId,
        expectedRequestSha256: requestSha256,
        linkCommit: "HEAD"
    });
    console.log("audio-v2 H2 request link validation passed; linkCommit=" + result.linkCommit + "; requestId=" + result.requestId);
}

if (require.main === module) {
    try { main(); }
    catch (error) {
        console.error("audio-v2 H2 request link validation failed: " + error.message);
        process.exit(1);
    }
}

module.exports = {
    H2_RECEIPT_PATH: H2_RECEIPT_PATH,
    LINK_KEYS: LINK_KEYS,
    LINK_PATH: LINK_PATH,
    LINK_SCHEMA: LINK_SCHEMA,
    buildH2RequestLink: buildH2RequestLink,
    runtimeRequestId: runtimeRequestId,
    validateH2RequestLink: validateH2RequestLink
};
