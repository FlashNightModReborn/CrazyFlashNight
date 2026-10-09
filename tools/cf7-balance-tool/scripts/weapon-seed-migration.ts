/**
 * 武器存量迁移生成器（#102 分批迁移第一批）：
 * 扫描 data/items/武器_手枪_*.xml 与 武器_长枪_*.xml，为尚无 weapon 账本记录的
 * item/profile 机械派生输入，生成 status=unresolved 的审计记录片段。
 *
 * 派生口径（全部标注在 ruleRefs/note，供人工裁定）：
 *   dualWield   use=手枪/手枪2→2，其余→1（WBR-DUAL-001 直读 use）
 *   pierce      bullet 名含"次级穿刺"→1.5、含"穿刺"→2、其余→1；bullet 不在
 *               bullets_cases.xml 或取值靠名称推断时，evidenceRef 带 UNRESOLVED 前缀
 *   damageType  生效 damagetype=魔法 或存在 magictype→2；含"真伤/无视防御"→3；其余→1
 *   shotgun     发射器文件→4；split>1→split（横向/纵向/连发语义未裁定，转黄）；
 *               其余→1
 *   magPrice    clipname 精确命中 消耗品_弹夹.xml 条目→取其 price；否则 0 并转黄
 *   weightLayers K 点商店→+1、合成→+1、仅金币店→0；全部未命中→unverified 0 转黄
 *   category    恒 1（非默认需 WBR-CAT-002 人工裁定）
 *   formula     恒 1（WBR-AUTH-001 当前公式版）
 *
 * 用法：cd tools/cf7-balance-tool && npx tsx scripts/weapon-seed-migration.ts > ../../tmp/weapon_seed_records.xml
 * 之后把片段插入 records/weapon-balance-audit.xml 的 </records> 前，跑
 * `npm run balance-sync -- --write` 让账本 digest 与物品 <balance> 落盘。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";
import {
  buildWeaponAcquisitionIndex,
  enumerateWeaponItemEffectiveProfileKeys,
  resolveWeaponItemEffectiveProfile
} from "@cf7-balance-tool/xml-io";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const ITEMS_DIR = path.join(REPO_ROOT, "data", "items");
const LEDGER_PATH = path.join(TOOL_ROOT, "records", "weapon-balance-audit.xml");
const WORKBOOK_REF =
  "0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx#枪械!Q1;formula=1";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  parseTagValue: true,
  trimValues: true
});

function main(): void {
  const ledgerSource = fs.readFileSync(LEDGER_PATH, "utf8");
  const ledgered = new Set(
    [...ledgerSource.matchAll(/<itemName>([\s\S]*?)<\/itemName>/g)].map((m) => m[1]!.trim())
  );
  const acquisitionIndex = buildWeaponAcquisitionIndex(REPO_ROOT);
  const ammoPrices = readAmmoPrices();
  const bulletNames = readBulletNames();

  const records: string[] = [];
  const seenItemNames = new Map<string, string>();
  for (const fileName of fs.readdirSync(ITEMS_DIR)) {
    if (!/^武器_(?:手枪|长枪)_.*\.xml$/.test(fileName)) continue;
    const sourceFile = `data/items/${fileName}`;
    const isLauncherFile = fileName.includes("发射器");
    const parsed = parser.parse(fs.readFileSync(path.join(ITEMS_DIR, fileName), "utf8")) as Record<string, unknown>;
    const items = collectItems(parsed);

    for (const item of items) {
      const name = scalar(item.name);
      if (!name || ledgered.has(name)) continue;
      if (seenItemNames.has(name)) {
        console.error(`WARN: 跨文件同名武器 ${name}：${seenItemNames.get(name)} vs ${sourceFile}，跳过后者`);
        continue;
      }
      seenItemNames.set(name, sourceFile);
      const profileKeys = enumerateWeaponItemEffectiveProfileKeys(item);
      for (const profileKey of profileKeys) {
        const resolved = resolveWeaponItemEffectiveProfile(item, profileKey, 1);
        const mech = resolved.mechanicalInputs;
        const record = deriveRecord({
          itemName: name,
          profileKey,
          sourceFile,
          isLauncherFile,
          itemUse: resolved.itemUse ?? "",
          bullet: scalar(mech.bullet),
          clipname: scalar(mech.clipname),
          split: finite(mech.split),
          damagetype: scalar(mech.damagetype),
          magictype: scalar(mech.magictype),
          ammoPrices,
          bulletNames,
          acquisitionIndex
        });
        records.push(record);
      }
    }
  }
  process.stdout.write(records.join("\n") + "\n");
}

interface DeriveArgs {
  itemName: string;
  profileKey: string;
  sourceFile: string;
  isLauncherFile: boolean;
  itemUse: string;
  bullet: string;
  clipname: string;
  split: number;
  damagetype: string;
  magictype: string;
  ammoPrices: Map<string, number>;
  bulletNames: Set<string>;
  acquisitionIndex: ReturnType<typeof buildWeaponAcquisitionIndex>;
}

function deriveRecord(args: DeriveArgs): string {
  const { itemName, profileKey, sourceFile } = args;
  const anchor = `${sourceFile}#item=${itemName}`;

  // dualWield
  const dualWield = args.itemUse === "手枪" || args.itemUse === "手枪2" ? 2 : 1;
  const dualRef = ref("WBR-DUAL-001", "input.dualWield", `${anchor}/use=${args.itemUse}`);

  // pierce
  let pierce = 1;
  let pierceRule = "WBR-PIERCE-001";
  let pierceNote = "";
  if (/次级穿刺/.test(args.bullet)) { pierce = 1.5; pierceRule = "WBR-PIERCE-002"; pierceNote = "次级穿刺按名推断 1.5"; }
  else if (/穿刺/.test(args.bullet)) { pierce = 2; pierceRule = "WBR-PIERCE-003"; pierceNote = "普通穿刺按名推断 2"; }
  const bulletKnown = args.bullet !== "" && args.bulletNames.has(args.bullet);
  const pierceEvidence = bulletKnown
    ? `UNRESOLVED: data/items/bullets_cases.xml#bullet=${args.bullet}；${pierceNote || "默认非穿刺=1"}待复核`
    : `UNRESOLVED: bullets_cases.xml 未找到 bullet=${args.bullet || "<空>"}；pierce=1 为默认占位`;
  const pierceRef = ref(pierceRule, "input.pierce", pierceEvidence);

  // damageType
  let damageType = 1;
  let dmgRule = "WBR-DMG-001";
  const dtText = `${args.damagetype}${args.magictype}`;
  if (/真伤|无视防御|真实/.test(dtText)) { damageType = 3; dmgRule = "WBR-DMG-003"; }
  else if (args.damagetype === "魔法" || args.magictype !== "") { damageType = 2; dmgRule = "WBR-DMG-002"; }
  const dmgEvidence =
    args.damagetype || args.magictype
      ? `${anchor}/data;damagetype=${args.damagetype || "absent"};magictype=${args.magictype || "absent"}`
      : `UNRESOLVED: ${anchor}/data;无 damagetype/magictype，默认物理=1`;
  const dmgRef = ref(dmgRule, "input.damageType", dmgEvidence);

  // shotgun
  let shotgun = 1;
  let shotRule = "WBR-SHOT-001";
  let shotEvidence: string;
  if (args.isLauncherFile) {
    shotgun = 4;
    shotRule = "WBR-SHOT-003";
    shotEvidence = `${anchor}/data;发射器文件按爆炸类=4`;
  } else if (args.split > 1) {
    shotgun = args.split;
    shotRule = "WBR-SHOT-002";
    shotEvidence = `UNRESOLVED: ${anchor}/data/split=${args.split}；横向/纵向/连发语义未裁定，按 split 直录待复核`;
  } else {
    shotEvidence = `${anchor}/data/split=${args.split || "absent"}`;
  }
  const shotRef = ref(shotRule, "input.shotgun", shotEvidence);

  // magPrice
  const ammoPrice = args.clipname ? args.ammoPrices.get(args.clipname) : undefined;
  const magPrice = ammoPrice ?? 0;
  const ammoEvidence =
    ammoPrice !== undefined
      ? `data/items/消耗品_弹夹.xml#item=${args.clipname}/price=${ammoPrice}`
      : `UNRESOLVED: data/items/消耗品_弹夹.xml 未找到 clipname=${args.clipname || "<空>"} 对应弹药；magPrice=0 为占位`;
  const ammoRef = ref("WBR-AMMO-001", "input.magPrice", ammoEvidence);

  // weightLayers（获取渠道）
  const goldFiles = [...(args.acquisitionIndex.goldShopFilesByItem.get(itemName) ?? [])];
  const kshopFiles = [...(args.acquisitionIndex.kshopFilesByItem.get(itemName) ?? [])];
  const craftFiles = [...(args.acquisitionIndex.craftingFilesByItem.get(itemName) ?? [])];
  const budget: Array<{ code: string; delta: number; ruleRef: string; evidenceRef?: string }> = [];
  if (kshopFiles.length > 0) {
    budget.push({ code: "acquisition.kshop", delta: 1, ruleRef: "WBR-WL-001", evidenceRef: kshopFiles[0]! });
  }
  if (craftFiles.length > 0) {
    budget.push({ code: "acquisition.crafting", delta: 1, ruleRef: "WBR-WL-001", evidenceRef: craftFiles[0]! });
  }
  if (goldFiles.length > 0) {
    budget.push({ code: "acquisition.gold-standard", delta: 0, ruleRef: "WBR-WL-003", evidenceRef: goldFiles[0]! });
  }
  if (budget.length === 0) {
    budget.push({
      code: "acquisition.unverified",
      delta: 0,
      ruleRef: "WBR-WL-003",
      evidenceRef: "UNRESOLVED: 现役商店/K点/合成索引均未命中；获取路径待人工确认"
    });
  }
  const weightLayers = budget.reduce((total, entry) => total + entry.delta, 0);
  const multiPath = [goldFiles.length, kshopFiles.length, craftFiles.length].filter((n) => n > 0).length > 1;
  const wlEvidence = multiPath
    ? `UNRESOLVED: ${[...goldFiles, ...kshopFiles, ...craftFiles].filter(Boolean).join("；")}；多路径层级按 WBR-WL-005 待裁定`
    : (budget[0]!.evidenceRef ?? `UNRESOLVED: 无获取路径`);
  const wlRef = ref(
    multiPath ? "WBR-WL-005" : (goldFiles.length ? "WBR-WL-003" : "WBR-WL-001"),
    "input.weightLayers",
    wlEvidence
  );

  const catRef = ref("WBR-CAT-001", "input.category", `${anchor};no-special-category-evidence`);
  const authRef = ref("WBR-AUTH-001", "input.formula", WORKBOOK_REF);

  const noteParts = [
    "机械派生登记（首批存量迁移）",
    !bulletKnown && "bullet 未见于 bullets_cases",
    ammoPrice === undefined && "弹药价格缺失",
    args.split > 1 && !args.isLauncherFile && "split 语义待裁定",
    multiPath && "多获取路径层级待裁定",
    budget[0]!.code === "acquisition.unverified" && "无获取渠道",
    "全部输入待人工复核后方可 confirmed"
  ];
  const note = noteParts.filter(Boolean).join("；");

  const budgetXml = budget
    .map(
      (entry) =>
        `        <entry>\n          <code>${entry.code}</code>\n          <delta>${entry.delta}</delta>\n          <ruleRef>${entry.ruleRef}</ruleRef>${
          entry.evidenceRef ? `\n          <evidenceRef>${escapeXml(entry.evidenceRef)}</evidenceRef>` : ""
        }\n        </entry>`
    )
    .join("\n");
  const refsXml = [dualRef, pierceRef, dmgRef, shotRef, ammoRef, wlRef, catRef, authRef]
    .map(
      (r) =>
        `        <ref>\n          <id>${r.id}</id>\n          <target>${r.target}</target>\n          <evidenceRef>${escapeXml(r.evidenceRef)}</evidenceRef>\n        </ref>`
    )
    .join("\n");

  return [
    "    <record>",
    `      <auditRef>weapon:${escapeXml(itemName)}:${escapeXml(profileKey)}</auditRef>`,
    `      <itemName>${escapeXml(itemName)}</itemName>`,
    `      <profileKey>${escapeXml(profileKey)}</profileKey>`,
    `      <dualWield>${dualWield}</dualWield>`,
    `      <pierce>${pierce}</pierce>`,
    `      <damageType>${damageType}</damageType>`,
    `      <shotgun>${shotgun}</shotgun>`,
    `      <magPrice>${magPrice}</magPrice>`,
    `      <weightLayers>${weightLayers}</weightLayers>`,
    `      <category>1</category>`,
    `      <formula>1</formula>`,
    `      <status>unresolved</status>`,
    `      <displayEligible>false</displayEligible>`,
    `      <inputDigest>fnv1a32:00000000</inputDigest>`,
    `      <sourceDigest>sha256:${"0".repeat(64)}</sourceDigest>`,
    "      <budgetBreakdown>",
    budgetXml,
    "      </budgetBreakdown>",
    "      <ruleRefs>",
    refsXml,
    "      </ruleRefs>",
    `      <note>${escapeXml(note)}</note>`,
    "    </record>"
  ].join("\n");
}

function ref(id: string, target: string, evidenceRef: string) {
  return { id, target, evidenceRef };
}

function readAmmoPrices(): Map<string, number> {
  const source = fs.readFileSync(path.join(ITEMS_DIR, "消耗品_弹夹.xml"), "utf8");
  const result = new Map<string, number>();
  for (const block of source.matchAll(/<item[\s\S]*?<\/item>/g)) {
    const name = block[0].match(/<name>([\s\S]*?)<\/name>/)?.[1]?.trim();
    const price = Number(block[0].match(/<price>([\s\S]*?)<\/price>/)?.[1]?.trim());
    if (name && Number.isFinite(price)) result.set(name, price);
  }
  return result;
}

function readBulletNames(): Set<string> {
  const result = new Set<string>();
  for (const fileName of ["bullets_cases.xml", "missileConfigs.xml"]) {
    const filePath = path.join(ITEMS_DIR, fileName);
    if (!fs.existsSync(filePath)) continue;
    const source = fs.readFileSync(filePath, "utf8");
    for (const match of source.matchAll(/<name>([\s\S]*?)<\/name>/g)) {
      const name = match[1]!.trim();
      if (name) result.add(name);
    }
  }
  return result;
}

function collectItems(parsed: unknown): Record<string, unknown>[] {
  const items: Record<string, unknown>[] = [];
  const visit = (value: unknown): void => {
    if (Array.isArray(value)) { value.forEach(visit); return; }
    if (!value || typeof value !== "object") return;
    const obj = value as Record<string, unknown>;
    if (obj.name !== undefined && obj.data !== undefined) { items.push(obj); return; }
    Object.values(obj).forEach(visit);
  };
  visit(parsed);
  return items;
}

function scalar(value: unknown): string {
  if (value === undefined || value === null) return "";
  return String(value).trim();
}

function finite(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

main();
