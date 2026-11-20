import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { buildNonWeaponRuntimeProjection, writeNonWeaponRuntimeProjection } from "../src/nonweapon-runtime-projection.js";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) fs.rmSync(root, { recursive: true, force: true }); });
const balance = (family: string, extra = "") => `<balance><formulaFamily>${family}</formulaFamily><schemaVersion>1</schemaVersion>${extra}</balance>`;
const item = (name: string, content: string) => `<item><name>${name}</name><data><level>1</level></data>${content}</item>`;
function fixture(files: Record<string, string>, entries = Object.keys(files), itemSets = "item_sets.xml") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-nonweapon-projection-")); roots.push(root);
  const items = path.join(root, "data/items"); fs.mkdirSync(items, { recursive: true });
  for (const [name, source] of Object.entries(files)) fs.writeFileSync(path.join(items, name), source);
  fs.writeFileSync(path.join(items, "list.xml"), `<root><itemSets>${itemSets}</itemSets>${entries.map((entry) => `<items>${entry}</items>`).join("")}</root>`);
  fs.writeFileSync(path.join(items, itemSets), "\ufeff<root><!--套装中心--><set><id>A</id><name>套装</name></set></root>\r\n");
  return root;
}
const outText = (projection: ReturnType<typeof buildNonWeaponRuntimeProjection>, file: string) => projection.files.get(`data/items/${file}`)!.toString("utf8");

describe("offline nonweapon ItemDataLoader projection", () => {
  it("preserves literal item keys when tracking duplicate names", () => {
    const root = fixture({ "items.xml": `<root>${item("刀", balance("melee"))}${item("刀 ", balance("melee"))}${item("刀 ", balance("melee"))}</root>` });
    const projection = buildNonWeaponRuntimeProjection(root, "identity-fixture");
    expect(projection.manifest.items).toMatchObject([
      { name: "刀", stripped: true, nameOccurrence: 1 },
      { name: "刀 ", stripped: false, nameOccurrence: 1 },
      { name: "刀 ", stripped: false, nameOccurrence: 2 }
    ]);
  });
  it("removes only the four known families, preserving BOM/CRLF/comments, identity and defaults input", () => {
    const content = "\ufeff<root>\r\n<!--作者注释不丢失-->\r\n" + ["armor", "melee", "potion", "explosives", "weapon", "future"].map((family) => item(family, balance(family))).join("\r\n") + "\r\n</root>\r\n";
    const root = fixture({ "items.xml": content });
    const before = fs.readFileSync(path.join(root, "data/items/items.xml"));
    const projection = buildNonWeaponRuntimeProjection(root, "fixture-revision");
    let expected = content;
    for (const family of ["armor", "melee", "potion", "explosives"]) expected = expected.replace(balance(family), "");
    expect(outText(projection, "items.xml")).toBe(expected);
    expect(outText(projection, "items.xml")).not.toContain("<modslot>");
    expect(projection.files.get("data/items/item_sets.xml")).toEqual(fs.readFileSync(path.join(root, "data/items/item_sets.xml")));
    expect(fs.readFileSync(path.join(root, "data/items/items.xml"))).toEqual(before);
    expect(projection.manifest).toMatchObject({ itemCount: 6, removedNodes: 4, allOtherParsedFieldsEqual: true });
    expect(projection.manifest.netSavedBytes).toBe(Buffer.byteLength(content) - Buffer.byteLength(expected));
  });

  it("retains duplicate names within/across files and their ordered source identities", () => {
    const root = fixture({
      "a.xml": `<root>${item("重名", balance("armor"))}${item("同文件", balance("melee"))}${item("同文件", balance("melee"))}</root>`,
      "b.xml": `<root>${item("重名", balance("weapon"))}${item("独立", balance("potion"))}</root>`
    }, ["b.xml", "a.xml"]);
    const projection = buildNonWeaponRuntimeProjection(root, "fixture");
    expect(projection.manifest).toMatchObject({ listEntries: ["b.xml", "a.xml"], removedNodes: 1 });
    expect(outText(projection, "a.xml")).toContain(balance("armor"));
    expect(outText(projection, "a.xml")).toContain(balance("melee"));
    expect(projection.manifest.items).toMatchObject([
      { name: "重名", sourceFile: "b.xml", sourceOrdinal: 0, reverseEnumerationId: 5 },
      { name: "独立", sourceFile: "b.xml", sourceOrdinal: 1, reverseEnumerationId: 4 },
      { name: "重名", sourceFile: "a.xml", sourceOrdinal: 0, reverseEnumerationId: 3 },
      { name: "同文件", nameOccurrence: 1 }, { name: "同文件", nameOccurrence: 2 }
    ]);
    expect(projection.manifest.duplicateNames).toMatchObject([
      { name: "重名", dictionaryWinnerMergedOrdinal: 0 }, { name: "同文件", dictionaryWinnerMergedOrdinal: 3 }
    ]);
  });

  it("keeps duplicate balance, unknown schema, nested balance and recursive bullet-reader input", () => {
    const root = fixture({ "items.xml": `<root>${item("重复balance", balance("armor") + balance("armor"))}${item("未来版本", balance("armor").replace("<schemaVersion>1", "<schemaVersion>2"))}${item("递归读者", balance("melee", "<nested><bullet>模板-单元</bullet></nested>"))}${item("属性读者", balance("melee", '<nested bullet="模板-单元"/>'))}${item("嵌套字段", "<mechanism>" + balance("armor") + "</mechanism>")}</root>` });
    const projection = buildNonWeaponRuntimeProjection(root, "fixture");
    expect(outText(projection, "items.xml")).toBe(fs.readFileSync(path.join(root, "data/items/items.xml"), "utf8"));
    expect(projection.manifest.removedNodes).toBe(0);
  });

  it("supports singleton items/list entries, empty files, item_sets fallback and repeated list entries", () => {
    const root = fixture({ "singleton.xml": `<root>${item("单项", balance("potion"))}</root>`, "empty.xml": "<root/>" }, ["singleton.xml", "empty.xml", "singleton.xml"]);
    fs.writeFileSync(path.join(root, "data/items/list.xml"), "<root><items>singleton.xml</items><items>empty.xml</items><items>singleton.xml</items></root>");
    const projection = buildNonWeaponRuntimeProjection(root, "fixture");
    expect(projection.manifest).toMatchObject({ itemCount: 2, itemSets: "item_sets.xml", removedNodes: 0 });
    fs.writeFileSync(path.join(root, "data/items/list.xml"), "<root><items>singleton.xml</items></root>");
    expect(buildNonWeaponRuntimeProjection(root, "fixture").manifest).toMatchObject({ itemCount: 1, removedNodes: 1 });
  });

  it("reproduces exact bytes and --check rejects stale/missing/extra outputs without writes", () => {
    const root = fixture({ "a.xml": `<root>${item("甲", balance("armor"))}</root>` });
    const projection = buildNonWeaponRuntimeProjection(root, "fixture");
    const output = path.join(root, "tmp/projection");
    writeNonWeaponRuntimeProjection(root, output, projection);
    expect(() => writeNonWeaponRuntimeProjection(root, output, projection, true)).not.toThrow();
    const manifestBefore = fs.readFileSync(path.join(output, "projection-manifest.json"));
    fs.appendFileSync(path.join(output, "data/items/a.xml"), "<!--stale-->");
    expect(() => writeNonWeaponRuntimeProjection(root, output, projection, true)).toThrow("Missing/stale");
    expect(fs.readFileSync(path.join(output, "projection-manifest.json"))).toEqual(manifestBefore);
    writeNonWeaponRuntimeProjection(root, output, projection);
    expect(buildNonWeaponRuntimeProjection(root, "fixture").manifest).toEqual(projection.manifest);
    fs.unlinkSync(path.join(output, "data/items/a.xml"));
    expect(() => writeNonWeaponRuntimeProjection(root, output, projection, true)).toThrow("Missing/stale");
    fs.writeFileSync(path.join(output, "unrelated.xml"), "keep");
    expect(() => writeNonWeaponRuntimeProjection(root, output, projection)).toThrow("Unexpected output files (preserved)");
    expect(fs.readFileSync(path.join(output, "unrelated.xml"), "utf8")).toBe("keep");
  });

  it("detects author input changes and refuses production destinations or symlink output escapes", () => {
    const root = fixture({ "a.xml": `<root>${item("甲", balance("armor"))}</root>` });
    const output = path.join(root, "tmp/projection");
    const projection = buildNonWeaponRuntimeProjection(root, "fixture");
    writeNonWeaponRuntimeProjection(root, output, projection);
    fs.appendFileSync(path.join(root, "data/items/a.xml"), "<!--新输入-->");
    expect(() => writeNonWeaponRuntimeProjection(root, output, buildNonWeaponRuntimeProjection(root, "fixture"), true)).toThrow("Missing/stale");
    for (const destination of [root, path.join(root, "data/items"), path.join(root, "runtime/projection"), path.join(root, "tmp")]) {
      expect(() => writeNonWeaponRuntimeProjection(root, destination, projection)).toThrow("Output must");
    }
    fs.symlinkSync(path.join(root, "data/items"), path.join(root, "tmp/escape"), process.platform === "win32" ? "junction" : "dir");
    expect(() => writeNonWeaponRuntimeProjection(root, path.join(root, "tmp/escape/projection"), projection)).toThrow("Output must");
  });

  it("rejects malformed XML and list traversal rather than rewriting ambiguous input", () => {
    const root = fixture({ "a.xml": "<root><item></root>" });
    expect(() => buildNonWeaponRuntimeProjection(root, "fixture")).toThrow("Invalid XML");
    fs.writeFileSync(path.join(root, "data/items/list.xml"), "<root><items>../escape.xml</items></root>");
    expect(() => buildNonWeaponRuntimeProjection(root, "fixture")).toThrow("Unsafe item list path");
  });
});
