import fs from "node:fs";
import path from "node:path";
import { XMLParser, XMLValidator } from "fast-xml-parser";

import {
  WEAPON_BALANCE_BUDGET_CODES,
  computeWeaponPrice,
  type WeaponBalanceAuditRecord
} from "@cf7-balance-tool/core";
import type { ResolvedWeaponItemProfile } from "./weapon-balance.js";

export type WeaponPriceEvidenceContext = Pick<ResolvedWeaponItemProfile,
  "itemName" | "profileKey" | "itemUse" | "itemPrice" | "runtimeInputs">;

export interface WeaponAcquisitionIndex {
  repositoryRoot: string;
  craftingFilesByItem: ReadonlyMap<string, readonly string[]>;
  goldShopFilesByItem: ReadonlyMap<string, readonly string[]>;
  goldShopRefsByItem: ReadonlyMap<string, readonly string[]>;
  kshopFilesByItem: ReadonlyMap<string, readonly string[]>;
  rewardFiles: ReadonlySet<string>;
  catalogFiles: ReadonlySet<string>;
}

export interface WeaponBalanceEvidenceIssue {
  severity: "error" | "warning";
  code: string;
  path: string;
  message: string;
}

export interface WeaponBalanceEvidenceValidationResult {
  valid: boolean;
  displayEligible: boolean;
  issues: WeaponBalanceEvidenceIssue[];
}

/** 构建现役合成、金币商店和 K 点商店的精确物品名索引。 */
export function buildWeaponAcquisitionIndex(
  repositoryRoot: string
): WeaponAcquisitionIndex {
  const root = path.resolve(repositoryRoot);
  const shops = listedJsonFiles(root, "data/shops", "shops");
  const kshops = listedJsonFiles(root, "data/kshop", "kshop");
  const recipes = listedJsonFiles(root, "data/crafting", "list", ".json");
  return {
    repositoryRoot: root,
    ...indexNpcShopShelves(root, shops),
    craftingFilesByItem: indexCatalogs(root, recipes, extractCraftingNames),
    kshopFilesByItem: indexCatalogs(root, kshops, extractKshopNames),
    rewardFiles: new Set([
      ...listedJsonFiles(root, "data/task", "task"),
      ...listedJsonFiles(root, "data/achievement", "achievement")
    ]),
    catalogFiles: new Set([...shops, ...kshops, ...recipes])
  };
}

function indexNpcShopShelves(root: string, shops: string[]) {
  const goldShopFilesByItem = new Map<string, string[]>();
  const goldShopRefsByItem = new Map<string, string[]>();
  const shopIds = new Set<string>();
  for (const file of shops) {
    const shop = readJson(root, file);
    if (!isObject(shop)) throw new Error(`${file}: invalid NPC shop`);
    const modern = shop.schema !== undefined;
    if (modern && (shop.schema !== "npc-shop.v2" || typeof shop.shopId !== "string" || !shop.shopId)) {
      throw new Error(`${file}: invalid NPC shop schema or identity`);
    }
    const catalogs = modern ? [[String(shop.shopId), shop.catalog] as const] : Object.entries(shop);
    if (!catalogs.length) throw new Error(`${file}: missing NPC shop`);
    for (const [id, catalog] of catalogs) {
      if (!id || shopIds.has(id) || !isObject(catalog) || (!modern && !Object.keys(catalog).length)) {
        throw new Error(`${file}: invalid or duplicate NPC shop ${id}`);
      }
      shopIds.add(id);
      for (const [slot, entry] of Object.entries(catalog)) {
        const name = typeof entry === "string" ? entry : isObject(entry) ? entry.name : undefined;
        if (typeof name !== "string" || !/^(0|[1-9]\d*)$/.test(slot)) continue;
        addReference(goldShopFilesByItem, name, file);
        addReference(goldShopRefsByItem, name, `${file}#${modern ? "catalog" : id}.${slot}`);
      }
    }
  }
  return { goldShopFilesByItem, goldShopRefsByItem };
}

/**
 * 校验 displayEligible attestation 所引用的仓库证据。
 * 领域 validator 与本结果必须同时通过，玩家投影才可进入显示层。
 */
export function validateWeaponBalanceEvidence(
  itemName: string,
  record: WeaponBalanceAuditRecord,
  index: WeaponAcquisitionIndex,
  priceContext?: WeaponPriceEvidenceContext
): WeaponBalanceEvidenceValidationResult {
  const issues: WeaponBalanceEvidenceIssue[] = [];

  if (record.status !== "confirmed") {
    return { valid: true, displayEligible: false, issues };
  }

  record.ruleRefs.forEach((ref, refIndex) => {
    const evidencePath = validateEvidencePath(
      ref.evidenceRef,
      `weaponBalanceAudit.ruleRefs.ref[${refIndex}].evidenceRef`,
      index.repositoryRoot,
      issues
    );
    if (evidencePath?.startsWith("data/shops/") && ref.evidenceRef &&
        (ref.target === "input.weightLayers" || ref.evidenceRef.includes("#catalog.")) &&
        !index.goldShopRefsByItem.get(itemName)?.includes(ref.evidenceRef)) {
      addError(issues, "gold_shop_slot_mismatch", `weaponBalanceAudit.ruleRefs.ref[${refIndex}].evidenceRef`,
        `NPC shop evidence must point to the active shelf for ${itemName}: ${ref.evidenceRef}`);
    }
  });

  record.budgetBreakdown.forEach((entry, entryIndex) => {
    const issuePath = `weaponBalanceAudit.budgetBreakdown.entry[${entryIndex}]`;
    if (!(WEAPON_BALANCE_BUDGET_CODES as readonly string[]).includes(entry.code)) {
      addError(
        issues,
        "budget_code_unknown",
        `${issuePath}.code`,
        `unsupported weapon balance budget code ${entry.code}`
      );
    }
    const evidencePath = validateEvidencePath(
      entry.evidenceRef,
      `${issuePath}.evidenceRef`,
      index.repositoryRoot,
      issues
    );

    if (entry.code === "acquisition.crafting") {
      const matches = index.craftingFilesByItem.get(itemName) ?? [];
      if (matches.length === 0) {
        addError(
          issues,
          "crafting_output_not_found",
          issuePath,
          `no active crafting recipe has exact output name ${itemName}`
        );
      } else if (evidencePath && !matches.includes(evidencePath)) {
        addError(
          issues,
          "crafting_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `referenced file does not contain an exact ${itemName} recipe output`
        );
      }
    }

    if (entry.code === "acquisition.gold-standard") {
      const goldMatches = index.goldShopFilesByItem.get(itemName) ?? [];
      const craftingMatches = index.craftingFilesByItem.get(itemName) ?? [];
      const kshopMatches = index.kshopFilesByItem.get(itemName) ?? [];

      if (goldMatches.length === 0) {
        addError(
          issues,
          "gold_shop_item_not_found",
          issuePath,
          `no active NPC gold shop contains exact item ${itemName}`
        );
      } else if (!entry.evidenceRef || !index.goldShopRefsByItem.get(itemName)?.includes(entry.evidenceRef)) {
        addError(
          issues,
          "gold_shop_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `evidence must name the active NPC shop file and shelf for ${itemName}: ${entry.evidenceRef}`
        );
      }

      if (craftingMatches.length > 0) {
        addError(
          issues,
          "gold_standard_has_crafting_source",
          issuePath,
          `${itemName} also appears as a crafting output`
        );
      }
      if (kshopMatches.length > 0) {
        addError(
          issues,
          "gold_standard_has_kshop_source",
          issuePath,
          `${itemName} also appears in a K-point shop`
        );
      }
    }

    if (entry.code === "acquisition.kshop") {
      const matches = index.kshopFilesByItem.get(itemName) ?? [];
      if (matches.length === 0) {
        addError(
          issues,
          "kshop_item_not_found",
          issuePath,
          `no active K-point shop contains exact item ${itemName}`
        );
      } else if (evidencePath && !matches.includes(evidencePath)) {
        addError(
          issues,
          "kshop_evidence_mismatch",
          `${issuePath}.evidenceRef`,
          `referenced file does not contain exact K-point shop item ${itemName}`
        );
      }
    }

    if (entry.code === "acquisition.unverified") {
      addError(
        issues,
        "unverified_acquisition_confirmed",
        issuePath,
        "acquisition.unverified can never support a confirmed record"
      );
    }

    if (entry.code === "acquisition.high-price") {
      validateHighPriceEvidence(itemName, record, index, priceContext,
        entry.delta, entry.evidenceRef, issuePath, issues);
    }
    if (entry.code === "mechanic.tactical-mod-lock") {
      validateTacticalModLockEvidence(itemName, record, index.repositoryRoot,
        evidencePath, issuePath, issues);
    }
  });

  const valid = !issues.some((issue) => issue.severity === "error");
  return {
    valid,
    displayEligible: valid && record.displayEligible,
    issues
  };
}

/** 战术补偿必须由当前物品的实际改装政策证明，名称和文案不作证据。 */
function validateTacticalModLockEvidence(
  itemName: string,
  record: WeaponBalanceAuditRecord,
  repositoryRoot: string,
  evidencePath: string | undefined,
  issuePath: string,
  issues: WeaponBalanceEvidenceIssue[]
): void {
  if (!evidencePath) return;
  const items: Record<string, unknown>[] = [];
  const collect = (value: unknown): void => {
    if (Array.isArray(value)) { value.forEach(collect); return; }
    if (!isObject(value)) return;
    if (value.name === itemName && value.type === "武器") items.push(value);
    Object.values(value).forEach(collect);
  };
  try {
    const source = fs.readFileSync(path.join(repositoryRoot, evidencePath), "utf8");
    collect(new XMLParser({ ignoreAttributes: false, trimValues: true }).parse(source));
  } catch {
    addError(issues, "tactical_mod_lock_evidence_invalid", issuePath,
      "tactical mod-lock evidence must be a readable current item XML");
    return;
  }
  const item = items.length === 1 ? items[0] : undefined;
  if (!item || !isObject(item.data)) {
    addError(issues, "tactical_mod_lock_item_mismatch", issuePath,
      `evidence must contain exactly one weapon definition named ${itemName}`);
    return;
  }
  const variant = record.profileKey === "data" ? {} : item[record.profileKey];
  const tags = (value: unknown): string[] => typeof value === "string"
    ? value.split(",").map(tag => tag.trim()).filter(Boolean) : [];
  const allowed = tags(item.allowedModTags);
  const inherent = tags(item.inherentTags);
  const blocked = tags(item.blockedTags);
  const requiredBlocked = ["导轨基座", "枪口", "弹匣", "下导轨", "瞄具", "枪机",
    "外部紧固", "表面涂层", "弹药", "机匣内构", "核心模块", "枪管"];
  const modslot = isObject(variant) ? (variant.modslot ?? item.data.modslot) : undefined;
  if (!["长枪", "手枪", "手枪2"].includes(String(item.use)) ||
      allowed.length !== 1 || allowed[0] !== "等级校正" ||
      !["电力", "NOAH"].every(tag => inherent.includes(tag)) ||
      !requiredBlocked.every(tag => blocked.includes(tag)) ||
      blocked.includes("等级校正") ||
      !(typeof modslot === "number" || typeof modslot === "string") || Number(modslot) !== 1) {
    addError(issues, "tactical_mod_lock_policy_mismatch", issuePath,
      "tactical +1 requires one level-correction slot, 电力/NOAH bases and the closed ordinary-mod policy");
  }
}

/** 只支持已独立裁定的购买限定金币 +1；不推断其他物品的价格层。 */
function validateHighPriceEvidence(
  itemName: string,
  record: WeaponBalanceAuditRecord,
  index: WeaponAcquisitionIndex,
  context: WeaponPriceEvidenceContext | undefined,
  delta: number,
  evidenceRef: string | undefined,
  issuePath: string,
  issues: WeaponBalanceEvidenceIssue[]
): void {
  const requiredRules = [
    ["WBR-MAP-002", "pricing.priceLayers"],
    ["WBR-PL-001", "pricing.priceLayers"],
    ["WBR-PL-003", "pricing.priceLayers"],
    ["WBR-PRICE-001", "pricing.goldPrice"],
    ["WBR-PRICE-002", "pricing.priceRatio"],
    ["WBR-PRICE-003", "pricing.priceLayers"]
  ];
  if (record.priceLayers !== 1 || delta !== 1 || requiredRules.some(([id, target]) =>
    !record.ruleRefs.some((ref) => ref.id === id && ref.target === target))) {
    addError(issues, "high_price_mapping_unverified", issuePath,
      "gold high-price +1 requires independent priceLayers=1 and explicit mapping/price rule references");
    return;
  }

  if (!evidenceRef || !index.goldShopRefsByItem.get(itemName)?.includes(evidenceRef)) {
    addError(issues, "high_price_gold_shop_mismatch", issuePath,
      `evidence must name the active NPC shop file and shelf for ${itemName}: ${evidenceRef}`);
  }
  if ((index.craftingFilesByItem.get(itemName)?.length ?? 0) > 0 ||
      (index.kshopFilesByItem.get(itemName)?.length ?? 0) > 0) {
    addError(issues, "high_price_other_acquisition", issuePath,
      `${itemName} also has crafting or K-point acquisition; gold-only +1 cannot be confirmed`);
  }
  const unreviewed = findUnreviewedItemReferences(index, itemName);
  if (unreviewed.length > 0) {
    addError(issues, "high_price_unreviewed_acquisition", issuePath,
      `review named references outside the weapon definition and gold shops: ${unreviewed.join(", ")}`);
  }

  if (!context || context.itemName !== itemName || context.profileKey !== record.profileKey ||
      !["长枪", "手枪", "手枪2"].includes(context.itemUse ?? "") ||
      !Number.isFinite(context.itemPrice) || context.itemPrice <= 0 ||
      !Number.isFinite(context.runtimeInputs.level) || context.runtimeInputs.level <= 0 ||
      !Number.isFinite(record.category) || record.category <= 0 ||
      !Number.isFinite(record.damageType) || record.damageType < 1) {
    addError(issues, "high_price_context_invalid", issuePath,
      "price verification requires current item identity, price, use, effective level and audited factors");
    return;
  }
  const recommendedPrice = computeWeaponPrice({
    level: context.runtimeInputs.level,
    weightLayers: record.priceLayers,
    dualWieldFactor: context.itemUse === "长枪" ? 1 : 1.5,
    categoryFactor: record.category,
    damageTypeFactor: record.damageType
  }).goldPrice;
  const priceRatio = context.itemPrice / recommendedPrice;
  if (!Number.isFinite(priceRatio) || priceRatio < 0.8 || priceRatio > 1.25) {
    addError(issues, "high_price_outside_audit_band", issuePath,
      `price=${context.itemPrice}, recommended=${recommendedPrice}, ratio=${priceRatio}; expected 0.8..1.25`);
  }
}

/**
 * 保守检查具名获取引用：XML/JSON 精确叶值，AS 源码文本。
 * 定义自身、派生字典及资产索引不是获取路径；其余命中须人工语义复核，
 * 不因它看似 NPC 预装就自动放行。动态拼接/通用随机池仍须规则证据说明。
 */
function findUnreviewedItemReferences(
  index: WeaponAcquisitionIndex, itemName: string
): string[] {
  const { repositoryRoot } = index;
  const reviewed = new Set([
    ...(index.goldShopFilesByItem.get(itemName) ?? []),
    ...(index.kshopFilesByItem.get(itemName) ?? []),
    ...(index.craftingFilesByItem.get(itemName) ?? [])
  ]);
  const matches: string[] = [];
  const escapedItemName = itemName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const quotedItemName = new RegExp(`(["'])${escapedItemName}\\1`);
  const xmlParser = new XMLParser({ ignoreAttributes: false, trimValues: true });
  const scan = (directory: string): void => {
    if (!fs.existsSync(directory)) return;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const absolute = path.join(directory, entry.name);
      const relative = toRepositoryPath(repositoryRoot, absolute);
      if (relative === "data/dictionaries") continue;
      if (entry.isDirectory()) { scan(absolute); continue; }
      const ext = path.extname(entry.name).toLowerCase();
      if (![".xml", ".json", ".as"].includes(ext) || reviewed.has(relative) ||
          relative === "data/items/asset_source_map.xml" || relative === "data/tooltip/tooltip-catalog.json") continue;
      const source = fs.readFileSync(absolute, "utf8").replace(/^\uFEFF/, "");
      if (ext === ".as") {
        // AS2 专项类只由 TestLoader 运行，不是正式获取入口；其他脚本仍逐名检查。
        // 钛合金QJZ171 与 QJZ171 是独立物品，不能用子串把变体行为记到原枪名下。
        const focusedTest = relative.startsWith("scripts/类定义/") &&
          /(?:^|\/)test\/[^/]+Test\.as$/.test(relative);
        if (!focusedTest && quotedItemName.test(source)) matches.push(relative);
        continue;
      }
      const parsed: unknown = ext === ".json" ? JSON.parse(source) : xmlParser.parse(source);
      if (!index.catalogFiles.has(relative) && isUnlistedCatalog(relative, parsed)) continue;
      const hasEncodedRewards = index.rewardFiles.has(relative) ||
        /^data\/rag\/agent_saves\/[^/]+\/(agent_tasks|task_reward_overrides)\.json$/.test(relative);
      if (containsItemName(parsed, itemName, relative.startsWith("data/items/"), hasEncodedRewards)) {
        matches.push(relative);
      }
    }
  };
  for (const directory of ["data", "config", "scripts"]) scan(path.join(repositoryRoot, directory));
  return matches.sort();
}

// Only recognize the loaders' own catalog shapes here. Other files retain the generic reference check.
function isUnlistedCatalog(file: string, value: unknown): boolean {
  if (file.startsWith("data/shops/npcs/") && file.endsWith(".json") && isObject(value)) {
    return value.schema === "npc-shop.v2" || (value.schema === undefined && Object.values(value).every(isObject));
  }
  if (!Array.isArray(value) || !file.endsWith(".json")) return false;
  if (file.startsWith("data/kshop/")) return value.every(row => isObject(row) && typeof row.item === "string");
  return file.startsWith("data/crafting/") && value.every(row => isObject(row) && typeof row.name === "string");
}

function containsItemName(value: unknown, itemName: string, skipDefinition: boolean, hasEncodedRewards: boolean): boolean {
  if (value === itemName) return true;
  if (Array.isArray(value)) return value.some((part) => containsItemName(part, itemName, skipDefinition, hasEncodedRewards));
  if (!isObject(value)) return false;
  if (skipDefinition && value.name === itemName && value.type === "武器") return false;
  return Object.entries(value).some(([field, part]) => {
    if (hasEncodedRewards && (field === "rewards" || field === "extra_rewards") && Array.isArray(part)) {
      // ItemUtil.getRequirementFromTask splits on ## when present, otherwise on #.
      if (part.some(entry => typeof entry === "string" &&
          entry.split(entry.includes("##") ? "##" : "#", 1)[0] === itemName)) return true;
    }
    return containsItemName(part, itemName, skipDefinition, hasEncodedRewards);
  });
}

function validateEvidencePath(
  evidenceRef: string | undefined,
  issuePath: string,
  repositoryRoot: string,
  issues: WeaponBalanceEvidenceIssue[]
): string | undefined {
  if (!evidenceRef?.trim()) {
    addError(
      issues,
      "evidence_ref_missing",
      issuePath,
      "display-eligible records require a repository evidence path"
    );
    return undefined;
  }

  const pathPart = evidenceRef.split("#", 1)[0]?.trim();
  if (!pathPart) {
    addError(
      issues,
      "evidence_ref_path_missing",
      issuePath,
      "evidenceRef must begin with a repository-relative file path"
    );
    return undefined;
  }

  const resolved = path.resolve(repositoryRoot, pathPart.replaceAll("/", path.sep));
  const relative = path.relative(repositoryRoot, resolved);
  if (
    path.isAbsolute(pathPart) ||
    relative === "" ||
    relative.startsWith("..") ||
    path.isAbsolute(relative)
  ) {
    addError(
      issues,
      "evidence_ref_outside_repository",
      issuePath,
      "evidenceRef must resolve to a file inside the repository"
    );
    return undefined;
  }

  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    addError(
      issues,
      "evidence_ref_not_found",
      issuePath,
      `evidence file does not exist: ${pathPart}`
    );
    return undefined;
  }

  return toRepositoryPath(repositoryRoot, resolved);
}

function readJson(root: string, file: string): unknown {
  return JSON.parse(fs.readFileSync(path.join(root, file), "utf8").replace(/^\uFEFF/, ""));
}

function listedJsonFiles(root: string, directory: string, tag: string, suffix = ""): string[] {
  const manifest = `${directory}/list.xml`;
  const source = fs.readFileSync(path.join(root, manifest), "utf8");
  if (XMLValidator.validate(source) !== true) throw new Error(`${manifest}: invalid XML`);
  const entries: unknown = new XMLParser({ parseTagValue: false }).parse(source).root?.[tag];
  return (Array.isArray(entries) ? entries : [entries]).map((entry: unknown) => {
    if (typeof entry !== "string" || !entry || entry.includes("\\") || entry.includes(":") ||
        entry.split("/").some(part => !part || part === ".." || part === ".") ||
        !(entry + suffix).endsWith(".json")) throw new Error(`${manifest}: invalid <${tag}> entry`);
    return `${directory}/${entry}${suffix}`;
  });
}

function addReference(index: Map<string, string[]>, name: string, reference: string): void {
  const existing = index.get(name);
  if (!existing) index.set(name, [reference]);
  else if (!existing.includes(reference)) existing.push(reference);
}

function indexCatalogs(root: string, files: string[], extractNames: (value: unknown) => string[]) {
  const result = new Map<string, string[]>();
  for (const file of files) {
    for (const name of extractNames(readJson(root, file))) addReference(result, name, file);
  }
  return result;
}

function extractCraftingNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (isObject(entry) ? entry.name : undefined))
    .filter((name): name is string => typeof name === "string");
}

function extractKshopNames(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => (isObject(entry) ? entry.item : undefined))
    .filter((name): name is string => typeof name === "string");
}

function toRepositoryPath(repositoryRoot: string, absolutePath: string): string {
  return path.relative(repositoryRoot, absolutePath).split(path.sep).join("/");
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function addError(
  issues: WeaponBalanceEvidenceIssue[],
  code: string,
  issuePath: string,
  message: string
): void {
  issues.push({ severity: "error", code, path: issuePath, message });
}
