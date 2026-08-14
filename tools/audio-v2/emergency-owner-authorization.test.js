"use strict";

var assert = require("assert");
var cp = require("child_process");
var fs = require("fs");
var os = require("os");
var path = require("path");
var contract = require("./validate-contract");
var validator = require("./validate-emergency-owner-authorization");

var VALIDATOR_PATH = path.join(__dirname, "validate-emergency-owner-authorization.js");
var checks = 0;

function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

function expectFailure(action, pattern) {
    checks += 1;
    assert.throws(action, pattern);
}

function writeCanonical(filePath, value) {
    fs.writeFileSync(filePath, contract.canonicalBytes(value));
}

function run(args) {
    return cp.spawnSync(process.execPath, [VALIDATOR_PATH].concat(args), {
        encoding: null,
        stdio: ["ignore", "pipe", "pipe"]
    });
}

var temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-audio-owner-emergency-"));
try {
    var requestPath = path.join(temporaryRoot, "request.json");
    var authorizationPath = path.join(temporaryRoot, "authorization.json");
    var artifactSourceHash = "A".repeat(64);
    var producerRecipeHash = "B".repeat(64);
    var toolchainLockHash = "C".repeat(64);
    var policyHash = "D".repeat(64);
    var releaseTreeOid = "1".repeat(40);
    var requestId = validator.runtimeRequestId(releaseTreeOid, policyHash);
    var payloadClosureHash = "E".repeat(64);
    var request = {
        artifactSourceHash: artifactSourceHash,
        buildIdentityHash: contract.runtimeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash),
        bundleFile: "source.bundle",
        bundleSha256: "F".repeat(64),
        bundleTreeOid: "2".repeat(40),
        createdAtUtc: "2026-08-14T00:00:00.000Z",
        policyHash: policyHash,
        producerRecipeHash: producerRecipeHash,
        releaseTreeOid: releaseTreeOid,
        requestCommitOid: "3".repeat(40),
        requestId: requestId,
        requiredQuorum: 2,
        schema: "cf7-runtime-build-request.v2",
        sourceCommitOid: "4".repeat(40),
        sourceKind: "Treeish",
        toolchainLockHash: toolchainLockHash
    };
    fs.writeFileSync(requestPath, Buffer.from(JSON.stringify(request, null, 4).replace(/\n/g, "\r\n") + "\r\n", "utf8"));
    var requestSha256 = contract.sha256(fs.readFileSync(requestPath));
    var notAfterUtc = "2099-01-01T00:00:00Z";
    var emit = run([
        "--emit", "--request-file", requestPath, "--request-id", requestId,
        "--payload-closure", payloadClosureHash, "--not-after-utc", notAfterUtc
    ]);
    check(emit.status === 0, "emit CLI must pass: " + emit.stderr.toString("utf8"));
    check(emit.stderr.length === 0, "emit CLI stderr must be empty");
    var emitted = JSON.parse(emit.stdout.toString("utf8"));
    check(emit.stdout.equals(contract.canonicalBytes(emitted)), "emit stdout must be only canonical JSON bytes");
    check(emitted.ownerAuthorizationVerbatim.length === 3, "emit must freeze all three exact owner messages");
    check(emitted.ownerAuthorizationSha256 === validator.ownerAuthorizationSha256(), "emit must bind canonical owner authorization array bytes");
    check(JSON.stringify(emitted.bypass) === JSON.stringify(["E1", "H2", "E3"]), "emit must freeze the exact bypass list");
    check(JSON.stringify(emitted.retainedControls) === JSON.stringify(validator.RETAINED_CONTROLS), "emit must freeze retained controls");
    fs.writeFileSync(authorizationPath, emit.stdout);

    var verify = run([
        "--verify", "--authorization-file", authorizationPath, "--request-file", requestPath,
        "--request-id", requestId, "--request-sha256", requestSha256,
        "--payload-closure", payloadClosureHash
    ]);
    check(verify.status === 0, "verify CLI must pass: " + verify.stderr.toString("utf8"));
    check(verify.stdout.length === 0 && verify.stderr.length === 0, "verify CLI success must be silent");
    var result = validator.validateAuthorization({
        authorizationPath: authorizationPath,
        requestPath: requestPath,
        expectedRequestId: requestId,
        expectedRequestSha256: requestSha256,
        payloadClosureHash: payloadClosureHash,
        now: new Date("2026-08-14T01:00:00Z")
    });
    check(result.authorizationSha256 === contract.sha256(emit.stdout), "validator must return the authorization byte hash");

    var tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.payloadClosureHash = "9".repeat(64);
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /binding mismatch: payloadClosureHash/);

    tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.ownerAuthorizationVerbatim[1] += "。";
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /ownerAuthorizationVerbatim/);

    tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.bypass = ["E1", "H2"];
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /bypass/);

    tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.retainedControls.pop();
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /retainedControls/);

    tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.notAfterUtc = "2020-01-01T00:00:00Z";
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /expired/);

    tampered = JSON.parse(emit.stdout.toString("utf8"));
    tampered.notAfterUtc = "2099-02-31T00:00:00Z";
    writeCanonical(authorizationPath, tampered);
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /real UTC instant/);

    fs.writeFileSync(authorizationPath, Buffer.from(JSON.stringify(JSON.parse(emit.stdout.toString("utf8"))) + "\n", "utf8"));
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /canonical sorted JSON/);

    fs.writeFileSync(authorizationPath, Buffer.concat([Buffer.from([0xEF, 0xBB, 0xBF]), emit.stdout]));
    expectFailure(function () {
        validator.validateAuthorization({
            authorizationPath: authorizationPath, requestPath: requestPath,
            expectedRequestId: requestId, expectedRequestSha256: requestSha256,
            payloadClosureHash: payloadClosureHash
        });
    }, /BOM/);

    fs.writeFileSync(authorizationPath, emit.stdout);
    var badRequestHash = run([
        "--verify", "--authorization-file", authorizationPath, "--request-file", requestPath,
        "--request-id", requestId, "--request-sha256", "0".repeat(64),
        "--payload-closure", payloadClosureHash
    ]);
    check(badRequestHash.status !== 0 && /request bytes changed/.test(badRequestHash.stderr.toString("utf8")), "verify must fail closed on request hash drift");
    var unexpected = run([
        "--emit", "--request-file", requestPath, "--request-id", requestId,
        "--payload-closure", payloadClosureHash, "--not-after-utc", notAfterUtc,
        "--extra", "value"
    ]);
    check(unexpected.status !== 0 && /unexpected/.test(unexpected.stderr.toString("utf8")), "CLI must reject unexpected arguments");
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("audio-v2 owner emergency authorization tests passed; checks=" + checks);
