/** Read live acquisition data and reconcile it with the pinned workbook engine. */
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {createHash} from "node:crypto";
import {XMLParser} from "fast-xml-parser";
import {computeSynthesis} from "../../packages/core/src/formulas/economy.js";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../../..");
const read=(file:string)=>fs.readFileSync(path.join(root,file),"utf8").replace(/^\uFEFF/,"");
const parser=new XMLParser({ignoreAttributes:false});
const workbook="0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx";
const workbookSha256=createHash("sha256").update(fs.readFileSync(path.join(root,workbook))).digest("hex");
if(workbookSha256!=="357e07955281d4cb3884902b58165e19e97852216ae5a76965d3ebd04fb4e107") throw Error("workbook changed");
const check=(ok:unknown,message:string)=>{if(!ok)throw Error(message);};
const array=(x:any)=>x===undefined?[]:Array.isArray(x)?x:[x];
const items=new Map<string,any[]>();
const sources=new Set<string>([workbook,"tools/former-sheriff-assets/registration.json","data/crafting/list.xml","data/items/list.xml"]);
// Only inspect item files listed by the real loader, not archived definitions.
const manifest=parser.parse(read("data/items/list.xml"));
const itemFiles=array(manifest.root.items);
check(itemFiles.length>0,"item manifest is empty");
for(const entry of itemFiles){
  const file="data/items/"+entry;
  for(const item of array(parser.parse(read(file)).root?.item)){
    const found=items.get(String(item.name))??[];
    found.push({...item,sourceFile:file}); items.set(String(item.name),found);
  }
}
function item(name:string){
  const matches=items.get(name)??[];
  check(matches.length===1,"item identity is missing/ambiguous: "+name);
  sources.add(matches[0].sourceFile); return matches[0];
}
const registration=JSON.parse(read("tools/former-sheriff-assets/registration.json"));
const names=new Set<string>(registration.items.map((x:any)=>x.name));
const expectedDonors=new Map<string,{name:string;priceLayers:number;category:number}>([
  ["重装特勤头盔",{name:"特战队员头部装备",priceLayers:1,category:1}],
  ["重装特勤背心",{name:"特战队员战术背心",priceLayers:1,category:1}],
  ["重装特勤手套",{name:"特战队员手套",priceLayers:1,category:1}],
  ["重装特勤战术裤",{name:"特战队员战术裤",priceLayers:1,category:1}],
  ["重装特勤战靴",{name:"特战队员鞋子",priceLayers:1,category:1}],
  ["特勤警棍",{name:"美式警棍",priceLayers:0,category:1}],
  ["特勤霰弹枪",{name:"XM1014",priceLayers:0,category:1.5}],
  ["特勤沙鹰",{name:"Desert Eagle",priceLayers:0,category:1}]
]);
const recipes:any[]=[];
for(const category of array(parser.parse(read("data/crafting/list.xml")).root.list)){
  const file=`data/crafting/${category}.json`;
  sources.add(file);
  for(const recipe of JSON.parse(read(file))) if(names.has(recipe.name)) recipes.push({...recipe,category,sourceFile:file});
}
check(recipes.length===8&&new Set(recipes.map(x=>x.name)).size===8,"expected one recipe per sheriff item");
const supplierFile="data/shops/npcs/前治安官.json";
const supplier=JSON.parse(read(supplierFile)); sources.add(supplierFile);
const supplied=new Set(Object.values(supplier.catalog).map((x:any)=>typeof x==="string"?x:x.name));
const productShops:string[]=[];
for(const folder of ["data/shops/npcs","data/kshop"]){
  for(const filename of fs.readdirSync(path.join(root,folder)).filter(x=>x.endsWith(".json"))){
    const file=folder+"/"+filename; sources.add(file);
    // Only exact JSON string leaves count, not substring matches in descriptions.
    function visit(x:any):void {
      if(typeof x==="string"&&names.has(x)) productShops.push(file+"#"+x);
      else if(Array.isArray(x)) x.forEach(visit);
      else if(x&&typeof x==="object") Object.values(x).forEach(visit);
    }
    visit(JSON.parse(read(file)));
  }
}
check(productShops.length===0,"finished equipment must not bypass crafting: "+productShops.join(","));
const rows=recipes.map(recipe=>{
  const product=item(recipe.name),donor=expectedDonors.get(recipe.name)!;
  const expectedCategory=product.type==="防具"?"公社防具":"铁枪会";
  check(recipe.category===expectedCategory,"wrong workbench for "+recipe.name+": expected "+expectedCategory);
  check(product.data.level===21&&recipe.kprice===0,"level/K-point drift: "+recipe.name);
  check(Number.isSafeInteger(recipe.price)&&recipe.price>=0,"invalid crafting fee");
  let equipmentPrice=0,materialPrice=0,equipmentCount=0,retailIngredients=0;
  const materials=recipe.materials.map((encoded:string)=>{
    const parts=encoded.split("#"),ingredient=item(parts[0]),quantity=Number(parts[1]);
    check(parts.length===2&&Number.isSafeInteger(quantity)&&quantity>0,"invalid ingredient: "+encoded);
    check(supplied.has(ingredient.name),"supplier does not carry "+ingredient.name);
    retailIngredients+=Number(ingredient.price)*quantity;
    if(ingredient.type==="武器"||ingredient.type==="防具"){
      equipmentCount+=quantity;
      check(ingredient.name===donor.name&&quantity===1,"wrong donor for "+recipe.name);
      check(ingredient.data.level<product.data.level,"donor level exceeds product progression");
      check(ingredient.use===product.use,"equipment slot mismatch");
      const divisor=ingredient.type==="防具"||ingredient.use==="手枪"?1.5:1;
      const value=.25*ingredient.data.level*3900*Math.pow(1.6,donor.priceLayers)*donor.category/divisor;
      equipmentPrice+=value;
      return {name:ingredient.name,quantity,cost:value,kind:"equipment",level:ingredient.data.level,
        priceLayers:donor.priceLayers,categoryFactor:donor.category,divisor};
    }
    check(ingredient.use==="材料","not a supported material: "+ingredient.name);
    const description=String(ingredient.description);
    const unitCost=description.includes("低级材料")?1000:description.includes("中等材料")?6000:description.includes("高等材料")?50000:NaN;
    check(Number.isFinite(unitCost)&&unitCost===Number(ingredient.price),"material tier needs explicit review: "+ingredient.name);
    materialPrice+=unitCost*quantity;
    return {name:ingredient.name,quantity,cost:unitCost*quantity,kind:"material"};
  });
  check(equipmentCount===1,"recipe needs one predecessor");
  const raceFactor=product.type==="防具"?.5:product.use==="刀"?1:2;
  const totals=computeSynthesis({level:21,weightLayers:2,raceFactor,goldCost:recipe.price,kPointCost:0,materialPrice,equipmentPrice,dropPrice:0});
  const residual=totals.currentCost/totals.weightedCost-1;
  // A local authored rounding band, not a tolerance claimed to come from XLSX.
  check(Math.abs(residual)<=.05,"recipe cost outside the reviewed 5% rounding band: "+recipe.name);
  return {...recipe,level:21,weightLayers:2,raceFactor,materials,materialPrice,equipmentPrice,...totals,residual,
    productPrice:Number(product.price),retailIngredients,retailTotal:retailIngredients+recipe.price};
});
const mapFile="flashswf/levels/地图-第一防线防区/LIBRARY/地图-第一防线防区.xml";
const mapSource=read(mapFile);
check(/加载改装清单\("公社防具"\)/.test(mapSource),"armor workbench opener drift");
check(/加载改装清单\("铁枪会"\)/.test(mapSource),"weapon forge opener drift");
check(mapSource.includes('检查基建等级("铁枪图腾", 1)'),"weapon forge unlock condition drift");
sources.add(mapFile);
const report={schema:"former-sheriff-acquisition.v1",workbookSha256,status:"data_configured_runtime_pending",
  formula:"level * 2000 * category * 1.6^(synthesisLayers - 1)",
  notes:["总成本为公式折算值，不是购买所有材料所需的金币；手续费为铁匠技能折扣前值。",
    "合成表成本D33采用已定2层；枪械C26购买限定与高价合成的属性层映射仍保留unresolved。",
    "防具无成品购买途径，按装备价格D22使用0.5；前置特战套按购买高价层1折算。",
    "未改动战斗面板、玩家存档、地图与Flash运行逻辑。"],
  workbenches:[
    {category:"公社防具",scene:"第一防线",existingLabel:"防具合成",sourceFile:mapFile},
    {category:"铁枪会",scene:"第一防线",existingLabel:"覆写锻炉",unlock:"铁枪图腾1级",sourceFile:mapFile}
  ],
  supplier:{name:"前治安官",sourceFile:supplierFile},rows,
  sourceDigests:Object.fromEntries([...sources].sort().map(file=>[file,createHash("sha256").update(fs.readFileSync(path.join(root,file))).digest("hex")]))};
const out=path.join(root,"tmp/former-sheriff-integration/acquisition-report.json");
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(report,null,2)+"\n");
console.log(JSON.stringify(rows.map(x=>({name:x.name,fee:x.price,currentCost:x.currentCost,target:x.weightedCost,residual:x.residual,retailTotal:x.retailTotal})),null,2));
