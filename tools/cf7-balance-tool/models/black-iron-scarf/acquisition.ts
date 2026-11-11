/**
 * #227：读取现役物品、标定与配方，复算三件头装和目镜围巾合成成本。
 * 维护者于2026-11-11采纳无成品直售系数0.5优先、三件属性不变的方案。
 * 仓库根运行：node --import ./tools/cf7-balance-tool/node_modules/tsx/dist/loader.mjs tools/cf7-balance-tool/models/black-iron-scarf/acquisition.ts
 * 只作离线数据与公式核对，不证明真实存档交易、夜视观感或正式部署。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { XMLParser } from "fast-xml-parser";
import { computeArmorRow } from "../../packages/core/src/formulas/armor.js";
import { computeSynthesis } from "../../packages/core/src/formulas/economy.js";
import { ARMOR_BALANCE_WORKBOOK_SHA256, parseArmorBalancePlan } from "../../packages/core/src/armor-balance/record.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");
const parser = new XMLParser({ ignoreAttributes: false });
const inputs = new Map<string, string>();
function check(ok: unknown, message: string): asserts ok { if (!ok) throw new Error(message); }
function read(file: string): string {
  const raw = fs.readFileSync(path.join(root, file));
  inputs.set(file, createHash("sha256").update(raw).digest("hex"));
  return raw.toString("utf8").replace(/^\uFEFF/, "");
}
function array<T>(value: T | T[] | undefined): T[] { return value === undefined ? [] : Array.isArray(value) ? value : [value]; }
const workbook = "0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx";
const workbookSha256 = createHash("sha256").update(fs.readFileSync(path.join(root, workbook))).digest("hex");
check(workbookSha256.toUpperCase() === ARMOR_BALANCE_WORKBOOK_SHA256, "权威工作簿已变更，请重新标定");
const plan = parseArmorBalancePlan(parser.parse(read("tools/cf7-balance-tool/records/armor-balance-plan.xml")));
const items = new Map<string, any>();
const relevantNames = new Set(["黑铁死士围巾", "锐刻幻影夜视仪", "黑铁游侠围巾", "透镜", "军用帆布", "增效剂"]);
for (const file of ["data/items/防具_0-19级.xml", "data/items/收集品_材料_插件.xml"]) {
  for (const item of array<any>(parser.parse(read(file)).root.item)) {
    if (!relevantNames.has(item.name)) continue;
    check(!items.has(item.name), "重复物品身份：" + item.name);
    items.set(item.name, item);
  }
}
function item(name: string): any { const value = items.get(name); check(value, "缺失物品：" + name); return value; }
function record(name: string) {
  const matches = plan.records.filter(row => row.itemName === name && row.sourceFile === "data/items/防具_0-19级.xml");
  check(matches.length === 1, "标定记录身份不唯一：" + name);
  check(matches[0].balanceMode === "formula" && matches[0].status === "confirmed", "标定尚未确认：" + name);
  return matches[0];
}
const decisions = [
  {name:"黑铁死士围巾", price:16000, M:0, G:0.5},
  {name:"锐刻幻影夜视仪", price:50000, M:0, G:1.5},
  {name:"黑铁游侠围巾", price:20000, M:1, G:0.5},
];
const rows = decisions.map(expected => {
  const product = item(expected.name), calibration = record(expected.name), d = product.data;
  check(product.price === expected.price && calibration.adoptedGoldPrice === expected.price, "售价漂移：" + expected.name);
  check(calibration.weightLayers === expected.M && calibration.priceLayers === 0
    && calibration.category === expected.G && calibration.damageTypeFactor === 1, "已采纳系数漂移：" + expected.name);
  const output = computeArmorRow({level:d.level, weight:d.weight, defence:d.defence || 0,
    hp:d.hp || 0, mp:d.mp || 0, damageBonus:d.damage || 0,
    weaponBonus:(d.knifepower || 0) + (d.gunpower || 0), punchBonus:d.punch || 0,
    magicDefence:Object.values(d.magicdefence || {}).reduce<number>((sum, value) => sum + Number(value), 0),
    extraWeightLayers:calibration.weightLayers});
  const formulaPrice = d.level * 2600 * 1.6 ** calibration.priceLayers * calibration.category;
  check(Math.abs(output.currentScore / output.weightedScore - 1) <= 0.05, "属性拟合超出5%：" + expected.name);
  check(product.price / formulaPrice >= 0.8 && product.price / formulaPrice <= 1.25, "价格超出取整带：" + expected.name);
  return {name:expected.name, price:product.price, formulaPrice,
    currentScore:output.currentScore, targetScore:output.weightedScore};
});

const productName = "黑铁游侠围巾";
function hasExactName(value: unknown): boolean {
  if (typeof value === "string") return value === productName;
  if (value && typeof value === "object") return Object.values(value).some(hasExactName);
  return false;
}
for (const folder of ["data/shops/npcs", "data/kshop"]) {
  for (const name of fs.readdirSync(path.join(root, folder)).filter(name => name.endsWith(".json"))) {
    check(!hasExactName(JSON.parse(read(folder + "/" + name))), "出现成品直售，需重新裁定种类系数：" + name);
  }
}
const tasks = JSON.parse(read("data/task/tasks1.json")).tasks;
check(tasks.some((task: any) => task.id === 25 && task.rewards.includes("黑铁死士围巾#1") && task.chain === "主线#26"), "死士围巾奖励来源漂移");
const map = JSON.parse(read("data/map/map_definition.json"));
const presence = map.placements.place_c7e60636436b3d3e.presenceWhen;
check(presence.type === "chain" && presence.key === "主线" && presence.min === 69, "外交部长获取顺序需重审");
const supplier = JSON.parse(read("data/shops/npcs/学生妹.json"));
check(Object.values(supplier.catalog).some((entry: any) => (typeof entry === "string" ? entry : entry.name) === "透镜"), "透镜供应缺失");

const recipes = JSON.parse(read("data/crafting/黑白契约.json"));
const recipe = recipes.find((entry: any) => entry.recipeId === "craft.black-white.001");
check(recipe && recipe.name === productName && (recipe.value ?? 1) === 1, "配方产物身份或数量漂移");
check(recipe.price === 1100 && recipe.kprice === 0, "配方基础工费/K点漂移");
check(JSON.stringify(recipe.materials) === JSON.stringify(["黑铁死士围巾#1", "透镜#1", "军用帆布#2", "增效剂#2"]), "配方材料漂移");
let equipmentCost = 0, materialCost = 0, retailMaterials = 0;
for (const encoded of recipe.materials) {
  const [name, quantityText] = encoded.split("#"), ingredient = item(name), quantity = Number(quantityText);
  check(Number.isSafeInteger(quantity) && quantity > 0, "材料数量无效：" + encoded);
  retailMaterials += ingredient.price * quantity;
  if (ingredient.type === "防具") {
    const calibration = record(name);
    // 原表合成表成本J13：装备数量×25%×等级×3900×1.6^价格层×种类系数÷防具系数1.5。
    equipmentCost += quantity * 0.25 * ingredient.data.level * 3900 * 1.6 ** calibration.priceLayers * calibration.category / 1.5;
  } else {
    check(ingredient.use === "材料", "配方前置不是材料：" + name);
    const tierPrice = ingredient.description.includes("低级材料") ? 1000 : ingredient.description.includes("中等材料") ? 6000 : NaN;
    check(tierPrice === ingredient.price, "材料档位价格需重审：" + name);
    materialCost += tierPrice * quantity;
  }
}
const product = item(productName), calibration = record(productName);
const crafting = calibration.budgetBreakdown.find(entry => entry.code === "acquisition.crafting");
check(crafting?.delta === 1 && crafting.evidenceRef === "data/crafting/黑白契约.json#craft.black-white.001", "合成预算证据漂移");
const cost = computeSynthesis({level:product.data.level, weightLayers:crafting.delta, raceFactor:calibration.category,
  goldCost:recipe.price, kPointCost:recipe.kprice, materialPrice:materialCost, equipmentPrice:equipmentCost, dropPrice:0});
check(cost.currentCost === cost.weightedCost && cost.currentCost === 15000, "配方公式成本未闭合");
console.log(JSON.stringify({schema:"black-iron-scarf-acquisition.v1", workbookSha256, items:rows,
  recipeId:recipe.recipeId, equipmentCost, materialCost, craftingFee:recipe.price, ...cost,
  retailTotal:retailMaterials + recipe.price,
  sourceDigest:createHash("sha256").update(JSON.stringify([...inputs].sort())).digest("hex"),
  evidenceScope:"离线标定与配方成本；不代签实机交易、实战或部署"}, null, 2));
