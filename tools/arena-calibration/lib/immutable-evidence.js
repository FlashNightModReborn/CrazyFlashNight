"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { sha256OfValue } = require("./arena-calibration-core");

function sha256Bytes(bytes) {
  return `sha256:${crypto.createHash("sha256").update(bytes).digest("hex")}`;
}

function writeNewBytes(filePath, value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, "utf8");
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const fd = fs.openSync(filePath, "wx");
  try {
    fs.writeFileSync(fd, bytes);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  return filePath;
}

function writeImmutableBytes(filePath, value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, "utf8");
  try { return writeNewBytes(filePath, bytes); }
  catch (error) {
    if (error.code !== "EEXIST") throw error;
    if (!fs.readFileSync(filePath).equals(bytes)) throw new Error(`immutable evidence collision: ${filePath}`);
    return filePath;
  }
}

function writeImmutableJson(filePath, value) {
  return writeImmutableBytes(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function snapshotBytes(directory, bytes, extension) {
  const sha256 = sha256Bytes(bytes);
  const filePath = path.join(directory, `${sha256.slice(7)}.${extension}`);
  writeImmutableBytes(filePath, bytes);
  return { filePath, sha256 };
}

// The address excludes import wall-clock time. A retry therefore reuses the
// original timestamp and hash instead of changing a durable journal reference.
function persistImmutableRecord(directory, prefix, record, idField, hashField, validate) {
  const identity = { ...record };
  delete identity.createdAt;
  delete identity[idField];
  delete identity[hashField];
  const id = `${prefix}-${sha256OfValue(identity).slice(7)}`;
  const filePath = path.join(directory, `${id}.json`);
  if (fs.existsSync(filePath)) {
    const existing = JSON.parse(fs.readFileSync(filePath, "utf8"));
    const hashInput = { ...existing };
    delete hashInput[hashField];
    const existingIdentity = { ...hashInput };
    delete existingIdentity.createdAt;
    delete existingIdentity[idField];
    if (existing[idField] !== id || existing[hashField] !== sha256OfValue(hashInput)
        || sha256OfValue(existingIdentity) !== sha256OfValue(identity)) {
      throw new Error(`immutable record integrity mismatch: ${filePath}`);
    }
    validate(existing);
    return existing;
  }
  const result = { ...record, [idField]: id };
  delete result[hashField];
  result[hashField] = sha256OfValue(result);
  validate(result);
  writeImmutableJson(filePath, result);
  return result;
}

module.exports = { persistImmutableRecord, sha256Bytes, snapshotBytes, writeImmutableBytes, writeImmutableJson, writeNewBytes };
