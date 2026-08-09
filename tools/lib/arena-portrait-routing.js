"use strict";

const fs = require("fs");
const path = require("path");

const DRESSUP_PORTRAIT_PREFIX = "主角-";
const DRESSUP_MANIFEST_PATH = path.resolve(
  __dirname,
  "..", "..", "launcher", "web", "assets", "dressup", "manifest.json"
);
const DRESSUP_EQUIPMENT_FIELDS = Object.freeze([
  "head", "body", "hand", "leg", "foot", "neck",
  "primary", "secondary", "secondary1", "secondary2", "melee", "grenade",
]);

// units.json contains a small set of historical display names that never became
// item keys in the canonical dressup manifest. Keep the compatibility mapping
// explicit and reviewable: an unknown name must never silently disappear.
const LEGACY_EQUIPMENT_ALIASES = Object.freeze({
  "远古诛神手套": "黄金骑士牙狼手套",
  "A兵团战术制式手套": "A兵团制式战术手套",
  "三阶黑色皮手套": "黑色皮手套",
  "褐色圆头皮鞋": "棕色圆头皮鞋",
});

const HAIR_COMPAT_ALIASES = Object.freeze({
  "发型-女式-红马尾": "发型-女式-玫红色马尾",
  "发型-女式-白长发": "发型-女式-银色清爽直发",
  "发型-男式-黑尖长发": "发型-男式-黑长发",
  "发型-男式-黑短发": "发型-男式-精武短发",
});

// The dressup asset manifest records these three legacy male arm symbols as
// intentionally unavailable while retaining the covered torso. This is the
// only permitted partial canonical item in the Arena mercenary projection.
const KNOWN_UNAVAILABLE_MERC_SKIN_KEYS = Object.freeze({
  "军绿防弹衣": Object.freeze([
    "男变装-二阶军绿防弹衣上臂",
    "男变装-二阶军绿防弹衣左下臂",
    "男变装-二阶军绿防弹衣右下臂",
  ]),
});

let defaultManifest = null;

function text(value) {
  return value == null ? "" : String(value).trim();
}

function loadDressupManifest() {
  if (!defaultManifest) {
    defaultManifest = JSON.parse(fs.readFileSync(DRESSUP_MANIFEST_PATH, "utf8"));
  }
  return defaultManifest;
}

function isDressupPortraitRef(value) {
  return text(value).startsWith(DRESSUP_PORTRAIT_PREFIX);
}

// Match ArenaPanelService.as exactly: only explicit male encodings are male;
// missing or unknown legacy values fail soft to female.
function normalizeLegacyGender(value) {
  const raw = text(value);
  return raw === "男" || raw === "主角-男" || raw === "1" ? "男" : "女";
}

function stripEnhancement(value) {
  return text(value).split("#", 1)[0].trim();
}

function skinCovered(manifest, key) {
  return !!(key && manifest && manifest.skinKeys && manifest.skinKeys[key]
    && manifest.skinKeys[key].covered === true);
}

function issue(issues, code, field, value, detail) {
  issues.push({
    code,
    field,
    value: text(value),
    detail: detail || "",
  });
}

function resolveFace(manifest, value, gender, issues) {
  const raw = text(value);
  const fallback = gender === "女" ? "女变装-基本脸型" : "男变装-基本脸型";
  let resolved = raw;
  if (!resolved) resolved = fallback;
  else if (/^\d+$/.test(resolved)) {
    resolved = manifest && manifest.appearance && manifest.appearance.faceById
      ? text(manifest.appearance.faceById[resolved]) : "";
    if (!resolved) {
      issue(issues, "unknown_face_id", "face", raw);
      return "";
    }
  }
  if (!skinCovered(manifest, resolved)) {
    issue(issues, "uncovered_face", "face", raw, resolved);
    return "";
  }
  return resolved;
}

function resolveHair(manifest, value, issues, aliases) {
  const raw = text(value);
  if (!raw || raw === "-1" || raw === "光头") return "";
  let resolved = raw;
  if (/^\d+$/.test(resolved)) {
    resolved = manifest && manifest.appearance && manifest.appearance.hairById
      ? text(manifest.appearance.hairById[resolved]) : "";
    if (!resolved) {
      issue(issues, "unknown_hair_id", "hair", raw);
      return "";
    }
  }
  if (resolved === "光头") return "";
  if (HAIR_COMPAT_ALIASES[resolved]) {
    const requested = resolved;
    resolved = HAIR_COMPAT_ALIASES[resolved];
    aliases.push({ kind: "hair", field: "hair", requested, canonical: resolved });
  }
  if (!skinCovered(manifest, resolved)) {
    issue(issues, "uncovered_hair", "hair", raw, resolved);
    return "";
  }
  return resolved;
}

function validateItemBindings(manifest, itemName, item, gender, field, issues, requireCoveredBindings) {
  const byGender = item && item.fieldsByGender;
  if (!byGender || typeof byGender !== "object") {
    issue(issues, "equipment_bindings_missing", field, itemName);
    return;
  }
  const genderKeys = Object.keys(byGender);
  // Some canonical neck/accessory items are intentionally non-visual and
  // therefore have an empty fieldsByGender map. They are resolved, not unknown.
  if (genderKeys.length === 0) return;
  const fields = byGender[gender];
  if (!fields || typeof fields !== "object") {
    issue(issues, "equipment_gender_binding_missing", field, itemName, gender);
    return;
  }
  for (const skinKey of Object.values(fields)) {
    const allowed = requireCoveredBindings && requireCoveredBindings[itemName];
    const allowKnownUnavailable = Array.isArray(allowed) && allowed.indexOf(skinKey) !== -1;
    if (!skinCovered(manifest, skinKey) && !allowKnownUnavailable) {
      issue(issues, "equipment_skin_uncovered", field, itemName, text(skinKey));
    }
  }
}

function resolveEquipment(manifest, source, fields, gender, issues, aliases, requireCoveredBindings) {
  const equipment = {};
  for (const field of fields) {
    const raw = stripEnhancement(source && source[field]);
    if (!raw) continue;
    const canonical = LEGACY_EQUIPMENT_ALIASES[raw] || raw;
    if (canonical !== raw) {
      aliases.push({ kind: "equipment", field, requested: raw, canonical });
    }
    const item = manifest && manifest.items ? manifest.items[canonical] : null;
    if (!item) {
      issue(issues, "unknown_equipment", field, raw, canonical);
      continue;
    }
    validateItemBindings(manifest, canonical, item, gender, field, issues, requireCoveredBindings);
    equipment[field] = canonical;
  }
  return equipment;
}

function inspectActor(source, options) {
  options = options || {};
  const manifest = options.manifest || loadDressupManifest();
  const issues = [];
  const aliases = [];
  if (!manifest || manifest.schema !== "cf7-dressup-manifest-v1") {
    issue(issues, "unsupported_manifest", "manifest", manifest && manifest.schema);
    return { portrait: null, issues, aliases };
  }
  const gender = normalizeLegacyGender(source && source.gender);
  const face = resolveFace(manifest, source && source.face, gender, issues);
  const hair = resolveHair(manifest, source && (source.hairstyle != null ? source.hairstyle : source.hair), issues, aliases);
  const fields = options.equipmentFields || DRESSUP_EQUIPMENT_FIELDS;
  const equipmentSource = options.equipmentSource || source || {};
  const equipment = resolveEquipment(
    manifest, equipmentSource, fields, gender, issues, aliases,
    options.requireCoveredBindings
  );
  const portrait = issues.length ? null : {
    kind: "dressup",
    actor: { gender, face, hair, equipment },
  };
  return { portrait, issues, aliases };
}

function inspectDressupPortrait(unit, options) {
  if (!unit || !isDressupPortraitRef(unit.spritename)) {
    return {
      portrait: null,
      issues: [{ code: "not_dressup_unit", field: "spritename", value: text(unit && unit.spritename), detail: "" }],
      aliases: [],
    };
  }
  const data = unit.data && typeof unit.data === "object" ? unit.data : null;
  if (!data) {
    return {
      portrait: null,
      issues: [{ code: "dressup_data_missing", field: "data", value: "", detail: "" }],
      aliases: [],
    };
  }
  return inspectActor(data, options);
}

function projectDressupPortrait(unit, options) {
  return inspectDressupPortrait(unit, options).portrait;
}

function inspectMercDressupPortrait(merc, options) {
  options = options || {};
  const equipment = merc && merc.equipment && typeof merc.equipment === "object"
    ? merc.equipment : {};
  const equipmentFields = Object.keys(equipment).sort();
  return inspectActor(merc || {}, {
    manifest: options.manifest,
    equipmentSource: equipment,
    equipmentFields,
    // Preserve the one audited partial legacy item, but reject every other
    // uncovered binding (including any future drift in this same item).
    requireCoveredBindings: KNOWN_UNAVAILABLE_MERC_SKIN_KEYS,
  });
}

function projectMercDressupPortrait(merc, options) {
  return inspectMercDressupPortrait(merc, options).portrait;
}

module.exports = {
  DRESSUP_EQUIPMENT_FIELDS,
  DRESSUP_MANIFEST_PATH,
  DRESSUP_PORTRAIT_PREFIX,
  HAIR_COMPAT_ALIASES,
  KNOWN_UNAVAILABLE_MERC_SKIN_KEYS,
  LEGACY_EQUIPMENT_ALIASES,
  inspectDressupPortrait,
  inspectMercDressupPortrait,
  isDressupPortraitRef,
  loadDressupManifest,
  normalizeLegacyGender,
  projectDressupPortrait,
  projectMercDressupPortrait,
};
