"use strict";

const DRESSUP_PORTRAIT_PREFIX = "主角-";
const DRESSUP_EQUIPMENT_FIELDS = Object.freeze([
  "head", "body", "hand", "leg", "foot", "neck",
  "primary", "secondary", "secondary2", "melee", "grenade",
]);

function text(value) {
  return value == null ? "" : String(value).trim();
}

function isDressupPortraitRef(value) {
  return text(value).startsWith(DRESSUP_PORTRAIT_PREFIX);
}

function projectDressupPortrait(unit) {
  if (!unit || !isDressupPortraitRef(unit.spritename)) return null;
  const data = unit.data && typeof unit.data === "object" ? unit.data : null;
  if (!data) return null;

  const equipment = {};
  for (const field of DRESSUP_EQUIPMENT_FIELDS) {
    const value = text(data[field]);
    if (value) equipment[field] = value;
  }
  const face = text(data.face);
  const hair = text(data.hairstyle || data.hair);
  const gender = text(data.gender) || "男";
  if (!face && !hair && Object.keys(equipment).length === 0) return null;

  return {
    kind: "dressup",
    actor: {
      gender,
      face,
      hair,
      equipment,
    },
  };
}

module.exports = {
  DRESSUP_EQUIPMENT_FIELDS,
  DRESSUP_PORTRAIT_PREFIX,
  isDressupPortraitRef,
  projectDressupPortrait,
};
