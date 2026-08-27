"use strict";

const fs = require("fs");
const path = require("path");
const {
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

const EVENT_SCHEMA = "arena-calibration.journal-event.v1";
const COMMIT_SCHEMA = "arena-calibration.durable-commit.v1";
const CHECKPOINT_SCHEMA = "arena-calibration.campaign-checkpoint.v1";

class WriterLeaseError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = "WriterLeaseError";
    this.code = code || "writer_lease_error";
    this.details = details || null;
  }
}

class JournalIntegrityError extends Error {
  constructor(message, details) {
    super(message);
    this.name = "JournalIntegrityError";
    this.code = "journal_integrity_error";
    this.details = details || null;
  }
}

class InjectedJournalCrash extends Error {
  constructor(point) {
    super(`injected journal crash at ${point}`);
    this.name = "InjectedJournalCrash";
    this.code = point === "after_second_flush_before_ack" ? "ack_lost" : "injected_crash";
    this.point = point;
  }
}

function safeCampaignId(value) {
  const id = String(value || "");
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id)) {
    throw new Error(`invalid campaignId: ${id}`);
  }
  return id;
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function processIsRunning(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (_error) {
    return false;
  }
}

function fsyncDirectoryBestEffort(directory) {
  let fd = null;
  try {
    fd = fs.openSync(directory, "r");
    fs.fsyncSync(fd);
  } catch (_error) {
    // Windows does not consistently permit directory handles through Node.
  } finally {
    if (fd !== null) fs.closeSync(fd);
  }
}

function writeJsonAtomic(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  const fd = fs.openSync(temporary, "wx");
  try {
    fs.writeFileSync(fd, `${JSON.stringify(value, null, 2)}\n`, "utf8");
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temporary, filePath);
  fsyncDirectoryBestEffort(path.dirname(filePath));
}

function readLineRecords(filePath) {
  const buffer = fs.readFileSync(filePath);
  const records = [];
  let start = 0;
  for (let index = 0; index < buffer.length; index += 1) {
    if (buffer[index] !== 0x0a) continue;
    const raw = buffer.subarray(start, index).toString("utf8").replace(/\r$/, "");
    if (raw.length > 0) records.push({ offset: start, raw, complete: true });
    start = index + 1;
  }
  if (start < buffer.length) {
    records.push({ offset: start, raw: buffer.subarray(start).toString("utf8"), complete: false });
  }
  return records;
}

function parseSegmentNumber(name) {
  const match = /^segment-(\d+)\.(open|closed|orphaned)\.jsonl$/.exec(name);
  return match ? Number(match[1]) : null;
}

class DurableCampaignJournal {
  constructor(options) {
    options = options || {};
    this.campaignId = safeCampaignId(options.campaignId);
    this.root = path.resolve(options.root, this.campaignId);
    this.eventsDir = path.join(this.root, "events");
    this.leasesDir = path.join(this.root, "leases");
    this.lockPath = path.join(this.root, "writer.lock.json");
    this.checkpointPath = path.join(this.root, "checkpoint.json");
    this.indexPath = path.join(this.root, "segment-index.json");
    this.clock = options.clock || (() => new Date().toISOString());
    this.leaseTtlMs = options.leaseTtlMs || 5 * 60 * 1000;
    this.lease = null;
    this.state = null;
  }

  _ensureDirectories() {
    fs.mkdirSync(this.eventsDir, { recursive: true });
    fs.mkdirSync(this.leasesDir, { recursive: true });
  }

  _archiveLease(prefix) {
    if (!fs.existsSync(this.lockPath)) return null;
    const destination = path.join(
      this.leasesDir,
      `${prefix}-${new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 17)}-${process.pid}.json`
    );
    fs.renameSync(this.lockPath, destination);
    return destination;
  }

  acquireWriter(options) {
    options = options || {};
    this._ensureDirectories();
    if (this.lease) throw new WriterLeaseError("writer lease is already held by this instance", "writer_already_held");
    if (fs.existsSync(this.lockPath)) {
      let existing = null;
      try { existing = JSON.parse(fs.readFileSync(this.lockPath, "utf8")); } catch (_error) { }
      const expired = existing && Date.parse(existing.expiresAt) <= Date.parse(this.clock());
      const dead = existing && !processIsRunning(existing.pid);
      if (!(options.allowStaleRecovery === true && expired && dead)) {
        throw new WriterLeaseError("campaign writer lease is already held", "writer_contention", existing);
      }
      this._archiveLease("stale");
    }
    const acquiredAt = this.clock();
    const lease = {
      schema: "arena-calibration.writer-lease.v1",
      leaseId: `writer-${process.pid}-${Date.now()}`,
      campaignId: this.campaignId,
      pid: process.pid,
      acquiredAt,
      expiresAt: new Date(Date.parse(acquiredAt) + this.leaseTtlMs).toISOString(),
    };
    const fd = fs.openSync(this.lockPath, "wx");
    try {
      fs.writeFileSync(fd, `${JSON.stringify(lease, null, 2)}\n`, "utf8");
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    this.lease = lease;
    this.state = this.recover({ repairTail: true });
    if (this.state.truncatedTail) {
      this.append("truncated_tail", this.state.truncatedTail);
      this.state.truncatedTail = null;
    }
    return { ...lease };
  }

  releaseWriter(reason) {
    if (!this.lease) return null;
    const lease = { ...this.lease, releasedAt: this.clock(), releaseReason: reason || "normal" };
    writeJsonAtomic(this.lockPath, lease);
    const archived = this._archiveLease("released");
    this.lease = null;
    return archived;
  }

  _assertWriter() {
    if (!this.lease) throw new WriterLeaseError("campaign writer lease is not held", "writer_not_held");
    if (!fs.existsSync(this.lockPath)) throw new WriterLeaseError("campaign writer lease file disappeared", "writer_lease_lost");
    const current = JSON.parse(fs.readFileSync(this.lockPath, "utf8"));
    if (current.leaseId !== this.lease.leaseId || current.pid !== process.pid) {
      throw new WriterLeaseError("campaign writer lease identity changed", "writer_lease_lost", current);
    }
  }

  _segmentFiles() {
    this._ensureDirectories();
    return fs.readdirSync(this.eventsDir)
      .map((name) => ({ name, number: parseSegmentNumber(name) }))
      .filter((entry) => entry.number !== null)
      .sort((left, right) => left.number - right.number || left.name.localeCompare(right.name));
  }

  _scanSegments() {
    const events = [];
    let expectedSequence = 1;
    let previousHash = "GENESIS";
    let maximumSegment = 0;
    let openSegment = null;
    let truncatedTail = null;

    for (const entry of this._segmentFiles()) {
      maximumSegment = Math.max(maximumSegment, entry.number);
      const filePath = path.join(this.eventsDir, entry.name);
      const isClosed = entry.name.includes(".closed.");
      const isOrphaned = entry.name.includes(".orphaned.");
      if (entry.name.includes(".open.")) {
        if (openSegment) throw new JournalIntegrityError("multiple open journal segments exist");
        openSegment = { number: entry.number, name: entry.name, path: filePath };
      }
      const records = readLineRecords(filePath);
      for (let index = 0; index < records.length;) {
        const eventRecord = records[index];
        let event;
        try { event = eventRecord.complete ? JSON.parse(eventRecord.raw) : null; } catch (_error) { event = null; }
        if (!event || event.recordKind !== "event") {
          if (isClosed) throw new JournalIntegrityError(`closed segment has invalid event at offset ${eventRecord.offset}`, { filePath });
          if (!isOrphaned) {
            truncatedTail = { segment: entry.name, offset: eventRecord.offset, reason: "invalid_or_incomplete_event" };
          }
          break;
        }
        assertSchemaInstance(EVENT_SCHEMA, event, `${entry.name} event`);
        if (event.campaignId !== this.campaignId || event.sequence !== expectedSequence || event.previousHash !== previousHash) {
          throw new JournalIntegrityError(`journal event chain mismatch at sequence ${event.sequence}`, { filePath, event });
        }
        if (event.eventHash !== sha256OfValue(withoutHash(event, "eventHash"))) {
          throw new JournalIntegrityError(`journal event hash mismatch at sequence ${event.sequence}`, { filePath });
        }
        const commitRecord = records[index + 1];
        let commit;
        try { commit = commitRecord && commitRecord.complete ? JSON.parse(commitRecord.raw) : null; } catch (_error) { commit = null; }
        if (!commit || commit.recordKind !== "durable_commit") {
          if (isClosed) throw new JournalIntegrityError(`closed segment is missing durable commit for sequence ${event.sequence}`, { filePath });
          if (!isOrphaned) {
            truncatedTail = { segment: entry.name, offset: eventRecord.offset, reason: "event_without_durable_commit" };
          }
          break;
        }
        assertSchemaInstance(COMMIT_SCHEMA, commit, `${entry.name} durable commit`);
        if (
          commit.campaignId !== this.campaignId
          || commit.segmentId !== event.segmentId
          || commit.sequence !== event.sequence
          || commit.eventHash !== event.eventHash
          || commit.segmentOffset !== eventRecord.offset
        ) {
          throw new JournalIntegrityError(`durable commit does not match event ${event.sequence}`, { filePath, commit });
        }
        if (commit.commitHash !== sha256OfValue(withoutHash(commit, "commitHash"))) {
          throw new JournalIntegrityError(`durable commit hash mismatch at sequence ${event.sequence}`, { filePath });
        }
        events.push({ event, commit, filePath });
        expectedSequence += 1;
        previousHash = event.eventHash;
        index += 2;
      }
      if (truncatedTail) break;
    }
    return { events, expectedSequence, previousHash, maximumSegment, openSegment, truncatedTail };
  }

  _deriveState(scan) {
    let campaignState = "READY";
    const committedRunKeys = new Set();
    scan.events.forEach(({ event }) => {
      if (event.eventType === "idle_grant_accepted" || event.eventType === "campaign_resumed") campaignState = "RUNNING";
      if (event.eventType === "campaign_paused") campaignState = "PAUSED";
      if (event.eventType === "exception_recorded" && event.payload.severity === "failed_closed") campaignState = "FAILED_CLOSED";
      if (event.eventType === "result_committed" && event.payload.runKey) committedRunKeys.add(event.payload.runKey);
    });
    return {
      campaignState,
      committedRunKeys,
      lastSequence: scan.expectedSequence - 1,
      lastEventHash: scan.previousHash,
      maximumSegment: scan.maximumSegment,
      openSegment: scan.openSegment,
      events: scan.events,
      truncatedTail: scan.truncatedTail,
    };
  }

  recover(options) {
    options = options || {};
    this._ensureDirectories();
    let scan = this._scanSegments();
    if (scan.truncatedTail && options.repairTail) {
      this._assertWriter();
      const originalTail = { ...scan.truncatedTail };
      if (!scan.openSegment || scan.openSegment.name !== scan.truncatedTail.segment) {
        throw new JournalIntegrityError("truncated tail is not in the unique open segment", scan.truncatedTail);
      }
      const orphaned = scan.openSegment.path.replace(".open.jsonl", ".orphaned.jsonl");
      fs.renameSync(scan.openSegment.path, orphaned);
      fsyncDirectoryBestEffort(this.eventsDir);
      scan = this._scanSegments();
      scan.truncatedTail = {
        ...originalTail,
        repairedFrom: path.basename(orphaned),
        original: options.originalTail || "uncommitted_tail_excluded",
      };
    }
    const state = this._deriveState(scan);
    this.state = state;
    if (this.lease) this._writeCheckpoint();
    return state;
  }

  _nextSegment() {
    const number = (this.state ? this.state.maximumSegment : 0) + 1;
    const segmentId = `segment-${String(number).padStart(6, "0")}`;
    const filePath = path.join(this.eventsDir, `${segmentId}.open.jsonl`);
    const fd = fs.openSync(filePath, "wx");
    fs.closeSync(fd);
    this.state.maximumSegment = number;
    this.state.openSegment = { number, name: path.basename(filePath), path: filePath };
    this._writeIndex();
    return this.state.openSegment;
  }

  _ensureOpenSegment() {
    if (this.state.openSegment && fs.existsSync(this.state.openSegment.path)) return this.state.openSegment;
    return this._nextSegment();
  }

  _writeIndex() {
    const index = {
      schema: "arena-calibration.segment-index.v1",
      campaignId: this.campaignId,
      openSegmentId: this.state.openSegment ? `segment-${String(this.state.openSegment.number).padStart(6, "0")}` : null,
      maximumSegment: this.state.maximumSegment,
      lastSequence: this.state.lastSequence,
      lastEventHash: this.state.lastEventHash,
      updatedAt: this.clock(),
    };
    writeJsonAtomic(this.indexPath, index);
  }

  _writeCheckpoint() {
    if (!this.state) return;
    const checkpoint = {
      schema: CHECKPOINT_SCHEMA,
      campaignId: this.campaignId,
      state: this.state.campaignState,
      lastSequence: this.state.lastSequence,
      lastEventHash: this.state.lastEventHash,
      committedRunKeys: Array.from(this.state.committedRunKeys).sort(),
      openSegmentId: this.state.openSegment ? `segment-${String(this.state.openSegment.number).padStart(6, "0")}` : null,
      recoveredAt: this.clock(),
      checkpointHash: "",
    };
    checkpoint.checkpointHash = sha256OfValue(withoutHash(checkpoint, "checkpointHash"));
    assertSchemaInstance(CHECKPOINT_SCHEMA, checkpoint, "campaign checkpoint");
    writeJsonAtomic(this.checkpointPath, checkpoint);
    this._writeIndex();
  }

  append(eventType, payload, options) {
    options = options || {};
    this._assertWriter();
    if (!this.state) this.state = this.recover({ repairTail: true });
    const segment = this._ensureOpenSegment();
    const segmentId = `segment-${String(segment.number).padStart(6, "0")}`;
    const sequence = this.state.lastSequence + 1;
    const event = {
      schema: EVENT_SCHEMA,
      recordKind: "event",
      campaignId: this.campaignId,
      segmentId,
      sequence,
      previousHash: this.state.lastEventHash,
      eventType,
      occurredAt: options.occurredAt || this.clock(),
      payload: payload || {},
      eventHash: "",
    };
    event.eventHash = sha256OfValue(withoutHash(event, "eventHash"));
    assertSchemaInstance(EVENT_SCHEMA, event, "journal event");
    const offset = fs.statSync(segment.path).size;
    const fd = fs.openSync(segment.path, "a");
    let commit = null;
    try {
      fs.writeSync(fd, `${JSON.stringify(event)}\n`, null, "utf8");
      if (options.faultPoint === "before_first_flush") throw new InjectedJournalCrash(options.faultPoint);
      fs.fsyncSync(fd);
      if (options.faultPoint === "after_first_flush") throw new InjectedJournalCrash(options.faultPoint);
      commit = {
        schema: COMMIT_SCHEMA,
        recordKind: "durable_commit",
        campaignId: this.campaignId,
        segmentId,
        sequence,
        eventHash: event.eventHash,
        segmentOffset: offset,
        committedAt: options.committedAt || this.clock(),
        commitHash: "",
      };
      commit.commitHash = sha256OfValue(withoutHash(commit, "commitHash"));
      assertSchemaInstance(COMMIT_SCHEMA, commit, "durable commit");
      const commitLine = `${JSON.stringify(commit)}\n`;
      if (options.faultPoint === "before_second_flush") {
        fs.writeSync(fd, commitLine.slice(0, Math.max(1, Math.floor(commitLine.length / 2))), null, "utf8");
        throw new InjectedJournalCrash(options.faultPoint);
      }
      fs.writeSync(fd, commitLine, null, "utf8");
      fs.fsyncSync(fd);
      if (options.faultPoint === "after_second_flush_before_ack") {
        throw new InjectedJournalCrash(options.faultPoint);
      }
    } finally {
      fs.closeSync(fd);
    }
    this.state.lastSequence = sequence;
    this.state.lastEventHash = event.eventHash;
    this.state.events.push({ event, commit, filePath: segment.path });
    if (eventType === "result_committed" && payload.runKey) this.state.committedRunKeys.add(payload.runKey);
    if (eventType === "idle_grant_accepted" || eventType === "campaign_resumed") this.state.campaignState = "RUNNING";
    if (eventType === "campaign_paused") this.state.campaignState = "PAUSED";
    if (eventType === "exception_recorded" && payload.severity === "failed_closed") this.state.campaignState = "FAILED_CLOSED";
    this._writeCheckpoint();
    return { event, commit };
  }

  appendResultOnce(runKey, payload, options) {
    this._assertWriter();
    if (this.state.committedRunKeys.has(runKey)) {
      const first = this.state.events.find(({ event }) => event.eventType === "result_committed" && event.payload.runKey === runKey);
      const duplicate = this.append("duplicate_excluded", {
        runKey,
        firstSequence: first ? first.event.sequence : null,
        excludedArtifactHash: payload.artifactHash || null,
        reason: "first_valid_durable_commit_wins",
      }, options);
      return { accepted: false, duplicate, first: first || null };
    }
    const committed = this.append("result_committed", { ...payload, runKey }, options);
    return { accepted: true, committed };
  }

  closeSegment(reason, options) {
    this._assertWriter();
    if (!this.state.openSegment) return null;
    const current = this.state.openSegment;
    const receipt = this.append("segment_close", {
      reason: reason || "normal",
      closingSequence: this.state.lastSequence + 1,
    }, options);
    const closedPath = current.path.replace(".open.jsonl", ".closed.jsonl");
    fs.renameSync(current.path, closedPath);
    fsyncDirectoryBestEffort(this.eventsDir);
    this.state.openSegment = null;
    this._writeCheckpoint();
    return { ...receipt, closedPath };
  }

  snapshot() {
    if (!this.state) this.state = this.recover({ repairTail: false });
    return {
      campaignId: this.campaignId,
      campaignState: this.state.campaignState,
      lastSequence: this.state.lastSequence,
      lastEventHash: this.state.lastEventHash,
      committedRunKeys: Array.from(this.state.committedRunKeys).sort(),
      eventCount: this.state.events.length,
      openSegment: this.state.openSegment ? this.state.openSegment.name : null,
    };
  }
}

module.exports = {
  CHECKPOINT_SCHEMA,
  COMMIT_SCHEMA,
  DurableCampaignJournal,
  EVENT_SCHEMA,
  InjectedJournalCrash,
  JournalIntegrityError,
  WriterLeaseError,
  readLineRecords,
  writeJsonAtomic,
};
