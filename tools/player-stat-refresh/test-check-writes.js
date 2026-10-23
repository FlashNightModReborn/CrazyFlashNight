'use strict';
const assert=require('assert');
const {scanText}=require('./check-writes');
let count=0;
function check(source,file,errors,kind) {
  const result=scanText(source,file);
  assert.strictEqual(result.filter(row=>row.severity==='error').length,errors,source);
  if(kind) assert(result.some(row=>row.kind===kind));
  count++;
}
check('function updateProperties(t:Object):Void {t.长枪属性.power += 5;}','scripts/Stat.as',1);
check('function requestPersistentRefresh(t:Object):Void {StaticInitializer.initializeUnit(t);}','scripts/Stat.as',1);
check('function refreshStats(t:Object):Void { t.buffManager.update(0); }','scripts/Stat.as',1);
check('function onClick():Void {_root.刷新人物装扮("hero");}','scripts/类定义/org/flashNight/arki/ui/Panel.as',1);
check('<script><![CDATA[function onClick(){_root.刷新人物装扮("hero");}]]></script>','flashswf/UI/LIBRARY/panel.xml',1);
check('function damage(t:Object):Void {t.hp -= 30;}','scripts/Combat.as',0);
check('function heal(t:Object):Void {t.hp = 100;}','scripts/Heal.as',0);
check('function initialize(t:Object):Void {StaticInitializer.initializeUnit(t);}','scripts/Spawn.as',0,'manager_or_lifecycle');
check('function switchRuntimeAlias(t:Object):Void {t.刀属性.power += 5;}','scripts/Weapon.as',0,'managed_compound');
check('function sortRows(rows:Array):Void {rows.sortOn("hp满血值");}','scripts/类定义/org/flashNight/arki/ui/Panel.as',0);
check('function refreshStats(){/* t.hp满血值 += 3; */var x="t.buffManager.update(0)";}','scripts/Stat.as',0);
check('function full(){t.hp满血值 += 4;} function refreshStats(){project();}','scripts/Stat.as',0,'managed_compound');
check('function updateProperties(){var f:Function=function(){t.伤害加成*=2;};}','scripts/Stat.as',1);
check('function committed(){_root.全局健身HP加成 += 10;}','scripts/Gym.as',0,'persistent_input');
console.log(`stat write checker: ${count} mutation/legal fixtures passed`);
