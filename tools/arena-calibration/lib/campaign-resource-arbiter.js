"use strict";

const {
  sha256OfValue,
} = require("./arena-calibration-core");
const { assertSchemaInstance } = require("./schema-registry");

const PRODUCER_REGISTRY_SCHEMA = "arena-calibration.producer-registry.v1";
const IDLE_GRANT_SCHEMA = "arena-calibration.idle-grant.v1";
const REQUIRED_SCOPES = Object.freeze(["launcher", "flash", "arena_runner"]);
const DEFAULT_OBSERVATION_TTL_SECONDS = 60;
const MAX_GRANT_TTL_SECONDS = 300;

class IdleGrantError extends Error {
  constructor(message, code, details) {
    super(message);
    this.name = "IdleGrantError";
    this.code = code || "idle_grant_invalid";
    this.details = details || null;
  }
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function producerSetHash(producers) {
  return sha256OfValue(
    producers
      .map((entry) => ({ producerId: entry.producerId, scope: entry.scope }))
      .sort((left, right) => `${left.scope}|${left.producerId}`.localeCompare(`${right.scope}|${right.producerId}`))
  );
}

function createProducerRegistry(producers, options) {
  options = options || {};
  const generatedAt = options.generatedAt || new Date().toISOString();
  const registry = {
    schema: PRODUCER_REGISTRY_SCHEMA,
    registryId: options.registryId || `producer-registry-${generatedAt.replace(/[^0-9]/g, "").slice(0, 14)}`,
    generatedAt,
    observationTtlSeconds: options.observationTtlSeconds || DEFAULT_OBSERVATION_TTL_SECONDS,
    producers: producers
      .map((entry) => ({ ...entry }))
      .sort((left, right) => `${left.scope}|${left.producerId}`.localeCompare(`${right.scope}|${right.producerId}`)),
    producerSetHash: producerSetHash(producers),
    registryHash: "",
  };
  registry.registryHash = sha256OfValue(withoutHash(registry, "registryHash"));
  assertSchemaInstance(PRODUCER_REGISTRY_SCHEMA, registry, "producer registry");
  return registry;
}

function validateProducerRegistry(registry, options) {
  options = options || {};
  assertSchemaInstance(PRODUCER_REGISTRY_SCHEMA, registry, "producer registry");
  if (registry.producerSetHash !== producerSetHash(registry.producers)) {
    throw new IdleGrantError("producerSetHash does not match the exact producer registry", "producer_set_hash_mismatch");
  }
  if (registry.registryHash !== sha256OfValue(withoutHash(registry, "registryHash"))) {
    throw new IdleGrantError("registryHash does not match registry contents", "registry_hash_mismatch");
  }
  const nowMs = Date.parse(options.now || new Date().toISOString());
  const generatedMs = Date.parse(registry.generatedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(generatedMs)) {
    throw new IdleGrantError("producer registry time is invalid", "registry_time_invalid");
  }
  const ids = new Set();
  registry.producers.forEach((producer) => {
    if (ids.has(producer.producerId)) {
      throw new IdleGrantError(`duplicate producerId: ${producer.producerId}`, "duplicate_producer");
    }
    ids.add(producer.producerId);
    const observedMs = Date.parse(producer.observedAt);
    if (!Number.isFinite(observedMs) || observedMs > nowMs + 5000) {
      throw new IdleGrantError(`producer observation time is invalid: ${producer.producerId}`, "producer_observation_time_invalid");
    }
    if (nowMs - observedMs > registry.observationTtlSeconds * 1000) {
      throw new IdleGrantError(`producer observation is stale: ${producer.producerId}`, "producer_observation_expired");
    }
  });
  REQUIRED_SCOPES.forEach((scope) => {
    if (!registry.producers.some((entry) => entry.scope === scope)) {
      throw new IdleGrantError(`producer registry does not cover ${scope}`, "producer_scope_missing", { scope });
    }
  });
  if (generatedMs > nowMs + 5000) {
    throw new IdleGrantError("producer registry is from the future", "registry_clock_invalid");
  }
  if (nowMs - generatedMs > registry.observationTtlSeconds * 1000) {
    throw new IdleGrantError("producer registry observation is stale", "registry_expired");
  }
  const blocked = registry.producers.filter((entry) => !entry.online || entry.leaseState !== "idle");
  if (blocked.length > 0) {
    throw new IdleGrantError(
      `producer registry is not idle: ${blocked.map((entry) => `${entry.producerId}:${entry.leaseState}`).join(", ")}`,
      "producer_not_idle",
      { producers: blocked }
    );
  }
  return true;
}

function createIdleGrant(registry, options) {
  options = options || {};
  const issuedAt = options.issuedAt || new Date().toISOString();
  validateProducerRegistry(registry, { now: issuedAt });
  const ttlSeconds = options.ttlSeconds || 120;
  if (!Number.isInteger(ttlSeconds) || ttlSeconds < 1 || ttlSeconds > MAX_GRANT_TTL_SECONDS) {
    throw new IdleGrantError(`idle grant ttl must be 1..${MAX_GRANT_TTL_SECONDS} seconds`, "grant_ttl_invalid");
  }
  const grant = {
    schema: IDLE_GRANT_SCHEMA,
    grantId: options.grantId || `idle-grant-${issuedAt.replace(/[^0-9]/g, "").slice(0, 14)}`,
    issuer: options.issuer || "cf7-local-development-arbiter",
    trustProfile: "local-development-arbiter-v1",
    scope: REQUIRED_SCOPES.slice(),
    issuedAt,
    expiresAt: new Date(Date.parse(issuedAt) + ttlSeconds * 1000).toISOString(),
    producerSetHash: registry.producerSetHash,
    registryId: registry.registryId,
    registryHash: registry.registryHash,
    revokeSignal: false,
    grantHash: "",
  };
  grant.grantHash = sha256OfValue(withoutHash(grant, "grantHash"));
  assertSchemaInstance(IDLE_GRANT_SCHEMA, grant, "idle grant");
  return grant;
}

function validateIdleGrant(grant, registry, options) {
  options = options || {};
  assertSchemaInstance(IDLE_GRANT_SCHEMA, grant, "idle grant");
  validateProducerRegistry(registry, options);
  if (grant.grantHash !== sha256OfValue(withoutHash(grant, "grantHash"))) {
    throw new IdleGrantError("grantHash does not match grant contents", "grant_hash_mismatch");
  }
  if (grant.revokeSignal) throw new IdleGrantError("idle grant has been revoked", "grant_revoked");
  if (grant.registryId !== registry.registryId || grant.registryHash !== registry.registryHash) {
    throw new IdleGrantError("idle grant is not bound to the supplied registry snapshot", "grant_registry_mismatch");
  }
  if (grant.producerSetHash !== registry.producerSetHash) {
    throw new IdleGrantError("idle grant producerSetHash does not match registry", "grant_producer_set_mismatch");
  }
  if (options.trustedIssuers && !options.trustedIssuers.includes(grant.issuer)) {
    throw new IdleGrantError(`idle grant issuer is not trusted: ${grant.issuer}`, "grant_issuer_untrusted");
  }
  const scope = new Set(grant.scope);
  REQUIRED_SCOPES.forEach((required) => {
    if (!scope.has(required)) throw new IdleGrantError(`idle grant does not cover ${required}`, "grant_scope_missing");
  });
  const nowMs = Date.parse(options.now || new Date().toISOString());
  const issuedMs = Date.parse(grant.issuedAt);
  const expiresMs = Date.parse(grant.expiresAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(issuedMs) || !Number.isFinite(expiresMs) || expiresMs <= issuedMs) {
    throw new IdleGrantError("idle grant time range is invalid", "grant_time_invalid");
  }
  if (nowMs < issuedMs - 5000) throw new IdleGrantError("idle grant is not active yet", "grant_not_active");
  if (nowMs >= expiresMs) throw new IdleGrantError("idle grant has expired", "grant_expired");
  if (expiresMs - issuedMs > MAX_GRANT_TTL_SECONDS * 1000) {
    throw new IdleGrantError("idle grant exceeds maximum ttl", "grant_ttl_invalid");
  }
  return true;
}

module.exports = {
  DEFAULT_OBSERVATION_TTL_SECONDS,
  IDLE_GRANT_SCHEMA,
  IdleGrantError,
  MAX_GRANT_TTL_SECONDS,
  PRODUCER_REGISTRY_SCHEMA,
  REQUIRED_SCOPES,
  createIdleGrant,
  createProducerRegistry,
  producerSetHash,
  validateIdleGrant,
  validateProducerRegistry,
};
