"use strict";

var assert = require("assert");
var cp = require("child_process");
var fs = require("fs");
var os = require("os");
var path = require("path");
var contract = require("./validate-contract");
var linkValidator = require("./validate-h2-request-link");

function runGit(root, args) {
    return cp.execFileSync("git", args, {
        cwd: root,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"]
    }).trim();
}

function writeFile(root, relativePath, bytes) {
    var full = path.join(root, relativePath.replace(/\//g, path.sep));
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, bytes);
}

function writeJson(root, relativePath, value) {
    writeFile(root, relativePath, contract.canonicalBytes(value));
}

function commit(root, message) {
    runGit(root, ["add", "-A"]);
    runGit(root, ["commit", "-q", "-m", message]);
    return runGit(root, ["rev-parse", "HEAD"]);
}

function expectFailure(label, action, pattern) {
    var thrown = null;
    try { action(); }
    catch (error) { thrown = error; }
    assert(thrown, label + " did not fail closed");
    if (pattern) assert(pattern.test(thrown.message), label + " failed for the wrong reason: " + thrown.message);
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function makeH2Receipt(context) {
    var evidence = context.manifest;
    return {
        authorization: { promotionAuthorized: true },
        decision: "accepted",
        evidence: {
            audioDeviceQualified: true,
            candidateVerificationSha256: evidence.candidateVerification.artifact.sha256,
            commit: context.commit,
            endpointCaptureToolSha256: evidence.endpointCaptures.items[0].toolArtifact.sha256,
            endpointClosureSha256: evidence.endpointCaptures.closureSha256,
            listeningMatrixSha256: evidence.listeningMatrix.sha256,
            manifestBlobOid: context.blobOid,
            manifestPath: context.path,
            manifestSha256: context.sha256,
            qualificationRunnerSha256: evidence.qualificationRunner.artifact.sha256,
            treeOid: context.tree
        },
        recordedAtUtc: "2026-08-14T00:00:00Z",
        releaseSource: {
            buildIdentity: evidence.candidate.buildIdentity,
            commit: evidence.releaseSource.commit,
            payloadClosure: evidence.candidate.payloadClosure,
            treeOid: evidence.releaseSource.treeOid
        },
        reviewer: { channel: "test", role: "human-maintainer", verbatim: contract.formatH2Proposal(context) },
        schema: "cf7.audio-v2.h2-promotion-acceptance.v2"
    };
}

function main() {
    var root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-h2-link-"));
    var requestRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-v2-request-"));
    var evidencePath = "docs/evidence/audio-v2/a6-evidence.json";
    var requestPath = path.join(requestRoot, "request.json");
    var tagName = "runtime-build-v2/test-e3-link";
    var hashA = "A".repeat(64);
    var hashB = "B".repeat(64);
    var hashC = "C".repeat(64);
    var hashD = "D".repeat(64);
    var hashE = "E".repeat(64);
    var hashF = "F".repeat(64);
    try {
        runGit(root, ["init", "-q"]);
        runGit(root, ["config", "user.email", "audio-link@example.invalid"]);
        runGit(root, ["config", "user.name", "Audio Link Test"]);
        writeJson(root, "config/build/runtime-github-builder.v2.json", {
            enabled: true,
            schema: "cf7-runtime-github-builder.v2",
            sourceRef: "refs/tags/" + tagName
        });
        writeJson(root, contract.R4_MANIFEST_PATH, { schema: "cf7.audio-v2.h1-decision-manifest.v4" });
        writeJson(root, contract.H1_RECEIPT_PATH, { decision: "accepted", schema: "historical-r2" });
        writeJson(root, contract.R3_H1_RECEIPT_PATH, { decision: "accepted", schema: "historical-r3" });
        writeJson(root, contract.R4_H1_RECEIPT_PATH, {
            authorization: { promotionAuthorized: false },
            decision: "accepted",
            schema: "cf7.audio-v2.h1-implementation-acceptance.v4",
            scopeRevision: "AUDIO-V2-H1-SWEET-SPOT-R4"
        });
        writeFile(root, "tools/audio-v2/validate-contract.js", fs.readFileSync(path.join(__dirname, "validate-contract.js")));
        writeFile(root, "tools/audio-v2/validate-h2-request-link.js", fs.readFileSync(path.join(__dirname, "validate-h2-request-link.js")));
        writeFile(root, contract.ADR_PATH, Buffer.from("# R4 accepted\n", "utf8"));
        var sourceCommit = commit(root, "S release source");
        var sourceTree = runGit(root, ["rev-parse", "HEAD^{tree}"]);
        runGit(root, ["tag", tagName, sourceCommit]);

        var buildIdentity = contract.runtimeBuildIdentityHash(hashA, hashB, hashC);
        var evidence = {
            candidate: { buildIdentity: buildIdentity, payloadClosure: hashD },
            candidateVerification: { artifact: { sha256: hashE } },
            endpointCaptures: { closureSha256: hashF, items: [{ toolArtifact: { sha256: hashA } }] },
            listeningMatrix: { sha256: hashB },
            qualificationRunner: { artifact: { sha256: hashC } },
            releaseSource: { commit: sourceCommit, treeOid: sourceTree },
            schema: "cf7.audio-v2.a6-evidence-manifest.v1"
        };
        writeJson(root, evidencePath, evidence);
        writeFile(root, contract.ADR_PATH, Buffer.from("# E1 evidence\n", "utf8"));
        var evidenceCommit = commit(root, "E1 evidence");
        var evidenceBinding = contract.gitObjectBinding(evidenceCommit, evidencePath, root);
        var context = {
            blobOid: evidenceBinding.blobOid,
            commit: evidenceCommit,
            manifest: evidence,
            path: evidencePath,
            sha256: evidenceBinding.sha256,
            tree: runGit(root, ["rev-parse", "HEAD^{tree}"])
        };
        writeJson(root, linkValidator.H2_RECEIPT_PATH, makeH2Receipt(context));
        writeFile(root, contract.ADR_PATH, Buffer.from("# E2 H2 accepted\n", "utf8"));
        var h2Commit = commit(root, "E2 H2 acceptance");

        var request = {
            artifactSourceHash: hashA,
            buildIdentityHash: buildIdentity,
            bundleFile: "source.bundle",
            bundleSha256: hashF,
            bundleTreeOid: sourceTree,
            createdAtUtc: "2026-08-14T00:00:00.0000000Z",
            policyHash: hashD,
            producerRecipeHash: hashB,
            releaseTreeOid: sourceTree,
            requestCommitOid: sourceCommit,
            requestId: linkValidator.runtimeRequestId(sourceTree, hashD),
            requiredQuorum: 2,
            schema: "cf7-runtime-build-request.v2",
            sourceCommitOid: sourceCommit,
            sourceKind: "Treeish",
            toolchainLockHash: hashC
        };
        var requestBytes = Buffer.from(JSON.stringify(request, null, 2) + "\r\n", "utf8");
        fs.writeFileSync(requestPath, requestBytes);
        var requestSha256 = contract.sha256(requestBytes);
        var built = linkValidator.buildH2RequestLink({
            root: root,
            h2Commit: h2Commit,
            requestPath: requestPath,
            expectedRequestId: request.requestId
        });
        assert.deepStrictEqual(Object.keys(built.link).sort(), linkValidator.LINK_KEYS.slice().sort());
        assert(built.bytes.equals(contract.canonicalBytes(built.link)), "emitted E3 link must be canonical JSON");
        var fixtureCli = path.join(root, "tools", "audio-v2", "validate-h2-request-link.js");
        var cliEmitted = cp.execFileSync(process.execPath, [
            fixtureCli, "--emit-link", "--request-file", requestPath, "--request-id", request.requestId
        ], { cwd: root, encoding: null, stdio: ["ignore", "pipe", "pipe"] });
        assert(cliEmitted.equals(built.bytes), "--emit-link CLI must emit the exact canonical E3 bytes at E2");
        var mixedMode = cp.spawnSync(process.execPath, [
            fixtureCli, "--emit-link", "--verify-link", "--request-file", requestPath, "--request-id", request.requestId
        ], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
        assert.notStrictEqual(mixedMode.status, 0, "mixed emit/verify CLI mode must fail closed");
        assert(/choose exactly one/.test(mixedMode.stderr), "mixed-mode CLI failure must identify the mode conflict");

        writeFile(root, linkValidator.LINK_PATH, built.bytes);
        var linkCommit = commit(root, "E3 request link");
        var result = linkValidator.validateH2RequestLink({
            root: root,
            linkCommit: linkCommit,
            requestPath: requestPath,
            expectedRequestId: request.requestId,
            expectedRequestSha256: requestSha256
        });
        assert.strictEqual(result.linkCommit, linkCommit);
        assert.strictEqual(result.requestSha256, requestSha256);
        var cliVerified = cp.execFileSync(process.execPath, [
            fixtureCli, "--verify-link", "--request-file", requestPath, "--request-id", request.requestId,
            "--request-sha256", requestSha256
        ], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
        assert(/validation passed/.test(cliVerified), "--verify-link CLI must pass at the exact E3 HEAD");

        fs.appendFileSync(requestPath, Buffer.from(" ", "utf8"));
        expectFailure("raw request byte drift", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: linkCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /request bytes changed/);
        fs.writeFileSync(requestPath, requestBytes);

        runGit(root, ["tag", "-f", tagName, evidenceCommit]);
        expectFailure("moved release tag", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: linkCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /tag does not peel to S/);
        runGit(root, ["tag", "-f", tagName, sourceCommit]);

        function makeBadE3(label, linkBytes, extraPath, mutateReceipt) {
            runGit(root, ["checkout", "-q", "--detach", h2Commit]);
            writeFile(root, linkValidator.LINK_PATH, linkBytes);
            if (extraPath) writeFile(root, extraPath, Buffer.from("extra\n", "utf8"));
            if (mutateReceipt) {
                var receipt = makeH2Receipt(context);
                receipt.recordedAtUtc = "2026-08-14T00:00:01Z";
                writeJson(root, linkValidator.H2_RECEIPT_PATH, receipt);
            }
            return commit(root, label);
        }

        var nonCanonicalCommit = makeBadE3("bad E3 noncanonical", Buffer.from(JSON.stringify(built.link) + "\n", "utf8"));
        expectFailure("noncanonical link", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: nonCanonicalCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /not canonical JSON/);

        var extraBinding = clone(built.link);
        extraBinding.untrusted = true;
        var extraBindingCommit = makeBadE3("bad E3 extra binding", contract.canonicalBytes(extraBinding));
        expectFailure("20th link binding", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: extraBindingCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /keys must be exactly/);

        var wrongBinding = clone(built.link);
        wrongBinding.evidenceManifestSha256 = hashF;
        var wrongBindingCommit = makeBadE3("bad E3 wrong binding", contract.canonicalBytes(wrongBinding));
        expectFailure("wrong evidence binding", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: wrongBindingCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /binding mismatch/);

        var extraPathCommit = makeBadE3("bad E3 extra path", built.bytes, "docs/evidence/audio-v2/extra.txt");
        expectFailure("E3 extra path", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: extraPathCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /changed paths must be exactly/);

        var changedReceiptCommit = makeBadE3("bad E3 changed H2 receipt", built.bytes, null, true);
        expectFailure("changed H2 receipt", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: changedReceiptCommit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /changed paths must be exactly/);

        expectFailure("missing E3 link", function () {
            linkValidator.validateH2RequestLink({ root: root, linkCommit: h2Commit, requestPath: requestPath, expectedRequestId: request.requestId, expectedRequestSha256: requestSha256 });
        }, /E3 changed paths must be exactly/);

        console.log("audio-v2 H2 request-link tests passed");
    } finally {
        fs.rmSync(root, { recursive: true, force: true });
        fs.rmSync(requestRoot, { recursive: true, force: true });
    }
}

try { main(); }
catch (error) {
    console.error(error.stack || error.message);
    process.exit(1);
}
