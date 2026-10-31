"use strict";

// units.json is the only identity authority. Names and linkage are not aliases.
const MAX_ID = 2147483647;
const MAX_KEY_LENGTH = 96;
const LEGACY_TYPE = /^兵种(0|[1-9][0-9]*)$/;
const SEMANTIC_KEY = /^[A-Za-z\u3400-\u9fff][A-Za-z0-9_\u3400-\u9fff-]*(?:\.[A-Za-z0-9_\u3400-\u9fff·-]+)+$/;
const RESERVED_SEGMENTS = new Set(["__proto__", "prototype", "constructor"]);

function validKey(value) {
  return typeof value === "string" && value.length <= MAX_KEY_LENGTH
    && SEMANTIC_KEY.test(value)
    && !value.split(".").some(part => RESERVED_SEGMENTS.has(part));
}

class UnitRegistry {
  constructor(units) {
    if (!Array.isArray(units) || units.length === 0) {
      throw new Error("Unit registry must be a non-empty array");
    }
    this.byId = new Map();
    this.byKey = new Map();
    units.forEach((unit, index) => {
      const label = "units[" + index + "]";
      if (!unit || typeof unit !== "object" || Array.isArray(unit)
          || !Number.isInteger(unit.id) || unit.id < 0 || unit.id > MAX_ID) {
        throw new Error(label + ": invalid unit id");
      }
      if (this.byId.has(unit.id)) throw new Error(label + ": duplicate unit id " + unit.id);
      if (typeof unit.spritename !== "string" || unit.spritename.length === 0) {
        throw new Error(label + ": missing spritename");
      }
      this.byId.set(unit.id, unit);
      if (Object.prototype.hasOwnProperty.call(unit, "key")) {
        if (!validKey(unit.key)) throw new Error(label + ": invalid unit key " + String(unit.key));
        if (this.byKey.has(unit.key)) throw new Error(label + ": duplicate unit key " + unit.key);
        this.byKey.set(unit.key, unit.id);
      }
    });
  }

  resolveType(reference, context = "unit reference") {
    if (typeof reference !== "string") throw new Error(context + ": unit reference must be a string");
    if (reference.length > MAX_KEY_LENGTH) throw new Error(context + ": unit reference is too long");
    const legacy = LEGACY_TYPE.exec(reference);
    const id = legacy ? Number(legacy[1]) : this.byKey.get(reference);
    if (id === undefined || !this.byId.has(id)) {
      throw new Error(context + ": unknown unit reference " + reference);
    }
    return "兵种" + id;
  }

  resolveId(reference, context = "unit reference") {
    if (typeof reference === "number") {
      if (!Number.isInteger(reference) || !this.byId.has(reference)) {
        throw new Error(context + ": unknown unit id " + reference);
      }
      return reference;
    }
    return Number(this.resolveType(reference, context).slice(2));
  }

  get(reference, context) {
    return this.byId.get(this.resolveId(reference, context));
  }
}

// The arena tools operate on Enemy XML bodies. Only a direct Type is an identity;
// a Parameters.Type or Attribute.Type must never be mistaken for the spawn type.
function extractDirectChildXml(body, childName, context = "Enemy") {
  const tags = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<(\/?)([^\s/>!?]+)(?:[^>"']|"[^"]*"|'[^']*')*>/g;
  let depth = 0;
  let start = -1;
  let found = false;
  let result = null;
  let tag;
  while ((tag = tags.exec(body))) {
    if (!tag[2]) continue;
    if (tag[1]) {
      depth--;
      if (depth === 0 && start >= 0) {
        result = body.slice(start, tag.index);
        start = -1;
      }
    } else {
      const selfClosing = /\/\s*>$/.test(tag[0]);
      if (depth === 0 && tag[2] === childName) {
        if (found) throw new Error(context + ": duplicate direct " + childName);
        found = true;
        if (selfClosing) result = "";
        else start = tags.lastIndex;
      }
      if (!selfClosing) depth++;
    }
  }
  return result;
}

module.exports = { UnitRegistry, validKey, extractDirectChildXml, MAX_ID, MAX_KEY_LENGTH };
