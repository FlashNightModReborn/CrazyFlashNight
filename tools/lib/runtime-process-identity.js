"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const CORE_BASENAME = "CRAZYFLASHER7MercenaryEmpire.Core";
const CORE_EXE_NAME = CORE_BASENAME + ".exe";
const CORE_DLL_NAME = CORE_BASENAME + ".dll";
const MANIFEST_NAME = "cf7-runtime-manifest.tsv";
const CANDIDATE_METADATA_NAME = "runtime-build-metadata.v2.json";
const SHA256_RE = /^[0-9A-F]{64}$/;

class RuntimeIdentityError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "RuntimeIdentityError";
    this.code = code;
    this.phase = "runtime_identity";
    this.details = details || null;
  }
}

function reject(code, message, details) {
  throw new RuntimeIdentityError(code, message, details);
}

function normalizeSha256(value, label) {
  const normalized = String(value || "").toUpperCase();
  if (!SHA256_RE.test(normalized)) {
    reject("runtime_identity_invalid", label + " must be a SHA-256 hex value");
  }
  return normalized;
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function realExistingPath(filePath, label) {
  try {
    return fs.realpathSync.native(filePath);
  } catch (error) {
    reject(
      "runtime_identity_path_missing",
      label + " does not exist or cannot be resolved: " + filePath,
      { path: filePath, error: error.message }
    );
  }
}

function readSmallText(filePath, maximumBytes, label) {
  let stat;
  try {
    stat = fs.statSync(filePath);
  } catch (error) {
    reject("runtime_identity_file_missing", label + " is missing: " + filePath, {
      path: filePath,
      error: error.message,
    });
  }
  if (!stat.isFile() || stat.size <= 0 || stat.size > maximumBytes) {
    reject("runtime_identity_file_invalid", label + " has an invalid size", {
      path: filePath,
      size: stat.size,
      maximumBytes,
    });
  }
  return fs.readFileSync(filePath, "utf8");
}

function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex").toUpperCase();
}

function parseRuntimeManifestText(text, sourceLabel) {
  const label = sourceLabel || "runtime manifest";
  const lines = String(text || "").replace(/\r/g, "").split("\n");
  if (lines[0] !== "cf7-runtime-manifest-v2") {
    reject("runtime_identity_manifest_invalid", label + " has an unsupported header");
  }

  let buildIdentity = null;
  let payloadClosure = null;
  let coreDll = null;
  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line) continue;
    const fields = line.split("\t");
    if (fields[0] === "buildIdentityHash") {
      if (fields.length !== 2) {
        reject("runtime_identity_manifest_invalid", label + " has a malformed buildIdentityHash row");
      }
      if (buildIdentity !== null) {
        reject("runtime_identity_manifest_invalid", label + " repeats buildIdentityHash");
      }
      buildIdentity = normalizeSha256(fields[1], label + " buildIdentityHash");
    } else if (fields[0] === "payloadClosureHash") {
      if (fields.length !== 2) {
        reject("runtime_identity_manifest_invalid", label + " has a malformed payloadClosureHash row");
      }
      if (payloadClosure !== null) {
        reject("runtime_identity_manifest_invalid", label + " repeats payloadClosureHash");
      }
      payloadClosure = normalizeSha256(fields[1], label + " payloadClosureHash");
    } else if (fields[0] === "file" && fields.length >= 2
        && fields[1].replace(/\\/g, "/") === "runtime/" + CORE_DLL_NAME) {
      if (fields.length !== 4) {
        reject("runtime_identity_manifest_invalid", label + " has a malformed Core DLL row");
      }
      if (coreDll !== null) {
        reject("runtime_identity_manifest_invalid", label + " repeats the Core DLL row");
      }
      const size = Number(fields[2]);
      if (!Number.isSafeInteger(size) || size <= 0) {
        reject("runtime_identity_manifest_invalid", label + " has an invalid Core DLL size");
      }
      coreDll = {
        size,
        sha256: normalizeSha256(fields[3], label + " Core DLL SHA-256"),
      };
    }
  }

  if (!buildIdentity || !payloadClosure || !coreDll) {
    reject("runtime_identity_manifest_invalid", label + " lacks runtime identity fields", {
      hasBuildIdentity: !!buildIdentity,
      hasPayloadClosure: !!payloadClosure,
      hasCoreDll: !!coreDll,
    });
  }
  return { buildIdentity, payloadClosure, coreDll };
}

function readRuntimeManifest(runtimeDirectory) {
  const manifestPath = path.join(runtimeDirectory, MANIFEST_NAME);
  return parseRuntimeManifestText(
    readSmallText(manifestPath, 1024 * 1024, "runtime manifest"),
    manifestPath
  );
}

function readCandidateMetadata(candidateRoot) {
  const metadataPath = path.join(candidateRoot, CANDIDATE_METADATA_NAME);
  const raw = readSmallText(metadataPath, 64 * 1024, "candidate metadata");
  const requiredKeys = ["schema", "buildIdentityHash", "payloadClosureHash"];
  requiredKeys.forEach((key) => {
    const matches = raw.match(new RegExp('"' + key + '"\\s*:', "g"));
    if (!matches || matches.length !== 1) {
      reject("runtime_identity_metadata_invalid", metadataPath + " must contain one " + key);
    }
  });

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    reject("runtime_identity_metadata_invalid", metadataPath + " is not valid JSON", {
      error: error.message,
    });
  }
  if (!parsed || parsed.schema !== "cf7-runtime-candidate-metadata.v2") {
    reject("runtime_identity_metadata_invalid", metadataPath + " has an unsupported schema");
  }
  return {
    buildIdentity: normalizeSha256(parsed.buildIdentityHash, metadataPath + " buildIdentityHash"),
    payloadClosure: normalizeSha256(parsed.payloadClosureHash, metadataPath + " payloadClosureHash"),
  };
}

function readInstallationIdentity(installRoot, runtimeMode) {
  const canonicalInstallRoot = realExistingPath(installRoot, "runtime installation root");
  const runtimeDirectory = realExistingPath(
    path.join(canonicalInstallRoot, "runtime"),
    "runtime directory"
  );
  const processPath = realExistingPath(
    path.join(runtimeDirectory, CORE_EXE_NAME),
    "Core executable"
  );
  const coreDllPath = realExistingPath(
    path.join(runtimeDirectory, CORE_DLL_NAME),
    "Core DLL"
  );
  const manifest = readRuntimeManifest(runtimeDirectory);
  const coreStat = fs.statSync(coreDllPath);
  const coreSha256 = sha256File(coreDllPath);
  if (coreStat.size !== manifest.coreDll.size || coreSha256 !== manifest.coreDll.sha256) {
    reject("runtime_identity_core_manifest_mismatch", "Core DLL bytes do not match the runtime manifest", {
      coreDllPath,
      actualSize: coreStat.size,
      expectedSize: manifest.coreDll.size,
      actualSha256: coreSha256,
      expectedSha256: manifest.coreDll.sha256,
    });
  }

  if (runtimeMode === "isolated_candidate") {
    const metadata = readCandidateMetadata(canonicalInstallRoot);
    if (metadata.buildIdentity !== manifest.buildIdentity
        || metadata.payloadClosure !== manifest.payloadClosure) {
      reject(
        "runtime_identity_metadata_manifest_mismatch",
        "candidate metadata does not match its runtime manifest",
        { metadata, manifest }
      );
    }
  }

  return {
    runtimeMode,
    processPath,
    coreSha256,
    buildIdentity: manifest.buildIdentity,
    payloadClosure: manifest.payloadClosure,
    installRoot: canonicalInstallRoot,
  };
}

function resolveCandidateRoot(projectRoot, candidateRoot) {
  const root = realExistingPath(projectRoot, "project root");
  const requested = path.isAbsolute(candidateRoot)
    ? candidateRoot
    : path.resolve(root, candidateRoot);
  const canonicalCandidate = realExistingPath(requested, "candidate root");
  const candidateBase = realExistingPath(
    path.join(root, "tmp", "runtime-candidates", "v2"),
    "candidate output root"
  );
  if (!samePath(path.dirname(canonicalCandidate), candidateBase)) {
    reject(
      "runtime_identity_candidate_outside_output_root",
      "--candidate-root must name one direct child of tmp/runtime-candidates/v2",
      { candidateRoot: canonicalCandidate, candidateBase }
    );
  }
  return canonicalCandidate;
}

function resolveExpectedRuntimeIdentity(projectRoot, candidateRoot) {
  if (candidateRoot) {
    return readInstallationIdentity(
      resolveCandidateRoot(projectRoot, candidateRoot),
      "isolated_candidate"
    );
  }
  return readInstallationIdentity(projectRoot, "formal_runtime");
}

function buildLauncherStartArguments(scriptPath, expectedIdentity) {
  const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath];
  if (!expectedIdentity || !expectedIdentity.runtimeMode) {
    reject("runtime_identity_expected_missing", "expected runtime identity is required before launch");
  }
  if (expectedIdentity.runtimeMode === "isolated_candidate") {
    if (!expectedIdentity.installRoot || !path.isAbsolute(expectedIdentity.installRoot)) {
      reject(
        "runtime_identity_candidate_root_invalid",
        "isolated_candidate launch requires an absolute candidate installation root"
      );
    }
    args.push("-CandidateRoot", expectedIdentity.installRoot);
  } else if (expectedIdentity.runtimeMode !== "formal_runtime") {
    reject("runtime_identity_mode_invalid", "unsupported runtimeMode: " + expectedIdentity.runtimeMode);
  }
  return args;
}

function readLauncherPorts(projectRoot, expectedHttpPort) {
  const portsPath = path.join(projectRoot, "launcher_ports.json");
  const raw = readSmallText(portsPath, 64 * 1024, "launcher ports file");
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    reject("runtime_identity_ports_invalid", "launcher_ports.json is not valid JSON", {
      error: error.message,
    });
  }
  if (!Number.isInteger(parsed.pid) || parsed.pid <= 0
      || !Number.isInteger(parsed.httpPort) || parsed.httpPort !== expectedHttpPort) {
    reject("runtime_identity_ports_invalid", "launcher_ports.json does not bind this HTTP endpoint", {
      expectedHttpPort,
      actualHttpPort: parsed.httpPort,
      pid: parsed.pid,
    });
  }
  return { pid: parsed.pid, httpPort: parsed.httpPort };
}

function processExecutablePath(pid) {
  const command = "$p = Get-Process -Id " + String(pid)
    + " -ErrorAction Stop; [Console]::Out.Write($p.Path)";
  const result = childProcess.spawnSync(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", command],
    {
      encoding: "utf8",
      windowsHide: true,
      timeout: 10000,
      maxBuffer: 1024 * 1024,
    }
  );
  if (result.status !== 0 || !String(result.stdout || "").trim()) {
    reject("runtime_identity_process_query_failed", "could not resolve Launcher process path", {
      pid,
      exitCode: result.status,
      signal: result.signal || null,
      stderr: String(result.stderr || "").slice(-2000),
    });
  }
  return realExistingPath(String(result.stdout).trim(), "Launcher process executable");
}

function identifyProcessInstallation(projectRoot, processPath) {
  const root = realExistingPath(projectRoot, "project root");
  const formalProcess = path.join(root, "runtime", CORE_EXE_NAME);
  if (samePath(processPath, formalProcess)) {
    return readInstallationIdentity(root, "formal_runtime");
  }

  const runtimeDirectory = path.dirname(processPath);
  const candidateRoot = path.dirname(runtimeDirectory);
  const candidateBase = path.join(root, "tmp", "runtime-candidates", "v2");
  if (path.basename(runtimeDirectory).toLowerCase() === "runtime"
      && path.basename(processPath).toLowerCase() === CORE_EXE_NAME.toLowerCase()
      && samePath(path.dirname(candidateRoot), candidateBase)) {
    return readInstallationIdentity(candidateRoot, "isolated_candidate");
  }

  reject("runtime_identity_unknown_process", "HTTP bus belongs to an unsupported executable path", {
    processPath,
    formalProcess,
    candidateBase,
  });
}

function collectRuntimeIdentity(projectRoot, httpPort) {
  const ports = readLauncherPorts(projectRoot, httpPort);
  const queriedProcessPath = processExecutablePath(ports.pid);
  const identity = identifyProcessInstallation(projectRoot, queriedProcessPath);
  if (!samePath(identity.processPath, queriedProcessPath)) {
    reject("runtime_identity_process_contract_mismatch", "resolved installation does not own the running process", {
      queriedProcessPath,
      installationProcessPath: identity.processPath,
    });
  }
  const portsAfterProbe = readLauncherPorts(projectRoot, httpPort);
  if (portsAfterProbe.pid !== ports.pid) {
    reject("runtime_identity_ports_changed", "Launcher PID changed during runtime identity verification", {
      beforePid: ports.pid,
      afterPid: portsAfterProbe.pid,
      httpPort,
    });
  }
  return Object.assign(identity, ports);
}

function publicRuntimeIdentity(identity) {
  if (!identity) return null;
  return {
    runtimeMode: identity.runtimeMode || null,
    processPath: identity.processPath || null,
    coreSha256: identity.coreSha256 || null,
    buildIdentity: identity.buildIdentity || null,
    payloadClosure: identity.payloadClosure || null,
    pid: Number.isInteger(identity.pid) ? identity.pid : null,
    httpPort: Number.isInteger(identity.httpPort) ? identity.httpPort : null,
  };
}

function assertRuntimeIdentity(expected, actual) {
  const mismatches = [];
  if (expected.runtimeMode !== actual.runtimeMode) mismatches.push("runtimeMode");
  if (!expected.processPath || !actual.processPath
      || !samePath(expected.processPath, actual.processPath)) mismatches.push("processPath");
  if (expected.coreSha256 !== actual.coreSha256) mismatches.push("coreSha256");
  if (expected.buildIdentity !== actual.buildIdentity) mismatches.push("buildIdentity");
  if (expected.payloadClosure !== actual.payloadClosure) mismatches.push("payloadClosure");
  if (mismatches.length > 0) {
    reject(
      "runtime_identity_mismatch",
      "running Launcher does not match the requested runtime identity: " + mismatches.join(", "),
      {
        mismatches,
        expected: publicRuntimeIdentity(expected),
        actual: publicRuntimeIdentity(actual),
      }
    );
  }
  return actual;
}

function verifyRuntimeIdentity(projectRoot, httpPort, expected, onObserved) {
  const actual = collectRuntimeIdentity(projectRoot, httpPort);
  if (typeof onObserved === "function") onObserved(actual);
  return assertRuntimeIdentity(expected, actual);
}

function createRuntimeIdentityReport(expected) {
  return {
    runtimeMode: null,
    processPath: null,
    coreSha256: null,
    buildIdentity: null,
    payloadClosure: null,
    pid: null,
    httpPort: null,
    verified: false,
    expected: publicRuntimeIdentity(expected),
    statusEndpointIdentityAvailable: false,
    identitySource: "launcher_ports.pid + Get-Process.Path + Core DLL SHA-256 + runtime manifest",
  };
}

function recordObservedRuntimeIdentity(report, actual) {
  const value = publicRuntimeIdentity(actual);
  Object.assign(report, value, { verified: false });
  return report;
}

function recordVerifiedRuntimeIdentity(report, actual) {
  recordObservedRuntimeIdentity(report, actual);
  report.verified = true;
  return report;
}

function checkRuntimeIdentityContract() {
  const shaA = "A".repeat(64);
  const shaB = "B".repeat(64);
  const shaC = "C".repeat(64);
  const manifest = parseRuntimeManifestText([
    "cf7-runtime-manifest-v2",
    "buildIdentityHash\t" + shaA,
    "payloadClosureHash\t" + shaB,
    "file\truntime/" + CORE_DLL_NAME + "\t123\t" + shaC,
    "",
  ].join("\n"), "check manifest");
  if (manifest.buildIdentity !== shaA || manifest.payloadClosure !== shaB
      || manifest.coreDll.sha256 !== shaC || manifest.coreDll.size !== 123) {
    throw new Error("runtime identity manifest self-check failed");
  }
  const invalidManifests = [
    [
      "cf7-runtime-manifest-v2",
      "buildIdentityHash\t" + shaA,
      "buildIdentityHash\t" + shaA,
      "payloadClosureHash\t" + shaB,
      "file\truntime/" + CORE_DLL_NAME + "\t123\t" + shaC,
    ].join("\n"),
    [
      "cf7-runtime-manifest-v2",
      "buildIdentityHash\t" + shaA,
      "payloadClosureHash\t" + shaB,
      "file\truntime/" + CORE_DLL_NAME + "\t123\t" + shaC + "\textra",
    ].join("\n"),
  ];
  invalidManifests.forEach((invalid, index) => {
    let rejected = false;
    try {
      parseRuntimeManifestText(invalid, "invalid check manifest " + index);
    } catch (error) {
      rejected = error && error.code === "runtime_identity_manifest_invalid";
    }
    if (!rejected) throw new Error("invalid runtime manifest self-check failed: " + index);
  });

  const expected = {
    runtimeMode: "isolated_candidate",
    processPath: path.join("C:\\", "check", "runtime", CORE_EXE_NAME),
    coreSha256: shaC,
    buildIdentity: shaA,
    payloadClosure: shaB,
  };
  assertRuntimeIdentity(expected, Object.assign({}, expected));
  const mismatches = [
    { runtimeMode: "formal_runtime" },
    { processPath: path.join("C:\\", "other", "runtime", CORE_EXE_NAME) },
    { coreSha256: shaB },
    { buildIdentity: shaB },
    { payloadClosure: shaA },
  ];
  mismatches.forEach((change) => {
    let rejected = false;
    try {
      assertRuntimeIdentity(expected, Object.assign({}, expected, change));
    } catch (error) {
      rejected = error && error.code === "runtime_identity_mismatch";
    }
    if (!rejected) {
      throw new Error("runtime identity mismatch self-check failed for " + Object.keys(change)[0]);
    }
  });
  const observedReport = createRuntimeIdentityReport(expected);
  recordObservedRuntimeIdentity(
    observedReport,
    Object.assign({}, expected, { runtimeMode: "formal_runtime" })
  );
  if (observedReport.verified !== false || observedReport.runtimeMode !== "formal_runtime"
      || !observedReport.expected
      || observedReport.expected.runtimeMode !== "isolated_candidate") {
    throw new Error("runtime identity mismatch report self-check failed");
  }
  const candidateStartArgs = buildLauncherStartArguments("start.ps1", Object.assign({}, expected, {
    installRoot: path.join("C:\\", "check"),
  }));
  const formalStartArgs = buildLauncherStartArguments("start.ps1", Object.assign({}, expected, {
    runtimeMode: "formal_runtime",
  }));
  if (candidateStartArgs.slice(-2).join("|") !== "-CandidateRoot|C:\\check"
      || formalStartArgs.includes("-CandidateRoot")) {
    throw new Error("runtime candidate launch argument self-check failed");
  }
  return { checks: 12 };
}

module.exports = {
  RuntimeIdentityError,
  assertRuntimeIdentity,
  buildLauncherStartArguments,
  checkRuntimeIdentityContract,
  collectRuntimeIdentity,
  createRuntimeIdentityReport,
  parseRuntimeManifestText,
  publicRuntimeIdentity,
  recordObservedRuntimeIdentity,
  recordVerifiedRuntimeIdentity,
  resolveExpectedRuntimeIdentity,
  verifyRuntimeIdentity,
};
