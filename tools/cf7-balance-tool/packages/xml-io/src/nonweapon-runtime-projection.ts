import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";
import { XMLParser, XMLValidator } from "fast-xml-parser";
import { parseXmlDocument, type XmlDocumentNode } from "./document.js";

const STRIPPABLE = new Set(["armor", "melee", "potion", "explosives"]);
const SCHEMA = "cf7-nonweapon-runtime-projection.v1";
const MANIFEST = "projection-manifest.json";
const parser = new XMLParser({ ignoreAttributes: false, trimValues: true });

interface ItemRow {
  sourceFile: string;
  sourceOrdinal: number;
  nameOccurrence: number;
  name: string;
  family: string;
  node: XmlDocumentNode;
  strip: boolean;
  retainedReason: string | null;
}

interface SourceFile {
  relativePath: string;
  bytes: Buffer;
  source: string;
  parsed: Record<string, unknown>;
  rows: ItemRow[];
}

export interface NonWeaponProjection {
  files: Map<string, Buffer>;
  manifest: Record<string, unknown>;
}

/** Offline ItemDataLoader input only. No loader, author XML or audit ledger is changed. */
export function buildNonWeaponRuntimeProjection(
  repoRoot: string,
  sourceRevision: string
): NonWeaponProjection {
  const itemsRoot = path.join(fs.realpathSync(repoRoot), "data/items");
  const read = (relativePath: string): SourceFile => {
    if (!relativePath.endsWith(".xml") || path.isAbsolute(relativePath)
      || relativePath.split(/[\\/]/).some((part) => part === ".." || part === ".")) {
      throw new Error(`Unsafe item list path: ${relativePath}`);
    }
    const absolute = fs.realpathSync(path.join(itemsRoot, relativePath));
    if (!isInside(itemsRoot, absolute)) throw new Error(`Item input escapes data/items: ${relativePath}`);
    const bytes = fs.readFileSync(absolute);
    const source = bytes.toString("utf8");
    if (!Buffer.from(source).equals(bytes)) throw new Error(`Invalid UTF-8: ${relativePath}`);
    const valid = XMLValidator.validate(source);
    if (valid !== true) throw new Error(`Invalid XML ${relativePath}: ${valid.err.msg}`);
    return { relativePath, bytes, source, parsed: parser.parse(source), rows: [] };
  };
  const list = read("list.xml");
  const listRoot = object(list.parsed.root, "list.xml root");
  const entries = array(listRoot.items).map((entry) => text(entry, "list.xml items"));
  if (entries.length === 0) throw new Error("Item list is empty");
  // Mirrors ItemDataLoader's fallback; item_sets is copied byte-for-byte, never stripped.
  const itemSets = listRoot.itemSets ? text(listRoot.itemSets, "list.xml itemSets") : "item_sets.xml";
  const sources = new Map<string, SourceFile>([["list.xml", list], [itemSets, read(itemSets)]]);
  for (const entry of entries) {
    if (entry === "list.xml" || entry === itemSets) throw new Error(`Invalid items entry: ${entry}`);
    if (sources.has(entry)) continue;
    const source = read(entry);
    const doc = parseXmlDocument(source.source);
    const root = doc.findNode("root");
    if (!root) throw new Error(`Missing root: ${entry}`);
    const nodes = root.children.filter((node) => node.name === "item");
    const items = isObject(source.parsed.root) ? array(source.parsed.root.item) : [];
    if (nodes.length !== items.length) throw new Error(`Ambiguous item structure: ${entry}`);
    const occurrences = new Map<string, number>();
    source.rows = nodes.map((node, sourceOrdinal) => {
      const item = object(items[sourceOrdinal], `${entry} item ${sourceOrdinal}`);
      const name = text(item.name, `${entry} item name`);
      const nameOccurrence = (occurrences.get(name) ?? 0) + 1;
      occurrences.set(name, nameOccurrence);
      const balance = isObject(item.balance) ? item.balance : null;
      const family = item.balance === undefined ? "none"
        : balance && typeof balance.formulaFamily === "string" ? balance.formulaFamily : "unknown";
      let retainedReason: string | null = item.balance === undefined ? "no_balance" : "family_not_in_scope";
      if (STRIPPABLE.has(family)) {
        retainedReason = balance?.schemaVersion === 1 ? null : "unknown_schema";
        // The raw-loader recursive bullet audit is a real reader, even before ItemUtil deletes balance.
        if (containsKey(balance, "bullet")) retainedReason = "recursive_bullet_audit_reader";
      }
      return { sourceFile: entry, sourceOrdinal, nameOccurrence, name, family,
        node, strip: retainedReason === null, retainedReason };
    });
    sources.set(entry, source);
  }
  // Preserve repeated file entries, singleton/array records and list order without name deduplication.
  const catalog = entries.flatMap((entry, listIndex) => sources.get(entry)!.rows.map((row) => ({ row, listIndex })));
  const byName = new Map<string, typeof catalog>();
  for (const entry of catalog) byName.set(entry.row.name, [...(byName.get(entry.row.name) ?? []), entry]);
  for (const entriesForName of byName.values()) {
    if (entriesForName.length < 2) continue;
    // The balance dictionary only assigns when a balance exists. Dropping one duplicate could expose
    // an earlier weapon/foreign balance; keep every duplicate instead of guessing dictionary aliases.
    for (const { row } of entriesForName) {
      if (row.strip) { row.strip = false; row.retainedReason = "duplicate_name"; }
    }
  }
  const files = new Map<string, Buffer>();
  const fileAudit: Record<string, unknown>[] = [];
  const familyCounts: Record<string, number> = {};
  let removedNodes = 0;
  let inputBytes = 0;
  let outputBytes = 0;
  for (const source of sources.values()) {
    let projected = source.source;
    const expected = structuredClone(source.parsed);
    const expectedItems = source.rows.length > 0 ? array(object(expected.root, source.relativePath).item) : [];
    const removals: { start: number; end: number }[] = [];
    for (const row of source.rows) {
      familyCounts[row.family] = (familyCounts[row.family] ?? 0) + 1;
      if (!row.strip) continue;
      const balances = row.node.children.filter((node) => node.name === "balance");
      if (balances.length !== 1 || balances[0]!.endTagEnd === undefined) {
        throw new Error(`Ambiguous balance node: ${source.relativePath}/${row.name}`);
      }
      const balance = balances[0]!;
      removals.push({ start: balance.startTagStart, end: balance.endTagEnd! });
      delete object(expectedItems[row.sourceOrdinal], row.name).balance;
      removedNodes++;
    }
    for (const range of removals.sort((left, right) => right.start - left.start)) {
      projected = projected.slice(0, range.start) + projected.slice(range.end);
    }
    // Equality before ItemUtil's set hydration/id/modslot defaults implies those inputs are unchanged.
    // This parser comparison is an offline structural oracle, not an AVM1 execution claim.
    if (!isDeepStrictEqual(parser.parse(projected), expected)) {
      throw new Error(`Non-balance data changed: ${source.relativePath}`);
    }
    const bytes = Buffer.from(projected);
    const relativePath = `data/items/${source.relativePath.replaceAll("\\", "/")}`;
    files.set(relativePath, bytes);
    inputBytes += source.bytes.length;
    outputBytes += bytes.length;
    fileAudit.push({ path: relativePath, inputSha256: sha(source.bytes), outputSha256: sha(bytes),
      inputBytes: source.bytes.length, outputBytes: bytes.length, removedNodes: removals.length });
  }
  const identity = ({ row, listIndex }: (typeof catalog)[number], ordinal: number) => ({
    listIndex, sourceFile: row.sourceFile, sourceOrdinal: row.sourceOrdinal,
    nameOccurrence: row.nameOccurrence, name: row.name, mergedOrdinal: ordinal,
    reverseEnumerationId: catalog.length - ordinal,
    family: row.family, stripped: row.strip, retainedReason: row.retainedReason
  });
  const manifest = {
    schema: SCHEMA, sourceRevision,
    scope: "offline ItemDataLoader list closure; production loading unchanged",
    strippedFamilies: [...STRIPPABLE], listEntries: entries, itemSets,
    loaderOracle: "source model: list concat, reverse array enumeration; not AVM1 measured",
    allOtherParsedFieldsEqual: true, itemCount: catalog.length,
    byteAccounting: "listed XML files only; projection manifest excluded",
    familyCounts, removedNodes, inputBytes, outputBytes, netSavedBytes: inputBytes - outputBytes,
    files: fileAudit,
    duplicateNames: [...byName].filter(([, rows]) => rows.length > 1).map(([name, rows]) => ({
      name, policy: "retain all balances", dictionaryWinnerMergedOrdinal: catalog.indexOf(rows[0]!),
      rows: rows.map((entry) => identity(entry, catalog.indexOf(entry)))
    })),
    items: catalog.map(identity)
  };
  return { files, manifest };
}

/** Generate/check only a dedicated output tree; never remove stale or unrelated files. */
export function writeNonWeaponRuntimeProjection(
  repoRoot: string, outputRoot: string, projection: NonWeaponProjection, check = false
): void {
  const repo = fs.realpathSync(repoRoot);
  const output = path.resolve(outputRoot);
  const nearest = nearestExisting(output);
  const canonical = path.resolve(fs.realpathSync(nearest), path.relative(nearest, output));
  if (canonical !== output || output === repo
    || (isInside(repo, output) && !isInside(path.join(repo, "tmp"), output))) {
    throw new Error("Output must be a dedicated directory outside the repository or under its tmp/");
  }
  const expected = new Map(projection.files);
  expected.set(MANIFEST, Buffer.from(JSON.stringify(projection.manifest, null, 2) + "\n"));
  const actual = walk(output);
  const extra = actual.filter((file) => !expected.has(file));
  if (extra.length) throw new Error(`Unexpected output files (preserved): ${extra.join(", ")}`);
  if (actual.length && !check) {
    const marker = path.join(output, MANIFEST);
    if (!fs.existsSync(marker) || JSON.parse(fs.readFileSync(marker, "utf8")).schema !== SCHEMA) {
      throw new Error("Refusing to overwrite an output directory without this generator's manifest");
    }
  }
  const differences: string[] = [];
  for (const [relative, bytes] of expected) {
    const target = path.join(output, relative);
    if (check) {
      if (!fs.existsSync(target) || !fs.readFileSync(target).equals(bytes)) differences.push(relative);
    } else {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, bytes);
    }
  }
  if (differences.length) throw new Error(`Missing/stale projection: ${differences.join(", ")}`);
}

function sha(bytes: Buffer): string { return createHash("sha256").update(bytes).digest("hex"); }
function array(value: unknown): unknown[] { return value === undefined ? [] : Array.isArray(value) ? value : [value]; }
function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function object(value: unknown, location: string): Record<string, unknown> {
  if (!isObject(value)) throw new Error(`Expected object: ${location}`);
  return value;
}
function text(value: unknown, location: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`Expected text: ${location}`);
  return value;
}
function containsKey(value: unknown, key: string): boolean {
  if (value === null || typeof value !== "object") return false;
  return Object.entries(value).some(([name, child]) => name === key || name === `@_${key}` || containsKey(child, key));
}
function isInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return relative !== "" && !relative.startsWith(".." + path.sep) && relative !== ".." && !path.isAbsolute(relative);
}
function nearestExisting(value: string): string {
  return fs.existsSync(value) ? value : nearestExisting(path.dirname(value));
}
function walk(root: string, relative = ""): string[] {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(path.join(root, relative), { withFileTypes: true }).flatMap((entry) => {
    if (entry.isSymbolicLink()) throw new Error("Output symlinks are not supported");
    const child = relative ? `${relative}/${entry.name}` : entry.name;
    return entry.isDirectory() ? walk(root, child) : [child];
  }).sort();
}
