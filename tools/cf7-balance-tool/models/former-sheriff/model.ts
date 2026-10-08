/** Lv21 sheriff candidate: reuse canonical formula engines; runtime stats stay in item XML. */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { XMLParser } from "fast-xml-parser";
import { computeArmorRow } from "../../packages/core/src/formulas/armor.js";
import { computeWeaponRow, type WeaponInput } from "../../packages/core/src/formulas/weapons.js";
import { computeMeleeRow } from "../../packages/core/src/formulas/melee.js";
import { computeArmorPrice, computeWeaponPrice } from "../../packages/core/src/formulas/economy.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");
const parser = new XMLParser({ ignoreAttributes: false });
const read = (p: string) => fs.readFileSync(path.join(root, p), "utf8");
const workbook = "0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx";
const expectedSha = "357e07955281d4cb3884902b58165e19e97852216ae5a76965d3ebd04fb4e107";
if (createHash("sha256").update(fs.readFileSync(path.join(root, workbook))).digest("hex") !== expectedSha) throw Error("workbook changed");
const registration = JSON.parse(read("tools/former-sheriff-assets/registration.json"));
const items = (file: string): any[] => parser.parse(read(file)).root.item;
const round = (n: number, step: number) => Math.round(n / step) * step;
// Acquisition is crafting-only. E is not the two-layer synthesis budget.
const level = 21, weightLayers = 2, priceLayers = 0;
const armors = registration.items.filter((i: any) => i.name.startsWith("重装特勤")).map((spec: any) => {
  const donor = items("data/items/防具_0-19级.xml").find(i => i.name === (spec.artDonor ?? spec.placeholderFrom)).data;
  const input = (d: any, layers: number) => ({level: d.level, weight: d.weight, defence: d.defence,
    hp: d.hp, mp: d.mp, damageBonus: d.damage, weaponBonus: 0, punchBonus: 0, magicDefence: 0, extraWeightLayers: layers});
  const target = computeArmorRow(input({...donor, level}, weightLayers)).weightedScore;
  const scale = target / computeArmorRow(input(donor, 0)).currentScore;
  const hp = round(donor.hp * scale, 5), mp = round(donor.mp * scale, 5), damage = round(donor.damage * scale, 5);
  const data = {level, weight: donor.weight, hp, mp, damage, defence: round((target - hp - mp - damage * 3) / 2, 5)};
  const {currentScore,balanceScore,weightedScore,magicDefAvgCap,magicDefMaxCap} = computeArmorRow(input(data, weightLayers));
  // computeArmorRow also quotes prices using M; the adopted price uses E below.
  const score = {currentScore,balanceScore,weightedScore,magicDefAvgCap,magicDefMaxCap};
  // 装备价格!D22: armor without a purchase route uses category 0.5.
  const category = 0.5;
  const price = round(computeArmorPrice({level, weightLayers:priceLayers, categoryFactor:category, damageTypeFactor:1}).goldPrice, 100);
  return {name:spec.name, file:spec.file, category, data, price, score, residual:score.currentScore / score.weightedScore - 1};
});

function solve(fixed: Omit<WeaponInput, "bulletPower">) {
  let lo = 1, hi = 100000;
  for (let n=0; n<80; n++) {
    const mid=(lo+hi)/2, row=computeWeaponRow({...fixed, bulletPower:mid});
    if (row.averageDPS > row.weightedDPS) hi=mid; else lo=mid;
  }
  return round((lo+hi)/2, 5);
}
const ammo = items("data/items/消耗品_弹夹.xml");
const guns = [
  // Preserve the ordinary-shotgun DPS base; price the finished piercing weapon.
  {name:"特勤霰弹枪", file:"data/items/武器_长枪_霰弹枪.xml", pierce:1, category:2, earlyPenalty:0},
  {name:"特勤沙鹰", file:"data/items/武器_手枪_大威力手枪.xml", pierce:2, category:2, earlyPenalty:1}
].map(spec => {
  const item=items(spec.file).find(i => i.name===spec.name), d=item.data, dw=item.use==="长枪"?1:2;
  const fixed={level, shootInterval:Number(d.interval), magSize:Number(d.capacity), magPrice:Number(ammo.find(i=>i.name===d.clipname).price),
    weight:dw===1?6:Number(d.weight), dualWieldFactor:dw, pierceFactor:spec.pierce, damageTypeFactor:1,
    shotgunValue:dw===1?7:Number(d.split), impact:dw===1?20:Number(d.impact), extraWeightLayers:weightLayers-spec.earlyPenalty, categoryFactor:spec.category};
  const power=solve(fixed), result=computeWeaponRow({...fixed, bulletPower:power});
  // Price sheet uses 1.5 for pistols; DPS uses 2. They are distinct inputs.
  const price=round(computeWeaponPrice({level, weightLayers:priceLayers, dualWieldFactor:dw===2?1.5:1, categoryFactor:spec.category, damageTypeFactor:1}).goldPrice,100);
  const singleFixed={...fixed,dualWieldFactor:1};
  const singlePower=solve(singleFixed), singleResult=computeWeaponRow({...singleFixed,bulletPower:singlePower});
  const singleHand=dw===2?{power:singlePower,attackBonusType:"长枪",fixed:singleFixed,
    residual:singleResult.averageDPS/singleResult.weightedDPS-1}:undefined;
  const data=dw===1?{level,power:power*2,weight:8.5,split:1,diffusion:4,impact:2,bulletsize:42,
    modslot:0,defence:20,toughness:50,accuracy:-10,vampirism:3}:{level,power};
  return {...spec, data, singleHand, basePower:power,
    builtins:dw===1?["八门金锁镇暴弹","战术手电","矢量偏转枪盾","汲丝虹吸匣"]:[],
    removeFields:spec.name==="特勤沙鹰"?["slay"]:[], price, fixed,
    residual:result.averageDPS/result.weightedDPS-1, averageDPS:result.averageDPS, weightedDPS:result.weightedDPS};
});
const meleeItem=items("data/items/武器_刀_短兵.xml").find(i=>i.name==="特勤警棍");
const knife=computeMeleeRow({level,weight:Number(meleeItem.data.weight),damageTypeFactor:1,weightLayers});
const power=round(knife.recommendedSharpness,5);
const melee={name:"特勤警棍",file:"data/items/武器_刀_短兵.xml",data:{level,power,defence:0},
  price:round(computeWeaponPrice({level,weightLayers:priceLayers,dualWieldFactor:1,categoryFactor:1,damageTypeFactor:1}).goldPrice,100),
  recommendedSharpness:knife.recommendedSharpness,
  modes:{status:"active",key:"weaponTransform",frames:15,baton:{power:power-110,conditionalDefence:165,actionType:"棍棒"},dagger:{power,conditionalDefence:0,actionType:"短兵"}},
  residual:power/knife.recommendedSharpness-1};
const report={level,weightLayers,priceLayers,workbookSha256:expectedSha,
  status:"stats_configured_gameplay_pending",armors,guns,melee};
if (process.argv.includes("--check")) {
  for (const spec of [...armors,...guns,melee]) {
    const item=items(spec.file).find(i=>i.name===spec.name);
    for(const [key,value] of Object.entries(spec.data)) if(value!==undefined && Number(item.data[key])!==value) throw Error(`${spec.name}.${key} drift`);
    if(Number(item.price)!==spec.price || Math.abs(spec.residual)>.05) throw Error(`${spec.name} price/fit drift`);
    for(const field of ("removeFields" in spec ? spec.removeFields : [])) if(item.data[field]!==undefined) throw Error(`${spec.name}.${field} still active`);
  }
  for(const gun of guns) if(gun.singleHand && (Number(items(gun.file).find(i=>i.name===gun.name).singleHand?.power)!==gun.singleHand.power
    || Math.abs(gun.singleHand.residual)>.05)) throw Error("single-hand profile drift");
  const transform=meleeItem.lifecycle?.attr_sheriffBaton;
  if(transform?.skillInteraction!=="independent" || transform?.init?.initRoutines!=="特勤警棍初始化"
    || transform?.cycle?.cycleRoutines!=="特勤警棍周期"
    || Number(transform?.init?.initParam?.frameMax)!==melee.modes.frames
    || Number(transform?.init?.initParam?.batonPower)!==melee.modes.baton.power
    || Number(transform?.init?.initParam?.batonDefence)!==melee.modes.baton.conditionalDefence
    || transform?.init?.initParam?.actionTypeA!=="棍棒" || transform?.init?.initParam?.actionTypeB!=="短兵"
    || meleeItem.actiontype!=="棍棒")
    throw Error("sheriff baton transform lifecycle/budget drift");
}
const out=path.join(root,"tmp/former-sheriff-integration/balance-report.json");
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(report,null,2)+"\n");
console.log(JSON.stringify([...armors,...guns,melee].map(i=>({name:i.name,...i.data,price:i.price,residual:i.residual})),null,2));
