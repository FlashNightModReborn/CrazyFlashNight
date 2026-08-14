"use strict";

var fs = require("fs");
var path = require("path");
var contract = require("./validate-contract");

var SCHEMA = "cf7.audio-v2.emergency-owner-authorization.v1";
var MAX_JSON_BYTES = 64 * 1024;
var OWNER_AUTHORIZATION_VERBATIM = [
    "后续能不能直接推进到完成云端共识与部署推送，我已经要睡觉了，另外从今天的路程上目前流程上已经占据了绝大部分的流程与配额开销，有害的可能就是这个过度设计的流程",
    "继续需要做流程的原因是什么，这不是开公司需要流程合规",
    "拆/降级机制和继续跑目前管线哪个更快，我希望的就是一觉起来后能至少看到完成了构建，让dll部署推送上去"
];
var BYPASS = ["E1", "H2", "E3"];
var RETAINED_CONTROLS = [
    "immutable_request",
    "dual_signer",
    "dual_fault_domain",
    "production_policy",
    "strict_v2_verifier",
    "atomic_promotion",
    "rollback"
];
var AUTHORIZATION_KEYS = [
    "artifactSourceHash", "buildIdentityHash", "bypass", "notAfterUtc",
    "ownerAuthorizationSha256", "ownerAuthorizationVerbatim", "payloadClosureHash",
    "policyHash", "producerRecipeHash", "releaseTreeOid", "requestId", "requestSha256",
    "retainedControls", "schema", "sourceCommitOid", "toolchainLockHash"
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

function expectExactArray(actual, expected, label) {
    expect(Array.isArray(actual) && JSON.stringify(actual) === JSON.stringify(expected), label + " does not match the frozen ordered values");
}

function expectNotAfterUtc(value, now) {
    var match = typeof value === "string" && /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?Z$/.exec(value);
    expect(match, "notAfterUtc must be an explicit RFC3339 UTC instant");
    var parsed = Date.parse(value);
    expect(Number.isFinite(parsed), "notAfterUtc is not a real UTC instant");
    var instant = new Date(parsed);
    expect(instant.getUTCFullYear() === Number(match[1]) && instant.getUTCMonth() + 1 === Number(match[2]) &&
        instant.getUTCDate() === Number(match[3]) && instant.getUTCHours() === Number(match[4]) &&
        instant.getUTCMinutes() === Number(match[5]) && instant.getUTCSeconds() === Number(match[6]),
    "notAfterUtc is not a real UTC instant");
    expect(parsed > (now || new Date()).getTime(), "owner emergency authorization has expired");
}

function readBoundedRegularFile(filePath, label) {
    expect(typeof filePath === "string" && path.isAbsolute(filePath), label + " must be an absolute path");
    var stat = fs.lstatSync(filePath);
    expect(stat.isFile() && !stat.isSymbolicLink(), label + " must be a regular non-link file");
    expect(stat.size > 0 && stat.size <= MAX_JSON_BYTES, label + " exceeds the bounded JSON size");
    return fs.readFileSync(filePath);
}

function runtimeRequestId(releaseTreeOid, policyHash) {
    expectOid(releaseTreeOid, "request releaseTreeOid");
    expectHash(policyHash, "request policyHash");
    return contract.sha256(Buffer.from(
        "cf7-runtime-build-request.v1\nreleaseTreeOid\t" + releaseTreeOid +
        "\npolicyHash\t" + policyHash + "\n",
        "utf8"
    ));
}

function readRequest(requestPath, expectedRequestId, expectedRequestSha256) {
    var bytes = readBoundedRegularFile(requestPath, "request file");
    var sha256 = contract.sha256(bytes);
    if (expectedRequestSha256) {
        expectHash(expectedRequestSha256, "expected request SHA-256");
        expect(sha256 === expectedRequestSha256, "runtime request bytes changed after the promotion snapshot");
    }
    var request;
    try { request = JSON.parse(bytes.toString("utf8").replace(/^\uFEFF/, "")); }
    catch (error) { fail("runtime request is invalid JSON: " + error.message); }
    exactKeys(request, REQUEST_KEYS, "runtime request v2");
    expect(request.schema === "cf7-runtime-build-request.v2", "runtime request schema must remain cf7-runtime-build-request.v2");
    expect(request.sourceKind === "Treeish", "owner emergency release requires an exact Treeish request");
    expectOid(request.sourceCommitOid, "request sourceCommitOid");
    expectOid(request.releaseTreeOid, "request releaseTreeOid");
    ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "policyHash", "buildIdentityHash", "requestId"].forEach(function (field) {
        expectHash(request[field], "request " + field);
    });
    expectedRequestId = String(expectedRequestId || "").toUpperCase();
    expectHash(expectedRequestId, "expected requestId");
    expect(request.requestId === expectedRequestId, "runtime requestId differs from the promotion requestId");
    expect(runtimeRequestId(request.releaseTreeOid, request.policyHash) === request.requestId, "runtime requestId recomputation mismatch");
    expect(contract.runtimeBuildIdentityHash(request.artifactSourceHash, request.producerRecipeHash, request.toolchainLockHash) === request.buildIdentityHash, "runtime request build identity is not recomputable from its three build domains");
    return { bytes: bytes, request: request, sha256: sha256 };
}

function ownerAuthorizationSha256() {
    return contract.sha256(contract.canonicalBytes(OWNER_AUTHORIZATION_VERBATIM));
}

function buildAuthorization(options) {
    options = options || {};
    var requestInfo = readRequest(options.requestPath, options.expectedRequestId, null);
    var payloadClosureHash = String(options.payloadClosureHash || "").toUpperCase();
    expectHash(payloadClosureHash, "payload closure hash");
    expectNotAfterUtc(options.notAfterUtc, options.now);
    var request = requestInfo.request;
    var authorization = {
        artifactSourceHash: request.artifactSourceHash,
        buildIdentityHash: request.buildIdentityHash,
        bypass: BYPASS.slice(),
        notAfterUtc: options.notAfterUtc,
        ownerAuthorizationSha256: ownerAuthorizationSha256(),
        ownerAuthorizationVerbatim: OWNER_AUTHORIZATION_VERBATIM.slice(),
        payloadClosureHash: payloadClosureHash,
        policyHash: request.policyHash,
        producerRecipeHash: request.producerRecipeHash,
        releaseTreeOid: request.releaseTreeOid,
        requestId: request.requestId,
        requestSha256: requestInfo.sha256,
        retainedControls: RETAINED_CONTROLS.slice(),
        schema: SCHEMA,
        sourceCommitOid: request.sourceCommitOid,
        toolchainLockHash: request.toolchainLockHash
    };
    return { authorization: authorization, bytes: contract.canonicalBytes(authorization) };
}

function validateAuthorization(options) {
    options = options || {};
    var requestInfo = readRequest(options.requestPath, options.expectedRequestId, options.expectedRequestSha256);
    var bytes = readBoundedRegularFile(options.authorizationPath, "authorization file");
    var authorization = contract.parseJsonBuffer(bytes, "owner emergency authorization");
    expect(bytes.equals(contract.canonicalBytes(authorization)), "owner emergency authorization must be canonical sorted JSON with two-space indent and terminal LF");
    exactKeys(authorization, AUTHORIZATION_KEYS, "owner emergency authorization");
    expect(authorization.schema === SCHEMA, "owner emergency authorization schema mismatch");
    [
        "artifactSourceHash", "buildIdentityHash", "ownerAuthorizationSha256", "payloadClosureHash",
        "policyHash", "producerRecipeHash", "requestId", "requestSha256", "toolchainLockHash"
    ].forEach(function (field) { expectHash(authorization[field], "owner emergency authorization " + field); });
    expectOid(authorization.sourceCommitOid, "owner emergency authorization sourceCommitOid");
    expectOid(authorization.releaseTreeOid, "owner emergency authorization releaseTreeOid");
    expectExactArray(authorization.ownerAuthorizationVerbatim, OWNER_AUTHORIZATION_VERBATIM, "ownerAuthorizationVerbatim");
    expect(authorization.ownerAuthorizationSha256 === ownerAuthorizationSha256(), "ownerAuthorizationSha256 does not bind the frozen verbatim array");
    expectExactArray(authorization.bypass, BYPASS, "bypass");
    expectExactArray(authorization.retainedControls, RETAINED_CONTROLS, "retainedControls");
    expectNotAfterUtc(authorization.notAfterUtc, options.now);

    var expectedPayloadClosureHash = String(options.payloadClosureHash || "").toUpperCase();
    expectHash(expectedPayloadClosureHash, "expected payload closure hash");
    var request = requestInfo.request;
    var bindings = {
        artifactSourceHash: request.artifactSourceHash,
        buildIdentityHash: request.buildIdentityHash,
        payloadClosureHash: expectedPayloadClosureHash,
        policyHash: request.policyHash,
        producerRecipeHash: request.producerRecipeHash,
        releaseTreeOid: request.releaseTreeOid,
        requestId: request.requestId,
        requestSha256: requestInfo.sha256,
        sourceCommitOid: request.sourceCommitOid,
        toolchainLockHash: request.toolchainLockHash
    };
    Object.keys(bindings).forEach(function (field) {
        expect(authorization[field] === bindings[field], "owner emergency authorization binding mismatch: " + field);
    });
    return {
        authorizationSha256: contract.sha256(bytes),
        notAfterUtc: authorization.notAfterUtc,
        requestId: authorization.requestId
    };
}

function argumentValue(args, name) {
    var indexes = [];
    args.forEach(function (arg, index) { if (arg === name) indexes.push(index); });
    expect(indexes.length === 1, name + " must appear exactly once");
    var index = indexes[0];
    expect(index + 1 < args.length && args[index + 1].indexOf("--") !== 0, name + " requires a value");
    return args[index + 1];
}

function main() {
    var args = process.argv.slice(2);
    var emit = args.filter(function (value) { return value === "--emit"; }).length;
    var verify = args.filter(function (value) { return value === "--verify"; }).length;
    expect((emit === 1) !== (verify === 1), "choose exactly one of --emit or --verify");
    var optionNames = emit === 1 ?
        ["--request-file", "--request-id", "--payload-closure", "--not-after-utc"] :
        ["--authorization-file", "--request-file", "--request-id", "--request-sha256", "--payload-closure"];
    var values = {};
    optionNames.forEach(function (name) { values[name] = argumentValue(args, name); });
    expect(args.length === 1 + optionNames.length * 2, "unexpected owner emergency authorization CLI argument");
    var allowedNames = [emit === 1 ? "--emit" : "--verify"].concat(optionNames);
    for (var index = 0; index < args.length; index += 1) {
        if (args[index].indexOf("--") === 0) expect(allowedNames.indexOf(args[index]) >= 0, "unexpected owner emergency authorization CLI argument: " + args[index]);
    }
    if (emit === 1) {
        var emitted = buildAuthorization({
            requestPath: values["--request-file"],
            expectedRequestId: values["--request-id"],
            payloadClosureHash: values["--payload-closure"],
            notAfterUtc: values["--not-after-utc"]
        });
        process.stdout.write(emitted.bytes);
        return;
    }
    validateAuthorization({
        authorizationPath: values["--authorization-file"],
        requestPath: values["--request-file"],
        expectedRequestId: values["--request-id"],
        expectedRequestSha256: values["--request-sha256"],
        payloadClosureHash: values["--payload-closure"]
    });
}

if (require.main === module) {
    try { main(); }
    catch (error) {
        console.error("audio-v2 owner emergency authorization failed: " + error.message);
        process.exit(1);
    }
}

module.exports = {
    AUTHORIZATION_KEYS: AUTHORIZATION_KEYS,
    BYPASS: BYPASS,
    OWNER_AUTHORIZATION_VERBATIM: OWNER_AUTHORIZATION_VERBATIM,
    RETAINED_CONTROLS: RETAINED_CONTROLS,
    SCHEMA: SCHEMA,
    buildAuthorization: buildAuthorization,
    ownerAuthorizationSha256: ownerAuthorizationSha256,
    runtimeRequestId: runtimeRequestId,
    validateAuthorization: validateAuthorization
};
