import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.HeroUtil;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.SpeedDeriveInitializer;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;

/**
 * DressupInitializer - 装备初始化器
 *
 * 负责单位的装备加载、属性计算、装扮更新等初始化工作
 *
 * ============================================================================
 * 性能分析记录 (2025-12-25)
 * ============================================================================
 *
 * 【测试环境】
 * - 样本: 24个单位初始化，共278次getData调用，267次装备计算
 * - 每单位约11件装备（头部、上装、手部、下装、脚部、颈部、长枪、手枪、手枪2、刀、手雷）
 *
 * 【优化前整体耗时分布】
 * ┌────────────────────────┬────────┬────────┐
 * │ 模块                   │ 耗时   │ 占比   │
 * ├────────────────────────┼────────┼────────┤
 * │ getData (数值计算)     │ 117ms  │ 73.1%  │
 * │ 生命周期装载           │ 13ms   │ 8.1%   │
 * │ 属性更新               │ 10ms   │ 6.3%   │
 * │ 其他                   │ 20ms   │ 12.5%  │
 * └────────────────────────┴────────┴────────┘
 *
 * 【优化前 getData 内部分解】(BaseItem.getData)
 * ┌────────────────────────┬────────┬────────┐
 * │ 操作                   │ 耗时   │ 占比   │
 * ├────────────────────────┼────────┼────────┤
 * │ getItemData (克隆)     │ 42ms   │ 29%    │
 * │ calculateData          │ 102ms  │ 71%    │
 * └────────────────────────┴────────┴────────┘
 *
 * 【优化前 EquipmentCalculator.calculatePure 内部分解】
 * ┌────────────────────────┬────────┬────────┐
 * │ 阶段                   │ 耗时   │ 占比   │
 * ├────────────────────────┼────────┼────────┤
 * │ clone itemData         │ 48ms   │ 53.9%  │  ← 已优化：消除冗余克隆
 * │ applyOperators         │ 26ms   │ 29.2%  │
 * │   - clone baseData     │ 12ms   │ 13.5%  │  ← 已优化：延迟到需要时克隆
 * │ accumulateModifiers    │ 9ms    │ 10.1%  │
 * │ buildMultiplier        │ 3ms    │ 3.4%   │
 * │ applyTierData          │ 0ms    │ 0%     │
 * └────────────────────────┴────────┴────────┘
 *
 * 【优化前关键结论】
 * 性能瓶颈: ObjectUtil.clone 深度克隆操作
 * - ItemUtil.getItemData 中克隆: 42ms
 * - EquipmentCalculator.calculatePure 开头克隆: 48ms (冗余!)
 * - applyOperatorsInOrder 中克隆 baseData: 12ms (可延迟!)
 * - 总克隆耗时: ~102ms，占总耗时的 64%
 *
 * ============================================================================
 * 性能优化实施 (2024-12-25)
 * ============================================================================
 *
 * 【第一阶段优化】消除冗余克隆
 * 1. 新增 calculateInPlace 方法（EquipmentCalculator.as）
 *    - 消除冗余克隆：ItemUtil.getItemData已返回克隆数据，无需二次克隆
 *    - 节省: ~48ms/批次 (30%)
 *
 * 2. 延迟 baseData 克隆（applyOperatorsInOrder）
 *    - 仅当存在 cap 修改器时才执行克隆
 *    - 节省: ~12ms/批次 (7.5%，视装备配置)
 *
 * 3. 修改 EquipmentUtil.calculateData 使用 calculateInPlace
 *    - 直接就地计算，避免克隆+回写的开销
 *
 * 【第二阶段优化】使用 cloneFast 快路径
 * 4. ItemUtil.getItemData 改用 ObjectUtil.cloneFast
 *    - 物品数据满足快路径条件：无循环引用、浅嵌套、纯数据
 *    - 实测加速比: 1.63x（基准测试: 62ms clone vs 38ms cloneFast）
 *    - 节省: ~16ms/批次（克隆耗时从42ms降至约26ms）
 *
 * 5. EquipmentCalculator 内部克隆改用 cloneFast
 *    - baseData, overrider, skill 均为简单对象
 *    - 额外节省: ~1ms/批次
 *
 * 【预期优化效果】（基于实测 cloneFast 1.63x 加速比）
 * ┌────────────────────────┬────────┬────────┬────────┐
 * │ 指标                   │ 优化前 │ 优化后 │ 提升   │
 * ├────────────────────────┼────────┼────────┼────────┤
 * │ getItemData 克隆       │ 42ms   │ ~26ms  │ ~38%   │
 * │ calculateData 克隆     │ 60ms   │ 0ms    │ 100%   │
 * │ 总克隆耗时             │ 102ms  │ ~27ms  │ ~74%   │
 * │ 单位初始化总耗时       │ 160ms  │ ~83ms  │ ~48%   │
 * │ 平均单次耗时           │ 6.67ms │ ~3.5ms │ ~48%   │
 * └────────────────────────┴────────┴────────┴────────┘
 *
 * 【相关文件】
 * - EquipmentCalculator.as: calculateInPlace + cloneFast
 * - EquipmentUtil.as: calculateData 改用 calculateInPlace
 * - ItemUtil.as: getItemData 改用 cloneFast
 * - ObjectUtil.as: 新增 cloneFast 快路径
 *
 * ============================================================================
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer {

    private static var equipmentKeys:Object = {
        头部装备: "头部装备数据", 
        上装装备: "上装装备数据", 
        手部装备: "手部装备数据", 
        下装装备: "下装装备数据", 
        脚部装备: "脚部装备数据", 
        颈部装备: "颈部装备数据", 
        长枪: "长枪数据", 
        手枪: "手枪数据", 
        手枪2: "手枪2数据", 
        刀: "刀数据", 
        手雷: "手雷数据"
    };
    private static var weaponKeys:Object = {
        长枪: "长枪属性", 
        手枪: "手枪属性", 
        手枪2: "手枪2属性", 
        刀: "刀属性", 
        手雷: "手雷属性"
    };
    private static var weaponPrefixKeys:Object = {
        长枪: "长枪", 
        手枪: "手枪", 
        手枪2: "手枪2", 
        刀: "兵器", 
        手部装备: "空手", 
        手雷: "手雷"
    };
    private static var removePropertyFunc:Object = {
        长枪: removePrimaryProperty, 
        手枪: removeSecondary1Property, 
        手枪2: removeSecondary2Property, 
        刀: removeMeleeProperty, 
        手部装备: removeHandProperty, 
        手雷: removeGrenadeProperty
    };

    // 只保存本专项公式读取的值，不保存 MovieClip、函数、弹药或运行状态。
    private static var numericInputKeys:Array = ["hp","mp","defence","damage","force","knifepower","gunpower",
        "punch","toughness","evasion","lazymiss","poison","vampirism","rout","accuracy","criticalhit",
        "slay","silence","damagetype","magictype","power","weight","speed","capacity",
        "impact","velocity","interval","diffusion","split","bullethit","muzzle","sound","bullet"];

    public static function copyNumericInput(data:Object):Object {
        if (data == null) return null;
        var result:Object = {};
        for (var i:Number=0; i<numericInputKeys.length; i++) {
            var key:String = numericInputKeys[i];
            if (data[key] != undefined) result[key] = data[key];
        }
        if (data.magicdefence != undefined) {
            result.magicdefence = {};
            for (var resistance:String in data.magicdefence) result.magicdefence[resistance] = data.magicdefence[resistance];
        }
        return result;
    }

    private static function recordNumericSource(target:Object, slot:String, item:Object, itemData:Object):Void {
        if (target.__persistentEquipmentInputV1 == undefined) target.__persistentEquipmentInputV1 = {slots:{}};
        target.__persistentEquipmentInputV1.slots[slot] = {item:item,
            signature:RuntimeEquipmentProjection.numericSourceSignature(item),
            data:copyNumericInput(itemData.data)};
        if (slot == "刀" && (item.name == "烬灭裁决" || item.name == "烬灭裁决双刀")) {
            var record:Object = target.__persistentEquipmentInputV1.slots[slot];
            var alternate:String = item.name == "烬灭裁决" ? "烬灭裁决双刀" : "烬灭裁决";
            var value:Object = {level:item.value.level,tier:item.value.tier,mods:item.value.mods instanceof Array ? item.value.mods.concat() : []};
            var other:BaseItem = new BaseItem(alternate,value,item.lastUpdate);
            record.forms = {};
            record.forms[item.name] = copyNumericInput(itemData.data);
            record.forms[alternate] = copyNumericInput(other.getData().data);
        }
    }

    /** 缺失/过期时拒绝；绝不从已 Buff 的 live 输出反推，也不在 STATS 调 getData。 */
    public static function readNumericSources(target:Object):Object {
        var input:Object = target.__persistentEquipmentInputV1;
        if (input == undefined) return null;
        for (var slot:String in equipmentKeys) {
            var record:Object = input.slots[slot];
            var item:Object = RuntimeEquipmentProjection.numericSourceRef(target,slot);
            if (record == undefined || record.item !== item || record.signature == null
                    || record.signature !== RuntimeEquipmentProjection.numericSourceSignature(item)) return null;
        }
        return input;
    }

    private static var persistentNumberKeys:Array = ["hp满血值","mp满血值","hp满血值装备加层","mp满血值装备加层",
        "装备防御力","懒闪避","伤害加成","空手攻击力","内力","装备刀锋利度加成","装备枪械威力加成",
        "毒","吸血","击溃","基础毒","基础吸血","基础击溃","基础斩杀","基础命中加成",
        "命中加成","韧性加成","闪避加成","防御力","命中率","韧性系数","躲闪率"];
    private static var persistentValueKeys:Array = ["伤害类型","魔法伤害属性","基础伤害类型","基础魔法伤害属性"];
    private static var persistentInputKeys:Array = ["_name","等级","hp基本满血值","mp基本满血值","基本空手攻击力",
        "空手攻击力_min","空手攻击力_max","基本防御力","体重","基础命中率","基础韧性系数","基础躲闪率",
        "是否为敌人","_yscale","攻击模式","装备投影含模板魔法抗性"];
    private static var weaponValueSuffixes:Array = ["伤害类型","魔法伤害属性","毒","吸血","击溃","命中加成","暴击","斩杀","消音","消音策略"];
    private static var projectionFaultForTests:Function;
    public static function _setProjectionFaultForTests(value:Function):Void { projectionFaultForTests=value; }

    /** 同一个绝对贡献供完整被动与普通投影使用；停用/同伴出战明确返回零。 */
    public static function lonerContribution(target:Object):Object {
        var skill:Object = target.被动技能.独行者;
        var level:Number = Number(skill.等级);
        var result:Object = {hp:0,mp:0,damage:0,defense:0};
        if (skill.启用 && !isFinite(level)) throw new Error("stat_skill_invalid:loner");
        if (!skill.启用 || !(level > 0)) return result;
        var limits:Object = _root.限制系统;
        var companionDisabled:Boolean = (!limits.limitLevel || _root.难度等级 >= limits.limitLevel) && limits.DisableCompanion;
        if (!companionDisabled) {
            for (var p:Number=0; p<_root.宠物信息.length; p++) if (_root.宠物信息[p][4] == 1) return result;
            for (var m:Number=0; m<_root.佣兵个数限制; m++) {
                var merc:Object = _root.同伴数据[m];
                if (_root.佣兵是否出战信息[m] == 1 && merc[1] != undefined && merc[1] != "undefined") return result;
            }
        }
        return {hp:level*50,mp:level*50,damage:level*10,defense:level*30};
    }

    public static function applyBasePassiveContribution(target:Object):Void {
        var previous:Object = target.__lonerContribution;
        if (previous == undefined) previous = {hp:0,mp:0,damage:0,defense:0};
        var next:Object = lonerContribution(target);
        var hpFull:Boolean = target.hp == target.hp满血值;
        var mpFull:Boolean = target.mp == target.mp满血值;
        var keys:Object = {hp满血值:"hp",mp满血值:"mp",伤害加成:"damage",防御力:"defense"};
        for (var key:String in keys) {
            var part:String = keys[key];
            var base:Number = typeof target.buffManager.getBaseValue == "function" ? target.buffManager.getBaseValue(key) : Number(target[key]);
            setPersistentBase(target,key,base+next[part]-previous[part]);
        }
        if (hpFull) target.hp += next.hp-previous.hp;
        if (mpFull) target.mp += next.mp-previous.mp;
        target.__lonerContribution = next;
    }

    /** 真实战技动作才安装/移除一对通用 ADD；普通投影只换基底。 */
    public static function beginBlackRhinoTransfer(target:Object):Boolean {
        if (target.转换的冷兵器加成 > 0 || !(target.空手攻击力 > 100)) return false;
        if(target.刀属性==undefined || !isFinite(Number(target.刀属性.power))) return false;
        var amount:Number = target.空手攻击力-100;
        if (!isFinite(amount) || typeof target.buffManager.addBuff != "function") return false;
        target.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("空手攻击力","add",-amount),"blackRhino.transfer.punch");
        target.buffManager.addBuff(new org.flashNight.arki.component.Buff.PodBuff("刀属性.power","add",amount),"blackRhino.transfer.blade");
        target.buffManager.update(0);
        target.转换的冷兵器加成 = amount;
        return true;
    }

    public static function endBlackRhinoTransfer(target:Object):Boolean {
        if (!(target.转换的冷兵器加成 > 0)) return false;
        target.buffManager.removeBuff("blackRhino.transfer.punch");
        target.buffManager.removeBuff("blackRhino.transfer.blade");
        target.buffManager.update(0);
        target.转换的冷兵器加成 = 0;
        return true;
    }

    public static function requestPersistentRefresh(target:Object,reason:String):Object {
        if (target.__playerStatInitializing === true) { target.__playerStatNeedsNumericTail=true; return {status:"pending",reason:"initializing"}; }
        if(target._name!==_root.控制目标) {
            var hp:Number=Number(target.hp);var maxHp:Number=Number(target.hp满血值);var mp:Number=Number(target.mp);
            var record:Object=buildPersistentSnapshot(target);applyPersistentSnapshot(target,record);
            target.hp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(hp,maxHp,Number(target.hp满血值));
            target.mp=org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(mp,Number(target.mp满血值));
            refreshKnownModeCaches(target,record);return {status:"applied",reason:""};
        }
        var coordinator = org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
        coordinator.invalidate(1,reason,coordinator.contextToken());
        return coordinator.flush(reason);
    }

    public static function applyMusicModeCommand(ref:Object):Void {
        requestPersistentRefresh(ref.自机,"morph");
    }

    /** 只读明确的几个装备 ref，既不遍历任务也不调用 mode 迁移命令。 */
    private static function projectKnownModeInputs(owner:Object,c:Object,input:Object):Void {
        c.__modeCaches=[]; c.__modeWeaponWrites={};
        var kinds:Array=["guitar","vocal","keyboard"];
        var fields:Array=["__statGuitarRef","__statVocalRef","__statKeyboardRef"];
        for(var i:Number=0;i<kinds.length;i++) {
            var ref:Object=owner[fields[i]];
            if(ref==undefined) continue;
            if(ref.属性投影身体!==owner.__playerStatBody || ref.自机!==owner) throw new Error("stat_mode_ref_stale");
            var slot:String=kinds[i]=="guitar" ? "长枪" : "刀";
            var projection:Object=calculateMusicMode(kinds[i],ref,input.slots[slot].data,c.装备枪械威力加成,c.装备刀锋利度加成);
            c[weaponKeys[slot]]=projection.weapon;
            c.__modeWeaponWrites[slot]=projection.weapon;
            if(kinds[i]=="guitar" && ref.是否刀枪复用) c.刀属性={power:projection.baseProps.power*ref.刀威力系数};
            c.__modeCaches.push({ref:ref,kind:kinds[i],values:projection.cache});
        }
        var balance:Object=owner.__statBalanceRef;
        if(balance!=undefined) {
            if(balance.属性投影身体!==owner.__playerStatBody) throw new Error("stat_mode_ref_stale");
            c.__modeCaches.push({ref:balance,kind:"balance",values:{默认形态基础伤害:c.刀属性.power}});
        }
        if(typeof owner.__pileBunkerM7.projectPersistentBlade=="function") owner.__pileBunkerM7.projectPersistentBlade(c);
        if(input.slots.手枪.item.name=="dominator") {
            var mode:String=String(owner["武器类型:dominator"] || "麻醉模式");
            var gunsmith:Object=c.被动技能.枪械师;
            var gunsmithBonus:Number=gunsmith.启用 ? Number(gunsmith.等级)*5 : 0;
            var dominator:Object=calculateDominatorMode(input.slots.手枪.data,mode,c.装备枪械威力加成,gunsmithBonus);
            c.手枪属性=dominator;c.__modeWeaponWrites.手枪=dominator;
            c.手枪伤害类型=mode=="分解模式" ? "真伤" : "物理";
        }
        c.根据模式重新读取武器加成(c.攻击模式);
    }

    public static function calculateMusicMode(kind:String,ref:Object,raw:Object,gunBonus:Number,bladeBonus:Number):Object {
        var output:Object=copyNumericInput(raw);
        var cache:Object={};var baseProps:Object=copyNumericInput(raw);
        var mode:String=String(ref.weaponValue.weaponMode || ref.weaponMode);
        if(kind=="guitar") {
            baseProps.power=Number(raw.power)+gunBonus;cache.baseGunProps=baseProps;
            output.power=Number(raw.power)*(mode=="机枪" ? ref.机枪威力系数 : 1)+gunBonus;
            if(mode=="机枪") {
                output.impact=ref.机枪击倒力;output.bullethit=ref.机枪命中效果;output.muzzle=ref.机枪枪口焰;
                output.sound=ref.机枪音效;output.bullet=ref.机枪子弹;
                output.velocity=raw.velocity*ref.机枪速度倍率;output.interval=Math.floor(raw.interval/ref.机枪射击间隔除数);
                output.diffusion=Math.floor(raw.diffusion/ref.机枪散射度除数);output.split=raw.split*ref.机枪霰弹值倍率;
                output.capacity=raw.capacity*ref.机枪弹容倍率;
            }
        } else {
            var baseDamage:Number=Number(raw.power)+bladeBonus;cache.baseDamage=baseDamage;
            output.power=baseDamage;
            if(kind=="vocal" && mode=="话筒支架") output.power=baseDamage*0.8;
            if(kind=="keyboard" && mode=="键盘") output.power=baseDamage*ref.keyboardDamageMultiplier;
        }
        validateNumericInput(output);
        return {weapon:output,cache:cache,baseProps:baseProps};
    }

    public static function calculateDominatorMode(raw:Object,mode:String,gunBonus:Number,gunsmithBonus:Number):Object {
        var output:Object=copyNumericInput(raw);
        var coefficient:Number=mode=="分解模式" ? 28 : (mode=="击杀模式" ? 7 : 1);
        var extra:Number=mode=="分解模式" ? 10 : (mode=="击杀模式" ? 7 : 0);
        output.power=raw.power*coefficient+gunBonus+gunsmithBonus*extra;
        if(mode!="麻醉模式") {
            output.bullet=mode=="分解模式" ? "电浆球" : "普通微波子弹";
            output.impact=mode=="分解模式" ? 0.5 : 15;
            output.bullethit="火花";output.muzzle="枪火";output.sound="dominator枪声2.wav";
            output.velocity=raw.velocity*1.2;output.interval=mode=="分解模式" ? Math.floor(raw.interval*1.5) : raw.interval;
            output.diffusion=mode=="分解模式" ? 0 : Math.floor(raw.diffusion/1.5);
            output.capacity=Math.floor(raw.capacity*(mode=="分解模式" ? 0.06 : 0.6));
        }
        validateNumericInput(output);return output;
    }

    public static function refreshKnownModeCaches(target:Object,record:Object):Void {
        var caches:Array=record.unbuffed.__modeCaches;
        for(var i:Number=0;i<caches.length;i++) {
            var entry:Object=caches[i];var ref:Object=entry.ref;
            if(ref.属性投影身体!==target.__playerStatBody) throw new Error("stat_mode_ref_stale");
            for(var key:String in entry.values) ref[key]=entry.values[key];
            var param:Object=ref.初始化参数;
            var mpMax:Number=Number(target.mp满血值);
            var ratio:Number=param.mpCostRatio || 1;
            if(entry.kind=="guitar") {
                ref.吉他震地耗蓝量=Math.floor(mpMax/100*(param.quakeMpCostRatio || 5));
                ref.黄色音符耗蓝量=ref.灯光增幅耗蓝量=Math.floor(mpMax/100*(param.noteMpCostRatio || 1));
            } else if(entry.kind=="vocal") {
                ref.红色音符耗蓝量=ref.主唱光刃耗蓝量=Math.floor(mpMax/100*ratio);
                ref.猩红增幅耗蓝量=Math.floor(mpMax/100*ratio/2);
            } else if(entry.kind=="keyboard") {
                ref.蓝色音符耗蓝量=ref.镰刀光斩耗蓝量=ref.镰刀风车斩耗蓝量=Math.floor(mpMax/100*ratio);
                ref.天蓝增幅耗蓝量=Math.floor(mpMax/100*ratio/(param.cyanBoostMpCostDivisor || 2));
                ref.追踪充能耗蓝量=Math.floor(mpMax/100*(param.trackingMpCostRatio || 5));
            }
        }
    }

    /** 不改 live，也不读取 live final；完整算完后由调用方校验身份再提交。 */
    public static function buildPersistentSnapshot(target:Object,passiveInput:Object):Object {
        var input:Object = readNumericSources(target);
        if (input == null) throw new Error("stat_source_missing_or_stale");
        var c:Object = {};
        for (var i:Number=0; i<persistentInputKeys.length; i++) c[persistentInputKeys[i]] = target[persistentInputKeys[i]];
        if (!isFinite(Number(c.hp基本满血值)) || !isFinite(Number(c.mp基本满血值))) throw new Error("stat_base_missing");
        c.label = target.label;
        c.被动技能=passiveInput==undefined ? target.被动技能 : passiveInput;
        c.area = {_height:target.area._height};
        c.装备投影基础魔法抗性 = target.装备投影基础魔法抗性;
        c.根据模式重新读取武器加成 = target.根据模式重新读取武器加成;
        for (var slot:String in equipmentKeys) {
            var source:Object=input.slots[slot];
            var sourceData:Object=source.data;
            if(source.forms!=undefined) {
                var longMode:Boolean=source.item.value.长柄形态;
                if(source.item.value.长柄形态==undefined) longMode=source.item.name=="烬灭裁决";
                sourceData=source.forms[longMode ? "烬灭裁决" : "烬灭裁决双刀"];
            }
            var data:Object = copyNumericInput(sourceData);
            validateNumericInput(data);
            c[equipmentKeys[slot]] = data == null ? null : {data:data};
            if (weaponKeys[slot]) c[weaponKeys[slot]] = copyNumericInput(data);
        }
        computeEquipmentProperties(c);
        var loner:Object = lonerContribution({被动技能:c.被动技能});
        c.hp满血值 += loner.hp; c.mp满血值 += loner.mp;
        c.伤害加成 += loner.damage; c.防御力 += loner.defense;
        // 合法负 HP 装备可能耗尽常驻上限；先合计基础、装备、健身、经脉和被动再保底。
        // 不改原装备加层，不结算当前 HP，也不把 NaN/Infinity 伪装成合法输出。
        if (isFinite(Number(c.hp满血值)) && c.hp满血值 < 1) c.hp满血值 = 1;
        projectKnownModeInputs(target,c,input);
        SetEffectController.projectStaticResistance(target,c);
        var legacy:Object = null;
        var gunBonus;
        if(passiveInput!=undefined) {
            var gunsmith:Object=passiveInput.枪械师;
            gunBonus=gunsmith.启用 ? Number(gunsmith.等级)*5 : 0;
            if(!isFinite(gunBonus)) throw new Error("stat_skill_invalid:gunsmith");
        }
        if (typeof target.buff.buildPersistentRebase == "function") legacy = target.buff.buildPersistentRebase(c,gunBonus);
        var record:Object = {unbuffed:c,legacy:legacy,loner:loner,passiveInput:passiveInput,gunBonus:gunBonus};
        validatePersistentSnapshot(record);
        record.expected = previewPersistentSnapshot(target,record);
        return record;
    }

    private static function validateNumericInput(data:Object):Void {
        if (data == null) return;
        for (var i:Number=0; i<numericInputKeys.length; i++) {
            var key:String = numericInputKeys[i];
            if (key == "damagetype" || key == "magictype" || key == "criticalhit" || key == "silence"
                    || key == "bullethit" || key == "muzzle" || key == "sound" || key == "bullet") continue;
            if (data[key] != undefined && !isFinite(Number(data[key]))) throw new Error("stat_input_invalid:"+key);
        }
        for (var resistance:String in data.magicdefence) {
            if (!isFinite(Number(data.magicdefence[resistance]))) throw new Error("stat_input_invalid:resistance");
        }
    }

    public static function validatePersistentSnapshot(record:Object):Void {
        var c:Object = record.unbuffed;
        for (var i:Number=0; i<persistentNumberKeys.length; i++) {
            var key:String = persistentNumberKeys[i];
            if (!isFinite(Number(c[key]))) throw new Error("stat_output_invalid:"+key);
        }
        if (!(c.hp满血值 > 0) || c.mp满血值 < 0) throw new Error("stat_output_invalid:resources");
        for (var resistance:String in c.魔法抗性) if (!isFinite(Number(c.魔法抗性[resistance]))) throw new Error("stat_output_invalid:resistance");
        for (var slot:String in weaponKeys) {
            var power:Object = c[weaponKeys[slot]].power;
            if (power != undefined && !isFinite(Number(power))) throw new Error("stat_output_invalid:power");
        }
        if (record.legacy != null) {
            for (var name:String in record.legacy.values) {
                var value = record.legacy.values[name];
                if (name == "魔法抗性") {
                    for (resistance in value) if (!isFinite(Number(value[resistance]))) throw new Error("stat_legacy_invalid:resistance");
                } else if (!isFinite(Number(value))) throw new Error("stat_legacy_invalid:"+name);
            }
            if (!(record.legacy.values.hp满血值 > 0) || record.legacy.values.mp满血值 < 0) throw new Error("stat_legacy_invalid:resources");
        }
    }

    private static function setPersistentBase(target:Object, key:String, value:Number):Void {
        if (key == "hp满血值" && target.__crumbleCeilingLoss > 0
                && !(typeof target.buffManager.hasCrumbleCeilingBinding == "function" && target.buffManager.hasCrumbleCeilingBinding())) {
            value = Math.max(1,value-target.__crumbleCeilingLoss);
        }
        if (typeof target.buffManager.setBaseValue == "function") target.buffManager.setBaseValue(key,value);
        else {
            var dot:Number = key.indexOf(".");
            if (dot < 0) target[key] = value;
            else target[key.substr(0,dot)][key.substr(dot+1)] = value;
        }
    }

    /** 使用现有 PodBuff/Calculator，只预览数值，不触发 update 或属性回调。 */
    private static function previewPersistentBase(target:Object, key:String, value:Number):Number {
        if (typeof target.buffManager.getPropertyContainer != "function") return value;
        var container:Object = target.buffManager.getPropertyContainer(key);
        if (container == null) return value;
        var calculator = new org.flashNight.arki.component.Buff.BuffCalculator();
        var buffs:Array = container.getBuffs();
        for (var i:Number=buffs.length-1; i>=0; i--) {
            var buff:Object = buffs[i];
            if (buff && buff.isActive()) calculator.addModification(buff.getCalculationType(),buff.getValue());
        }
        return calculator.calculate(value);
    }

    private static function previewPersistentSnapshot(target:Object, record:Object):Object {
        var expected:Object = {};
        var c:Object = record.unbuffed;
        var legacy:Object = record.legacy == null ? null : record.legacy.values;
        for (var i:Number=0; i<persistentNumberKeys.length; i++) {
            var key:String = persistentNumberKeys[i];
            var value:Number = Number(legacy != null && legacy[key] != undefined ? legacy[key] : c[key]);
            expected[key] = previewPersistentBase(target,key,value);
        }
        var resistances:Object = legacy != null ? legacy.魔法抗性 : c.魔法抗性;
        for (key in resistances) expected["魔法抗性."+key] = previewPersistentBase(target,"魔法抗性."+key,Number(resistances[key]));
        var oldPowerKeys:Object = {长枪:"长枪威力",手枪:"手枪威力",手枪2:"手枪2威力",刀:"刀锋利度"};
        for (var slot:String in weaponKeys) {
            if (c[weaponKeys[slot]].power == undefined) continue;
            value = Number(legacy != null && legacy[oldPowerKeys[slot]] != undefined ? legacy[oldPowerKeys[slot]] : c[weaponKeys[slot]].power);
            key = weaponKeys[slot]+".power"; expected[key] = previewPersistentBase(target,key,value);
        }
        if (target.__crumbleCeilingLoss > 0) expected.hp满血值 = Math.max(1,expected.hp满血值-target.__crumbleCeilingLoss);
        var huofengFactor:Number=Number(target.__huofengHpContract.factor);
        if (huofengFactor==0.7 || huofengFactor==0.5) expected.hp满血值=Math.max(1,Math.floor(expected.hp满血值*huofengFactor));
        for (key in expected) if (!isFinite(Number(expected[key]))) throw new Error("stat_final_invalid:"+key);
        if (!(expected.hp满血值 > 0) || expected.mp满血值 < 0) throw new Error("stat_final_invalid:resources");
        return expected;
    }

    /** 资源和派生屏障由 coordinator 承担；本段不发奖、不清任务、不更新 Buff 时间。 */
    public static function applyPersistentSnapshot(target:Object, record:Object):Void {
        validatePersistentSnapshot(record);
        var c:Object = record.unbuffed;
        var legacy:Object = record.legacy == null ? null : record.legacy.values;
        target.__statProjectionCommit = true;
        try {
            if(record.passiveInput!=undefined) {
                target.被动技能=record.passiveInput;
                target.移动射击=record.passiveInput.移动射击.启用 ? true : false;
                if(target.buff!=undefined) {
                    if(record.gunBonus>0) {target.buff.buff加算.手枪威力=record.gunBonus;target.buff.buff加算.手枪2威力=record.gunBonus;}
                    else {delete target.buff.buff加算.手枪威力;delete target.buff.buff加算.手枪2威力;}
                }
            }
            for (var i:Number=0; i<persistentNumberKeys.length; i++) {
                var key:String = persistentNumberKeys[i];
                setPersistentBase(target,key,Number(legacy != null && legacy[key] != undefined ? legacy[key] : c[key]));
                if(projectionFaultForTests!=undefined) projectionFaultForTests("field:"+key,target);
            }
            for (i=0; i<persistentValueKeys.length; i++) target[persistentValueKeys[i]] = c[persistentValueKeys[i]];
            for (var slot:String in weaponPrefixKeys) {
                var prefix:String = weaponPrefixKeys[slot];
                for (i=0; i<weaponValueSuffixes.length; i++) {
                    key = prefix+weaponValueSuffixes[i]; target[key] = c[key];
                }
            }
            var resistance:Object = legacy != null ? legacy.魔法抗性 : c.魔法抗性;
            target.魔法抗性 = {};
            for (key in resistance) target.魔法抗性[key] = resistance[key];
            if (typeof target.buffManager.syncAllPathBindings == "function") target.buffManager.syncAllPathBindings();
            var oldPowerKeys:Object = {长枪:"长枪威力",手枪:"手枪威力",手枪2:"手枪2威力",刀:"刀锋利度"};
            for (slot in weaponKeys) {
                if (c[weaponKeys[slot]].power == undefined) continue;
                var power:Number = Number(legacy != null && legacy[oldPowerKeys[slot]] != undefined ? legacy[oldPowerKeys[slot]] : c[weaponKeys[slot]].power);
                setPersistentBase(target,weaponKeys[slot]+".power",power);
            }
            for(slot in c.__modeWeaponWrites) {
                var fields:Object=c.__modeWeaponWrites[slot];
                for(key in fields) {
                    if(key=="power" || key=="magicdefence") continue;
                    target[weaponKeys[slot]][key]=fields[key];
                }
                if(fields.capacity!=undefined) target[slot+"弹匣容量"]=fields.capacity;
            }
            if (record.legacy != null) target.buff.acceptPersistentRebase(record.legacy);
            // AI 辅助量不参与玩家必需属性的校验、Buff 基底与后验。
            // 仍随每次成功投影更新；坏值由实际 AI 消费端拒绝，不保留旧装备的权重。
            target.佣兵技能概率抑制基数 = Number(c.佣兵技能概率抑制基数);
            target.__persistentStatBase = c;
            target.__lonerContribution = record.loner;
        } finally { target.__statProjectionCommit = false; }
    }

    /** 只刷新现有射击对象的派生字段，保留对象、任务和装填/弹药权威。 */
    public static function refreshPersistentWeaponCaches(target:Object,record:Object):Void {
        if(record.passiveInput!=undefined)
            org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime.reconcileSkillFeatures(target);
        var mode:String=String(target.攻击模式);
        var slots:Array=mode=="双枪" ? ["手枪","手枪2"] : [mode];
        var init:Object=org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
        var statKeys:Array=["子弹威力","命中率","击倒率","伤害类型","魔法伤害属性","毒","吸血","血量上限击溃","暴击","斩杀","移动子弹散射度"];
        var modeKeys:Array=["霰弹值","子弹散射度","站立子弹散射度","声音","发射效果","子弹种类","ammoCost","子弹速度","击中地图效果","Z轴攻击范围","击中后子弹的效果"];
        for(var i:Number=0;i<slots.length;i++) {
            var slot:String=slots[i];
            if(slot!="长枪" && slot!="手枪" && slot!="手枪2") continue;
            var field:String=i==1 ? "子弹属性2" : "子弹属性";
            var current:Object=target.man[field];
            if(current==undefined || target[slot+"属性"].power==undefined) continue;
            var fresh:Object=init.generateBulletProps(target,slot,target[slot+"属性"],{});
            if(!isFinite(Number(fresh.子弹威力)) || !isFinite(Number(fresh.命中率))) throw new Error("stat_weapon_cache_invalid");
            for(var k:Number=0;k<statKeys.length;k++) current[statKeys[k]]=fresh[statKeys[k]];
            if(record.unbuffed.__modeWeaponWrites[slot]!=undefined) {
                for(k=0;k<modeKeys.length;k++) current[modeKeys[k]]=fresh[modeKeys[k]];
            }
            var speedKey:String=mode=="双枪" ? (i==1 ? "副手射击速度" : "主手射击速度") : "射击速度";
            target.man[speedKey]=target[slot+"属性"].interval;
        }
        refreshKnownModeCaches(target,record);
        if(typeof target.shield.refreshStanceResistance=="function") target.shield.refreshStanceResistance();
        LongGunSubWeaponCore.refreshRuntimeStats(target);
    }

    public static function verifyPersistentSnapshot(target:Object,record:Object):Boolean {
        for(var key:String in record.expected) {
            var dot:Number=key.indexOf(".");
            var value:Number=Number(dot<0 ? target[key] : target[key.substr(0,dot)][key.substr(dot+1)]);
            if(!isFinite(value) || Math.abs(value-record.expected[key])>0.000001*Math.max(1,Math.abs(record.expected[key]))) return false;
        }
        return true;
    }



    public static function loadEquipment(target:MovieClip, equipKey:String, defaultLevel:Number):BaseItem{
        var 装备 = target[equipKey];
        if(typeof 装备 === "string"){
            装备 = BaseItem.createFromString(装备);
            if(装备.value.level == 1 && defaultLevel > 1) 装备.value.level = defaultLevel;
        }
        return 装备;
    }

    public static function loadHeroEquipment(target:MovieClip, equipKey:String):BaseItem{
        return _root.物品栏.装备栏.getItem(equipKey);
    }

    public static function getEquipmentDefaultLevel(targetLevel:Number, targetName:String):Number{
        if(targetLevel <= 0) return 1;
        var result = 1;
        if (targetName === "Andy" || targetName === "Blue" || targetName === "Boy" || targetName === "Pig" || targetName === "King") {
            result = 3 + Math.floor((targetLevel - 20) / 5);
        } else if (targetLevel <= 36) {
            result = Math.floor((targetLevel - 16) / 4);
        } else if (targetLevel <= 50) {
            result = 5 + Math.floor((targetLevel - 36) / 8);
        } else {
            result = 7 + Math.floor((targetLevel - 50) / 15);
        }
        if(result <= 0) return 1;
        if(result > 13) return 13;
        return result;
    }

    public static function loadEquipmentData(__target:MovieClip, equipKey:String, loadFunc:Function, defaultLevel:Number){
        var target:MovieClip = __target;
        var equipment:BaseItem = loadFunc(target, equipKey, defaultLevel);
        if(equipment){
            target[equipKey] = equipment; // 将装备对象储存到对应的装备类型键上
            var itemData:Object = equipment.getData(); // 获取计算完毕的装备数据
            target[equipmentKeys[equipKey]] = itemData; // 将装备数据储存到对应的装备数据键上
            recordNumericSource(target,equipKey,equipment,itemData);
            if(weaponKeys[equipKey]){
                // 武器输出保留完整现役字段，但不与 getData 的数字对象共用可写叶子。
                var runtimeData:Object = {};
                for (var runtimeKey:String in itemData.data) runtimeData[runtimeKey] = itemData.data[runtimeKey];
                target[weaponKeys[equipKey]] = runtimeData;
            }
        }else{
            target[equipKey] = null;
            target[equipmentKeys[equipKey]] = null;
            recordNumericSource(target,equipKey,null,null);
            if(weaponKeys[equipKey]){
                target[weaponKeys[equipKey]] = null;
            }
        }
    }


    public static function updateDressupKeys(__target:MovieClip):Void{
        var target:MovieClip = __target;

        // 军牌
        var 称号文本 = target.颈部装备数据.data.title ? target.颈部装备数据.data.title : "";
        if (target._name == _root.控制目标) {
            if(称号文本 === ""){
                称号文本 = HeroUtil.getHeroTitle()
            }
            _root.玩家称号 = 称号文本;
            target.发型 = _root.发型;
            target.脸型 = _root.脸型;
        }
        target.称号 = 称号文本;

        // 头部
        target.面具 = target.头部装备数据 ? target.头部装备数据.data.dressup : null;
        if (target.头部装备数据.helmet) {
            target.发型 = "";
        }

        var gender = target.性别;

        // 上装
        var 上装装备装扮 = target.上装装备数据.data.dressup;
        if(上装装备装扮){
            target.身体 = gender + 上装装备装扮 + "身体";
            target.上臂 = gender + 上装装备装扮 + "上臂";
            target.左下臂 = gender + 上装装备装扮 + "左下臂";
            target.右下臂 = gender + 上装装备装扮 + "右下臂";
        }else{
            target.身体 = null;
            target.上臂 = null;
            target.左下臂 = null;
            target.右下臂 = null;
        }
        
        // 手部
        var 手部装备装扮 = target.手部装备数据.data.dressup;
        if(手部装备装扮){
            target.左手 = 手部装备装扮 + "左手";
            target.右手 = 手部装备装扮 + "右手";
        }else{
            target.左手 = null;
            target.右手 = null;
        }

        // 下装
        var 下装装备装扮 = target.下装装备数据.data.dressup;
        if(下装装备装扮){
            target.屁股 = gender + 下装装备装扮 + "屁股";
            target.左大腿 = gender + 下装装备装扮 + "左大腿";
            target.右大腿 = gender + 下装装备装扮 + "右大腿";
            target.小腿 = gender + 下装装备装扮 + "小腿";
        }else{
            target.屁股 = null;
            target.左大腿 = null;
            target.右大腿 = null;
            target.小腿 = null;
        }
        
        // 脚部
        target.脚 = target.脚部装备数据 ? target.脚部装备数据.data.dressup : null;
        
        // 武器
        target.刀_装扮 = target.刀属性 ? target.刀属性.dressup : null;
        target.刀_刀口数 = target.刀属性 ? Number(target.刀属性.bladeCount) : 0; // 用于刀口位置生成子弹的路径选择优化
        target.刀1_装扮 = target.刀属性 ? target.刀属性.dressup1 ? target.刀属性.dressup1 : target.刀属性.dressup : null;
        target.刀2_装扮 = target.刀属性 ? target.刀属性.dressup2 : null;
        target.刀3_装扮 = target.刀属性 ? target.刀属性.dressup3 : null;
        target.长枪_装扮 = target.长枪属性 ? target.长枪属性.dressup : null;
        target.手枪_装扮 = target.手枪属性 ? target.手枪属性.dressup : null;
        target.手枪2_装扮 = target.手枪2属性 ? target.手枪2属性.dressup : null;
        target.手雷_装扮 = target.手雷属性 ? target.手雷属性.dressup : null;
    }


    /**
     * 装备投影需要一个稳定的未装备基底。标准主角模板会显式提供 hp/mp基本满血值，
     * 但普通敌人模板只提供已经按等级和难度计算完毕的 live 满值。首次遇到这类模板时
     * 捕获 live 满值；再后续刷新始终复用稳定字段，避免把上一轮装备加层或友军倍率叠回基底。
     */
    private static function resolveStableBaseStat(target:Object, baseKey:String,
                                                   liveKey:String, minKey:String,
                                                   maxKey:String):Number {
        var value:Number = Number(target[baseKey]);
        if (isFinite(value)) return value;

        value = Number(target[liveKey]);
        if (!isFinite(value)) {
            var minValue:Number = Number(target[minKey]);
            var maxValue:Number = Number(target[maxKey]);
            if (isFinite(minValue) && isFinite(maxValue)) {
                value = _root.根据等级计算值(minValue, maxValue, target.等级);
            }
        }
        if (!isFinite(value)) value = 0;
        target[baseKey] = value;
        return value;
    }

    /**
     * 敌人模板在进入 DressupInitializer 前已根据兵种 XML 补齐权威抗性。
     * 首次投影做浅值快照，之后每次从该快照重建，既保留机械/装甲等模板语义，
     * 又不让装备 magicdefence 在重复换装时累计。
     */
    private static function resolveTemplateMagicResistance(target:Object):Object {
        // 人形/玩家即使在首次刷新前已有一张 level-derived 抗性表，也不能把它误认成
        // 模板权威并永久冻结；当前权威边界由敌人数据的明确“非生物”标签承担。
        var nonBiological:Object = target.label ? target.label.非生物 : undefined;
        var hasAuthoritativeTemplate:Boolean = nonBiological === true || nonBiological === "true";
        if (!hasAuthoritativeTemplate) {
            delete target.装备投影基础魔法抗性;
            target.装备投影含模板魔法抗性 = false;
            return {};
        }

        var cached:Object = target.装备投影基础魔法抗性;
        if (cached != undefined) return cached;

        cached = {};
        var source:Object = target.魔法抗性;
        var hasTemplateValue:Boolean = false;
        if (source) {
            for (var key:String in source) {
                var value:Number = Number(source[key]);
                if (isFinite(value)) {
                    cached[key] = value;
                    hasTemplateValue = true;
                }
            }
        }
        target.装备投影基础魔法抗性 = cached;
        target.装备投影含模板魔法抗性 = hasTemplateValue;
        return cached;
    }


    /** 兼容旧冷路径调用名；完整装备初始化只从 initialize 进入私有子阶段。 */
    public static function updateProperties(target:Object):Object {
        return requestPersistentRefresh(target,"recovery");
    }

    private static function initializeEquipmentProperties(__target:MovieClip):Void {
        var target:MovieClip = __target;
        computeEquipmentProperties(target);
        target.__lonerContribution = {hp:0,mp:0,damage:0,defense:0};
        if(target.长枪属性){
            target.长枪弹匣容量 = target.长枪属性.capacity;
            org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime.ensure(target, "长枪", true);
        }
        if(target.手枪属性){
            target.手枪弹匣容量 = target.手枪属性.capacity;
            org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime.ensure(target, "手枪", true);
        }
        if(target.手枪2属性){
            target.手枪2弹匣容量 = target.手枪2属性.capacity;
            org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime.ensure(target, "手枪2", true);
        }

        org.flashNight.arki.unit.PlayerStatRefreshCoordinator.validateSpawnResourceSeed(target);
        // 新单位尚未获得 current HP 时，装备小计可能在最终被动投影前低于零。
        // 只约束首次资源种子，不改原始装备减益，也不修复已有负 HP/NaN 种子。
        // checkSeed 已先验证已有资源；最终上限仍由 buildPersistentSnapshot 汇总后确定。
        if(isNaN(target.hp)) target.hp = isFinite(Number(target.hp满血值))
            ? Math.max(1,Number(target.hp满血值)) : target.hp满血值;
        if(isNaN(target.mp)) target.mp = target.mp满血值;

        // updateProperties 会整体替换魔法抗性及武器属性对象；先让仍在生效的路径 Buff
        // 重绑到新对象，再刷新所有读取这些属性的下游派生值。
        if (target.buffManager && typeof target.buffManager.syncAllPathBindings == "function") {
            target.buffManager.syncAllPathBindings();
        }

        // 装备数值更新后，通知护盾系统刷新立场抗性派生字段
        // 因为魔法抗性表在本函数中被重建，需要触发护盾系统重新计算立场抗性
        if (target.shield && target.shield.refreshStanceResistance) {
            target.shield.refreshStanceResistance();
        }

        LongGunSubWeaponCore.refreshRuntimeStats(target);

        // AI DPS 估算缓存失效（装备变化 → 武器威力/弹匣容量/伤害类型可能全变）
        org.flashNight.arki.unit.PlayerInfoProvider.invalidateDpsCache(target);
    }

    private static function computeEquipmentProperties(__target:Object):Void{
        var target:Object = __target;

        resolveStableBaseStat(target, "hp基本满血值", "hp满血值", "hp_min", "hp_max");
        resolveStableBaseStat(target, "mp基本满血值", "mp满血值", "mp_min", "mp_max");

        target.hp满血值装备加层 = 0;
        target.mp满血值装备加层 = 0;
        target.装备防御力 = 0;
        target.懒闪避 = 0; //equipped.lazymiss

        target.伤害加成 = 0; //equipped.damage
        // 敌人模板的基本空手攻击力已经包含难度倍率；主角模板没有该字段时仍走原等级公式。
        var 基础空手攻击力:Number = Number(target.基本空手攻击力);
        target.空手攻击力 = isFinite(基础空手攻击力)
            ? 基础空手攻击力
            : _root.根据等级计算值(target.空手攻击力_min, target.空手攻击力_max, target.等级); //equipped.punch
        target.内力 = 65 + Math.floor(target.等级 * 0.56); //equipped.force
        target.装备刀锋利度加成 = 0; //equipped.knifepower
        target.装备枪械威力加成 = 0; //equipped.gunpower

        target.毒 = 0; //equipped.poison
        target.吸血 = 0; //equipped.vampirism
        target.击溃 = 0; //equipped.rout
        target.伤害类型 = "物理"; //equipped.damagetype
        target.魔法伤害属性 = undefined; //equipped.magictype
        var 模板魔法抗性:Object = resolveTemplateMagicResistance(target);
        var 抗性基础 = 10 + target.等级 * 0.1;
        target.魔法抗性 = {全属性: 0, 基础: 抗性基础, 电: 抗性基础, 热: 抗性基础, 冷: 抗性基础, 波: 抗性基础, 蚀: 抗性基础, 毒: 抗性基础, 冲: Math.min(20 + target.等级 * 0.5 , 60)}; //equipped.magicdefence
        if (!target.装备投影含模板魔法抗性) target.魔法抗性.人类 = target.等级;
        for (var 模板抗性键:String in 模板魔法抗性) {
            target.魔法抗性[模板抗性键] = Number(模板魔法抗性[模板抗性键]);
        }

        var areaHeight:Number = target.area._height * target._yscale;
        areaHeight = !isNaN(areaHeight) ? areaHeight : 136;
        var threshold:Number = 19000;

        if (areaHeight >= threshold * 2) {
            target.魔法抗性.巨体 = 0;
        } else if(areaHeight >= threshold) {
            target.魔法抗性.巨体 = 50 * (1 - (areaHeight - threshold) / threshold);
        }

        // _root.发布消息(target.area._height, target._yscale, areaHeight, target.魔法抗性.巨体)
        
        target.基础毒 = 0;
        target.基础吸血 = 0;
        target.基础击溃 = 0;
        target.基础斩杀 = 0;
        target.基础伤害类型 = "物理";
        target.基础魔法伤害属性 = undefined;
        target.基础命中加成 = 0;
        target.佣兵技能概率抑制基数 = 0;

        target.命中加成 = 0;
        target.韧性加成 = target.体重 - 50; //equipped.toughness
        target.闪避加成 = 0; //equipped.evasion

        // 刷新装备数值核心函数
        for(var key in equipmentKeys){
            updateProperty(target, key, target[equipmentKeys[key]].data);
        }
        //全属性抗性效果在遍历后再生效
        if (target.魔法抗性.全属性 > 0) {
            for (var i = 0; i < _root.敌人函数.魔法伤害种类.length; i++) {
                var type = _root.敌人函数.魔法伤害种类[i];
                if (type != "全属性" && target.魔法抗性[type]) {
                    target.魔法抗性[type] += target.魔法抗性.全属性;
                }
            }
        }

        target.根据模式重新读取武器加成(target.攻击模式);

        target.hp满血值 = target.hp基本满血值 + target.hp满血值装备加层;
        target.mp满血值 = target.mp基本满血值 + target.mp满血值装备加层;

        // 佣兵系数属于装备投影的一部分，必须在每次全量重建时从基础值一次性计算。
        // 放在调用侧追加会导致首刷与换装结果分叉（历史上 HP×3 丢失而 MP/10 重复补丁）。
        if (target.是否为敌人 == false && _root.控制目标 != target._name) {
            target.hp满血值 *= 3;
            target.mp满血值 /= 10;
        }
        
        target.防御力 = target.基本防御力 + target.装备防御力;

        target.命中率 = Math.max(target.基础命中率 * (1 + target.命中加成 / 100), DodgeHandler.HIT_RATE_LIMIT);
        target.韧性系数 = target.基础韧性系数 * (1 + target.韧性加成 / 100);

        target.躲闪率 = DodgeHandler.applyDodgeBonus(target.基础躲闪率, target.闪避加成);
        if (target.懒闪避 > 0.95) {
            target.懒闪避 = 0.95;
        }

        if (target.装备刀锋利度加成 && target.刀属性.power) {
            target.刀属性.power += target.装备刀锋利度加成;
        }
        if (target.装备枪械威力加成) {
            if (target.长枪属性.power) {
                target.长枪属性.power += target.装备枪械威力加成;
            }
            if (target.手枪属性.power) {
                target.手枪属性.power += target.装备枪械威力加成;
            }
            if (target.手枪2属性.power) {
                target.手枪2属性.power += target.装备枪械威力加成;
            }
        }
        // 健身房与经脉的常驻加成
        if (_root.控制目标 === target._name) {
            // HP/MP 上限与防御各让出一半练级空间给经脉穴位：健身房上限减半、穴位补上另一半，
            // 两边相加仍等于旧版练满的总收益。经脉那几项是 MeridianPanelService 安装的 getter，
            // 每次读取按当前配置与点亮集重算，改 meridians_config.json 后即以新值生效；
            // 服务未安装（属性缺失）时按 0 计，避免把整条属性算成 NaN。
            target.hp满血值 += readGlobalBonus(_root.全局健身HP加成) + readGlobalBonus(_root.经脉HP加成);
            target.mp满血值 += readGlobalBonus(_root.全局健身MP加成) + readGlobalBonus(_root.经脉MP加成);
            target.空手攻击力 += readGlobalBonus(_root.全局健身空攻加成);
            target.防御力 += readGlobalBonus(_root.全局健身防御加成) + readGlobalBonus(_root.经脉防御加成);
            // 内力只发一份：健身旧档加成与经脉加成取较大者，不叠加。
            // 健身房已移除内力训练项，练过内力的存档改走经脉时先补回原值——
            // 点亮累加超过旧值之前内力不增长，之后只补差值，避免同一份收益重复发放。
            var 健身内力:Number = readGlobalBonus(_root.全局健身内力加成);
            var 经脉内力:Number = readGlobalBonus(_root.经脉内力加成);
            target.内力 += 健身内力 > 经脉内力 ? 健身内力 : 经脉内力;
        }

    }

    /** 常驻全局加成的读数：属性缺失（对应服务未安装）或 NaN 一律按 0，避免把单位属性算成 NaN。 */
    private static function readGlobalBonus(value:Object):Number {
        var result:Number = Number(value);
        return isFinite(result) ? result : 0;
    }

    /**
     * 新 MovieClip 在最终属性投影后的资源结算。
     *
     * 敌人模板先按等级写 current HP，宠物进阶/Dressup 随后才重建最大值；调用方必须
     * 位于这两段之后。settlement 是随 initObject 进入单位的一次性计划：spawn 满资源，
     * preserve 保留重建前绝对值，upgrade 仅把 HP 回满。若最终投影没有 MP 字段，本入口
     * 不会凭空创建；hasDressup 人形范围既有的 0/0 MP 投影则继续保持合法 0/0。
     */
    public static function settleSpawnResources(target:Object, settlement:Object):Void {
        if (!target) return;
        var mode:String = settlement && settlement.mode != undefined
            ? String(settlement.mode) : "spawn";
        var maxHp:Number = Number(target.hp满血值);
        if (isFinite(maxHp) && maxHp > 0) {
            if (mode == "preserve") {
                target.hp = org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(
                    Number(settlement.currentHp), Number(settlement.previousMaxHp), maxHp);
            } else {
                target.hp = maxHp;
            }
        }

        // 非人形敌人模板通常没有通用 MP；只有最终 max 字段真实存在且有限时才结算。
        // 本入口不制造缺失字段；hasDressup 先前已投影出的 0/0 仍按既有合同保留。
        if (target.mp满血值 != undefined) {
            var maxMp:Number = Number(target.mp满血值);
            if (isFinite(maxMp) && maxMp >= 0) {
                if (mode == "preserve" || mode == "upgrade") {
                    target.mp = org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(
                        Number(settlement.currentMp), maxMp);
                } else {
                    target.mp = maxMp;
                }
            }
        }
    }

    private static function updateProperty(__target:Object, key:String, __data:Object){
        var target:Object = __target;
        var data:Object = __data;
        if(!data){
            removePropertyFunc[key](target);
            return;
        }

        if (data.hp) target.hp满血值装备加层 += data.hp;
        if (data.mp) target.mp满血值装备加层 += data.mp;
        if (data.defence) target.装备防御力 += data.defence;
        if (data.damage) target.伤害加成 += data.damage;
        if (data.force) target.内力 += data.force;
        if (data.knifepower) target.装备刀锋利度加成 += data.knifepower;
        if (data.gunpower) target.装备枪械威力加成 += data.gunpower;
        if (data.punch) {
            var 空手加成 = data.punch;
            target.空手攻击力 += 空手加成;
            // 指骨撑架等合法负加成仍扣攻击力；AI 抑制权重只累计正向拳力。
            if (空手加成 > 0) target.佣兵技能概率抑制基数 += Math.sqrt(空手加成);
        }
        if (data.toughness) target.韧性加成 += data.toughness;
        if (data.evasion) target.闪避加成 += data.evasion;
        if (data.lazymiss) target.懒闪避 += data.lazymiss / 100;

        //
        var prefix = weaponPrefixKeys[key];
        if(prefix){
            target[prefix + "伤害类型"] = data.damagetype ? data.damagetype : "物理";
            target[prefix + "魔法伤害属性"] = data.magictype ? data.magictype : null;
            //
            target[prefix + "毒"] = data.poison ? data.poison : 0;
            target[prefix + "吸血"] = data.vampirism ? data.vampirism : 0;
            target[prefix + "击溃"] = data.rout ? data.rout : 0;
            target[prefix + "命中加成"] = data.accuracy ? data.accuracy : 0;
            //target[prefix + "暴击"] = data.criticalhit ? data.criticalhit : null;
            var temp_criticalhit = data.criticalhit ? data.criticalhit : null;
            if (!isNaN(Number(temp_criticalhit))) {
                target[prefix + "暴击"] = function(当前子弹) {
                    if (_root.成功率(Number(temp_criticalhit))) {
                        return 1.5;
                    }
                    return 1;
                };
            } else if (temp_criticalhit == "满血暴击") {
                target[prefix + "暴击"] = function(当前子弹) {
                    if (当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值) {
                        return 1.5;
                    }
                    return 1;
                };
            }
            target[prefix + "斩杀"] = data.slay ? data.slay : 0;
            // 处理消音属性
            target[prefix + "消音"] = data.silence ? data.silence : null;
        }else{
            if(data.poison) target.基础毒 += data.poison;
            if(data.vampirism) target.基础吸血 += data.vampirism;
            if(data.rout) target.基础击溃 += data.rout;
            if(data.slay) target.基础斩杀 += data.slay;
            if(data.accuracy) target.基础命中加成 += data.accuracy;
        }

        if (data.magicdefence) {
            for (var mdKey in data.magicdefence) {
                if (!isNaN(target.魔法抗性[mdKey]) || target.魔法抗性[mdKey] === 0) {
                    target.魔法抗性[mdKey] += Number(data.magicdefence[mdKey]);
                } else {
                    target.魔法抗性[mdKey] = 10 + Number(data.magicdefence[mdKey]);
                }
            }
        }
    }

    private static function removePrimaryProperty(target:MovieClip){
        target.长枪伤害类型 = "物理";
        target.长枪魔法伤害属性 = null;
        target.长枪毒 = 0;
        target.长枪吸血 = 0;
        target.长枪击溃 = 0;
        target.长枪命中加成 = 0;
        target.长枪暴击 = null;
        target.长枪斩杀 = 0;
        target.长枪消音 = null;
        target.长枪消音策略 = null;
    }
    private static function removeSecondary1Property(target:MovieClip){
        target.手枪伤害类型 = "物理";
        target.手枪魔法伤害属性 = null;
        target.手枪毒 = 0;
        target.手枪吸血 = 0;
        target.手枪击溃 = 0;
        target.手枪命中加成 = 0;
        target.手枪暴击 = null;
        target.手枪斩杀 = 0;
        target.手枪消音 = null;
        target.手枪消音策略 = null;
    }
    private static function removeSecondary2Property(target:MovieClip){
        target.手枪2伤害类型 = "物理";
        target.手枪2魔法伤害属性 = null;
        target.手枪2毒 = 0;
        target.手枪2吸血 = 0;
        target.手枪2击溃 = 0;
        target.手枪2命中加成 = 0;
        target.手枪2暴击 = null;
        target.手枪2斩杀 = 0;
        target.手枪2消音 = null;
        target.手枪2消音策略 = null;
    }
    private static function removeMeleeProperty(target:MovieClip){
        target.兵器伤害类型 = "物理";
        target.兵器魔法伤害属性 = null;
        target.兵器毒 = 0;
        target.兵器吸血 = 0;
        target.兵器击溃 = 0;
        target.兵器命中加成 = 0;
        target.兵器暴击 = null;
        target.兵器斩杀 = 0;
    }
    private static function removeHandProperty(target:MovieClip){
        target.空手伤害类型 = "物理";
        target.空手魔法伤害属性 = null;
        target.空手毒 = 0;
        target.空手吸血 = 0;
        target.空手击溃 = 0;
        target.空手命中加成 = 0;
        target.空手暴击 = null;
        target.空手斩杀 = 0;
    }
    private static function removeGrenadeProperty(target:MovieClip){
        target.手雷伤害类型 = "物理";
        target.手雷魔法伤害属性 = null;
        target.手雷毒 = 0;
        target.手雷吸血 = 0;
        target.手雷击溃 = 0;
        target.手雷命中加成 = 0;
        target.手雷暴击 = null;
        target.手雷斩杀 = 0;
    }



    public static function updateWeightAndSpeed(__target:MovieClip):Void{
        var target:MovieClip = __target;

        target.重量 = 0; //weight
        for(var key in equipmentKeys){
            var weight = target[equipmentKeys[key]].data.weight;
            if(!isNaN(weight)) target.重量 += weight;
        }
        var 速度基数:Number = _root.根据等级计算值(target.速度_min, target.速度_max, target.等级) / 10;
        var 速度系数:Number = UnitUtil.getWeightSpeedRatio(target.重量, target.等级);

        target.行走X速度 = 速度基数 * 速度系数;
        target.起跳速度 = -10 * 速度系数;

        // 跳跃状态初始值（这些是状态缓存，不参与getter派生）
        target.跳跃中移动速度 = target.行走X速度;
        target.跳跃中上下方向 = "无";
        target.跳跃中左右方向 = "无";

        // 速度派生getter安装（主角模板的第二次尝试）：
        // 此时行走X速度已设置，可以安装派生getter
        // 对于敌人模板，StaticInitializer中已经安装过getter，这里会直接return
        SpeedDeriveInitializer.initialize(target);
    }


    /** 运行态借用槽装载完成后，再判断当前模式是否仍有可用装备。 */
    public static function validateAttackMode(target:MovieClip):Void{
        // 判断卸下装备后的转回空手
        var 旧攻击模式 = target.攻击模式;
        if (旧攻击模式 != "空手" && target.状态.indexOf(旧攻击模式) != -1) {
            var 是否卸下装备 = false;
            if (旧攻击模式 == "长枪" && !target.长枪)
                是否卸下装备 = true;
            else if (旧攻击模式 == "手枪" && !target.手枪)
                是否卸下装备 = true;
            else if (旧攻击模式 == "手枪2" && !target.手枪2)
                是否卸下装备 = true;
            else if (旧攻击模式 == "双枪" && (!target.手枪 || !target.手枪2))
                是否卸下装备 = true;
            else if (旧攻击模式 == "兵器" && !target.刀)
                是否卸下装备 = true;
            else if (旧攻击模式 == "手雷" && !target.手雷)
                是否卸下装备 = true;
            //
            if (是否卸下装备) {
                target.状态 = "空手站立";
                target.攻击模式 = "空手";
                target.根据模式重新读取武器加成("空手");
            }
        }

    }

    public static function updateActions(target:MovieClip, deferModeValidation:Boolean):Void{
        if (!deferModeValidation) validateAttackMode(target);
        // 更新装备动作类型
        target.空手动作类型 = target.手部装备数据.actiontype;
        target.兵器动作类型 = target.刀数据.actiontype;
        target.长枪动作类型 = target.长枪数据.actiontype;
        target.手枪动作类型 = target.手枪数据.actiontype;
        target.手枪2动作类型 = target.手枪2数据.actiontype;
        target.手雷动作类型 = target.手雷数据.actiontype;
        // target.手雷动作类型 （未启用）
    }


    public static function updateWeqaponSkills(__target:MovieClip):Void{
        var target:MovieClip = __target;

        target.主动战技 = _root.主角函数.创建主动战技槽位表();
        LongGunSubWeaponCore.clearUnit(target, false);
        loadWeaponSkill(target, "手部装备");
        loadWeaponSkill(target, "刀");
        loadWeaponSkill(target, "长枪");
        loadWeaponSkill(target, "手枪");
        loadWeaponSkill(target, "手枪2");
    }

    private static function loadWeaponSkill(target:MovieClip, equipType:String):Void{
        var data:Object = target[equipType + "数据"];
        var skillType:String = _root.主角函数.获取装备主动战技种类(equipType, data ? data.use : null);
        if (skillType) {
            if (equipType == "长枪" && SubweaponDataUtil.hasSubweapon(data)) {
                if (LongGunSubWeaponCore.configureUnit(target, data)) {
                    if (target.装载副武器控制槽) {
                        target.装载副武器控制槽(target.长枪副武器配置, skillType);
                    } else {
                        target.主动战技[skillType] = LongGunSubWeaponCore.buildControlSlot(target.长枪副武器配置);
                    }
                }
                return;
            }
            target.装载主动战技(data.skill, skillType);
        }
    }

    public static function teardownLifeCycles(target:MovieClip):Void{
        delete target.__statGuitarRef;delete target.__statVocalRef;delete target.__statKeyboardRef;delete target.__statBalanceRef;
        if (!target || !target.生命周期函数列表) {
            RuntimeEquipmentProjection.releaseAliases(target);
            SetEffectController.clearController(target);
            return;
        }
        for (var i:Number = target.生命周期函数列表.length - 1; i >= 0; --i) {
            var 卸载对象:Object = target.生命周期函数列表[i];
            if (卸载对象 && 卸载对象.动作) {
                try {
                    卸载对象.动作(卸载对象.额外参数);
                } catch (lifecycleUnloadError) {
                    // teardown 是资源回收边界：一个装备脚本故障不能阻止其余
                    // 生命周期逆序卸载，也不能让单位重建/移除留下外部订阅。
                    trace("[DressupInitializer] 生命周期函数卸载失败: " + lifecycleUnloadError);
                }
            }
        }
        target.生命周期函数列表.length = 0;
        RuntimeEquipmentProjection.releaseAliases(target);
        SetEffectController.clearController(target);
    }

    public static function updateLifeCycles(__target:MovieClip):Void{
        var target:MovieClip = __target;

        if (!target.生命周期函数列表) {
            target.生命周期函数列表 = [];
        }

        SetEffectController.prepare(target);

        target.装载生命周期函数(target.头部装备数据.lifecycle, "头部装备");
        target.装载生命周期函数(target.上装装备数据.lifecycle, "上装装备");
        target.装载生命周期函数(target.下装装备数据.lifecycle, "下装装备");
        target.装载生命周期函数(target.脚部装备数据.lifecycle, "脚部装备");
        target.装载生命周期函数(target.颈部装备数据.lifecycle, "颈部装备");
        target.装载生命周期函数(target.手部装备数据.lifecycle, "手部装备");
        target.装载生命周期函数(target.刀数据.lifecycle, "刀");
        target.装载生命周期函数(target.长枪数据.lifecycle, "长枪");
        target.装载生命周期函数(target.手枪数据.lifecycle, "手枪");
        target.装载生命周期函数(target.手枪2数据.lifecycle, "手枪2");
        target.装载生命周期函数(target.手雷数据.lifecycle, "手雷");

        target.完成生命周期函数装载();
    }



    public static function initialize(target:MovieClip):Void{
        if(target.hasDressup !== true) return;

        target.__persistentEquipmentInputV1 = {slots:{}};

        var loadFunc:Function = target._name === _root.控制目标 ? loadHeroEquipment : loadEquipment;
        var defaultLevel:Number = getEquipmentDefaultLevel(target.等级, target.名字);
        var loadEquipmentDataFunc:Function = loadEquipmentData;
        // 逐个检查装备并附加装备数据
        for(var key in equipmentKeys){
            loadEquipmentDataFunc(target, key, loadFunc, defaultLevel);
        }

        // 冻结权威装备栏输入；后续 lifecycle 只能通过 RuntimeEquipmentProjection
        // 申请有所有权的运行态空槽借用，不能污染 CharacterBuild 的 canonical 判定。
        RuntimeEquipmentProjection.beginCanonical(target);
        org.flashNight.arki.unit.Action.Huofeng.HuofengRunState.reconcileEquipment(target);

        // 更新装扮数据
        updateDressupKeys(target);

        // 更新人物属性
        initializeEquipmentProperties(target);

        // 更新重量速度
        updateWeightAndSpeed(target);

        // 更新人物动作
        updateActions(target, true);

        // 装载武器战技
        updateWeqaponSkills(target);

        // 装载生命周期函数
        updateLifeCycles(target);

        // 空刀槽可能在生命周期中由复合长枪合法借用；不能在那之前误判卸装。
        validateAttackMode(target);
        if(target._name === _root.控制目标) _root.玩家信息界面.刷新攻击模式(target.攻击模式);
        RuntimeEquipmentProjection.completeCanonical(target);
    }
}
