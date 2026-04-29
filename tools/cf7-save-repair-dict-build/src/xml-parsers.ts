import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { XMLParser } from "fast-xml-parser";

const itemParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  // Items often appear as <item>...</item> repeated; fast-xml-parser collapses
  // single-occurrence to object, multi to array. We always want array.
  isArray: (tagName) => tagName === "item" || tagName === "mod" || tagName === "Hair",
});

const enemyParser = new XMLParser({
  ignoreAttributes: false,
  // Enemy XMLs use the enemy NAME itself as the element tag (e.g. <敌人-黑铁会大叔>).
  // We need preserveOrder=true so we can iterate in document order and read
  // every top-level tag name under <root>.
  preserveOrder: true,
});

function listXmlFiles(dir: string): string[] {
  return readdirSync(dir)
    .filter((f) => f.toLowerCase().endsWith(".xml"))
    .filter((f) => f !== "list.xml" && f !== "asset_source_map.xml")
    .map((f) => join(dir, f));
}

/**
 * Extract item <name> values from data/items/*.xml.
 * Skips manifests (list.xml, asset_source_map.xml) and non-item XMLs (missileConfigs, bullets_cases).
 */
export function parseItemsDir(itemsDir: string): { names: string[]; sourceFiles: string[] } {
  const files = listXmlFiles(itemsDir).filter((f) => {
    // Item-style XMLs all share <root><item>...</item></root>; manifests/configs differ
    const lower = f.toLowerCase();
    return !lower.endsWith("missileconfigs.xml")
      && !lower.endsWith("bullets_cases.xml")
      && !lower.endsWith("hairstyle.xml");
  });
  const names = new Set<string>();
  const sourceFiles: string[] = [];
  for (const file of files) {
    const xml = readFileSync(file, "utf-8");
    const doc = itemParser.parse(xml) as { root?: { item?: Array<{ name?: string }> } };
    const items = doc.root?.item ?? [];
    let added = 0;
    for (const it of items) {
      const name = (it.name ?? "").toString().trim();
      if (name && !name.includes("�")) {
        if (!names.has(name)) added++;
        names.add(name);
      }
    }
    if (added > 0) sourceFiles.push(file);
  }
  return { names: [...names].sort((a, b) => a.localeCompare(b, "zh")), sourceFiles };
}

/**
 * Extract <mod><name> values from data/items/equipment_mods/*.xml.
 */
export function parseModsDir(modsDir: string): { names: string[]; sourceFiles: string[] } {
  const files = listXmlFiles(modsDir);
  const names = new Set<string>();
  const sourceFiles: string[] = [];
  for (const file of files) {
    const xml = readFileSync(file, "utf-8");
    const doc = itemParser.parse(xml) as { root?: { mod?: Array<{ name?: string }> } };
    const mods = doc.root?.mod ?? [];
    let added = 0;
    for (const m of mods) {
      const name = (m.name ?? "").toString().trim();
      if (name && !name.includes("�")) {
        if (!names.has(name)) added++;
        names.add(name);
      }
    }
    if (added > 0) sourceFiles.push(file);
  }
  return { names: [...names].sort((a, b) => a.localeCompare(b, "zh")), sourceFiles };
}

/**
 * Extract enemy element names from data/enemy_properties/*.xml.
 * Each top-level child of <root> whose tag name starts with "敌人-" is an enemy entry;
 * the tag name itself is the dictionary value.
 *
 * Skips "默认" (default template) and any tags not matching the "敌人-..." prefix.
 */
export function parseEnemiesDir(enemiesDir: string): { names: string[]; sourceFiles: string[] } {
  const files = listXmlFiles(enemiesDir);
  const names = new Set<string>();
  const sourceFiles: string[] = [];
  for (const file of files) {
    const xml = readFileSync(file, "utf-8");
    // preserveOrder=true returns: [{ "?xml": [...], ":@": {...} }, { root: [ ... children ... ] }]
    const doc = enemyParser.parse(xml) as Array<Record<string, unknown>>;
    const rootEntry = doc.find((e) => "root" in e) as { root: Array<Record<string, unknown>> } | undefined;
    if (!rootEntry) continue;
    let added = 0;
    for (const child of rootEntry.root) {
      const childTag = Object.keys(child).find((k) => k !== ":@");
      if (!childTag) continue;
      if (childTag === "默认") continue;
      if (!childTag.startsWith("敌人-") && !childTag.startsWith("主角-") && !childTag.startsWith("修改器")) continue;
      if (childTag.includes("�")) continue;
      if (!names.has(childTag)) added++;
      names.add(childTag);
    }
    if (added > 0) sourceFiles.push(file);
  }
  return { names: [...names].sort((a, b) => a.localeCompare(b, "zh")), sourceFiles };
}

/**
 * Extract <Hair><Identifier> values from data/items/hairstyle.xml.
 */
export function parseHairstyleFile(file: string): string[] {
  const xml = readFileSync(file, "utf-8");
  const doc = itemParser.parse(xml) as { HairStyle?: { Hair?: Array<{ Identifier?: string }> } };
  const entries = doc.HairStyle?.Hair ?? [];
  const names: string[] = [];
  for (const e of entries) {
    const id = (e.Identifier ?? "").toString().trim();
    if (id && !id.includes("�")) names.push(id);
  }
  return [...new Set(names)].sort((a, b) => a.localeCompare(b, "zh"));
}
