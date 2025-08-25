﻿import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.component.StatHandler.DodgeHandler;

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



    public static function loadEquipment(target:MovieClip, equipKey:String, defaultLevel:Number):Object{
        var 装备 = target[equipKey];
        if(typeof 装备 === "string"){
            装备 = ItemUtil.createItemByString(装备);
            if(装备.value.level == 1 && defaultLevel > 1) 装备.value.level = defaultLevel;
        }
        return 装备;
    }

    public static function loadHeroEquipment(target:MovieClip, equipKey:String):Object{
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

    public static function loadEquipmentData(target:MovieClip, equipKey:String, loadFunc:Function, defaultLevel:Number){
        var equipment:Object = loadFunc(target, equipKey, defaultLevel);
        if(equipment){
            target[equipKey] = equipment;
            var itemData = ItemUtil.getEquipmentData(equipment); // 获取计算完毕的装备数据
            target[equipmentKeys[equipKey]] = itemData;
            // 将所有武器的data数据另设一个储存键
            if(weaponKeys[equipKey]){
                target[weaponKeys[equipKey]] = itemData.data;
            }
        }else{
            target[equipKey] = null;
            target[equipmentKeys[equipKey]] = null;
            if(weaponKeys[equipKey]){
                target[weaponKeys[equipKey]] = null;
            }
        }
    }


    public static function updateDressupKeys(target:MovieClip):Void{
        // 军牌
        var 称号文本 = target.颈部装备数据.data.title ? target.颈部装备数据.data.title : "菜鸟";
        target.称号 = 称号文本;
        if (target._name == _root.控制目标) {
            _root.玩家称号 = target.称号;
            target.发型 = _root.发型;
            target.脸型 = _root.脸型;
        }

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
        target.长枪_装扮 = target.长枪属性 ? target.长枪属性.dressup : null;
        target.手枪_装扮 = target.手枪属性 ? target.手枪属性.dressup : null;
        target.手枪2_装扮 = target.手枪2属性 ? target.手枪2属性.dressup : null;
        target.手雷_装扮 = target.手雷属性 ? target.手雷属性.dressup : null;
    }


    public static function updateProperties(target:MovieClip):Void{
        target.命中加成 = 0;

        target.hp满血值装备加层 = 0;
        target.mp满血值装备加层 = 0;
        target.装备防御力 = 0;
        target.懒闪避 = 0; //equipped.lazymiss

        target.伤害加成 = 0; //equipped.damage
        target.重量 = 0; //weight
        target.空手攻击力 = _root.根据等级计算值(target.空手攻击力_min, target.空手攻击力_max, target.等级); //equipped.punch
        target.内力 = 65 + Math.floor(target.等级 * 0.56); //equipped.force
        target.装备刀锋利度加成 = 0; //equipped.knifepower
        target.装备枪械威力加成 = 0; //equipped.gunpower

        target.毒 = 0; //equipped.poison
        target.吸血 = 0; //equipped.vampirism
        target.击溃 = 0; //equipped.rout
        target.伤害类型 = undefined; //equipped.damagetype
        target.魔法伤害属性 = undefined; //equipped.magictype
        target.魔法抗性 = {全属性: 0, 基础: 10, 电: 10, 热: 10, 冷: 10, 波: 10, 蚀: 10, 毒: 10, 冲: 30 + target.等级 * 0.5}; //equipped.magicdefence
        target.魔法抗性.人类 = target.等级;
        target.基础毒 = 0;
        target.基础吸血 = 0;
        target.基础击溃 = 0;
        target.基础伤害类型 = undefined;
        target.基础魔法伤害属性 = undefined;
        target.基础命中加成 = 0;
        target.佣兵技能概率抑制基数 = 0;

        var 韧性加成:Number = target.身高 - 105 - 50; //equipped.toughness
        var 闪避加成:Number = 0; //equipped.evasion

        var equipmentDataList:Array = [];
        var data:Object;
        for(var key in equipmentKeys){
            data = target[equipmentKeys[key]].data;
            if(data) equipmentDataList.push(data);
        }

        for (var i=0; i<equipmentDataList.length; i++) {
            data = equipmentDataList[i];

            if (data.hp) {
                target.hp满血值装备加层 += data.hp;
            }
            if (data.mp) {
                target.mp满血值装备加层 += data.mp;
            }
            if (data.defence) {
                target.装备防御力 += data.defence;
            }
            if (data.damage) {
                target.伤害加成 += data.damage;
            }
            if (data.punch) {
                var 空手加成 = data.punch;
                target.空手攻击力 += 空手加成;
                target.佣兵技能概率抑制基数 += Math.sqrt(空手加成);
            }
            if (data.force) {
                target.内力 += data.force;
            }
            if (data.knifepower) {
                target.装备刀锋利度加成 += data.knifepower;
            }
            if (data.gunpower) {
                target.装备枪械威力加成 += data.gunpower;
            }
            if (data.lazymiss) {
                target.懒闪避 += data.lazymiss / 100;
            }

            var prefix = weaponPrefixKeys[key];

            // 
            if(prefix){
                target[prefix + "伤害类型"] = data.damagetype ? data.damagetype : null;
                target[prefix + "魔法伤害属性"] = data.magictype ? data.magictype : null;
                //
                target[prefix + "毒"] = data.poison ? data.poison : 0;
                target[prefix + "吸血"] = data.vampirism ? data.vampirism : 0;
                target[prefix + "击溃"] = data.rout ? data.rout : 0;
                target[prefix + "命中加成"] = data.accuracy ? data.accuracy : 0;
                target[prefix + "暴击"] = data.criticalhit ? data.criticalhit : 0;
                target[prefix + "斩杀"] = data.slay ? data.slay : 0;
            }else{
                if(data.poison) target.基础毒 += data.poison;
                if(data.vampirism) target.基础吸血 += data.vampirism;
                if(data.rout) target.基础击溃 += data.rout;
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
            if (data.toughness) {
                韧性加成 += data.toughness;
            }
            if (data.evasion) {
                闪避加成 += data.evasion;
            }
        }

        target.根据模式重新读取武器加成(target.攻击模式);

        target.hp满血值 = target.hp基本满血值 + target.hp满血值装备加层;
        target.mp满血值 = target.mp基本满血值 + target.mp满血值装备加层;
        
        target.防御力 = target.基本防御力 + target.装备防御力;

        target.命中率 = Math.max(target.基础命中率 * (1 + target.命中加成 / 100), DodgeHandler.HIT_RATE_LIMIT);
        target.韧性系数 = target.韧性系数 * (1 + 韧性加成 / 100);

        var 躲闪能力:Number = 1 / target.躲闪率;
        躲闪能力 = Math.max(target.躲闪率 * (1 + 闪避加成 / 100), DodgeHandler.DODGE_RATE_LIMIT);
        target.躲闪率 = 1 / 躲闪能力;
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
        if(target.长枪属性){
            target.长枪弹匣容量 = target.长枪属性.capacity;
            if(target.长枪.value.shot <= 0) target.长枪.value.shot = 0;
        }
        if(target.手枪属性){
            target.手枪弹匣容量 = target.手枪属性.capacity;
            if(target.手枪.value.shot <= 0) target.手枪.value.shot = 0;
        }
        if(target.手枪2属性){
            target.手枪2弹匣容量 = target.手枪2属性.capacity;
            if(target.手枪2.value.shot <= 0) target.手枪2.value.shot = 0;
        }

        // 健身房加成
        if (_root.控制目标 === target._name) {
            target.hp满血值 += _root.全局健身HP加成;
            target.mp满血值 += _root.全局健身MP加成;
            target.空手攻击力 += _root.全局健身空攻加成;
            target.内力 += _root.全局健身内力加成;
            target.防御力 += _root.全局健身防御加成;
        }

        if(isNaN(target.hp)) target.hp = target.hp满血值;
        if(isNaN(target.mp)) target.mp = target.mp满血值;
    }

    public static function updateWeightAndSpeed(target:MovieClip):Void{
        for(var key in equipmentKeys){
            var weight = target[equipmentKeys[key]].weight;
            if(!isNaN(weight)) target.重量 += weight;
        }
        var 速度基数:Number = _root.根据等级计算值(target.速度_min, target.速度_max, target.等级) / 10;
        var 速度系数:Number = _root.主角函数.重量速度关系(target.重量, target.等级);

        target.行走X速度 = 速度基数 * 速度系数;
        target.跳跃中移动速度 = target.行走X速度;
        target.跳跃中上下方向 = "无";
        target.跳跃中左右方向 = "无";
        target.行走Y速度 = target.行走X速度 / 2;
        target.跑X速度 = target.行走X速度 * 2;
        target.跑Y速度 = target.行走X速度;
        target.起跳速度 = -10 * 速度系数;

        if (target._name != _root.控制目标) {
            target.行走Y速度 = Math.min(target.行走Y速度, 2.5);
            target.跑Y速度 = Math.min(target.跑Y速度, 5);
        }
    }


    public static function updateActions(target:MovieClip):Void{
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
            //
            if (是否卸下装备) {
                target.状态 = "空手站立";
                target.攻击模式 = "空手";
            }
        }

        // 更新装备动作类型
        target.空手动作类型 = target.手部装备数据.actiontype;
        target.兵器动作类型 = target.刀数据.actiontype;
        target.长枪动作类型 = target.长枪数据.actiontype;
        target.手枪动作类型 = target.手枪数据.actiontype;
        target.手枪2动作类型 = target.手枪2数据.actiontype;
        // target.手雷动作类型 （未启用）
    }


    public static function updateWeqaponSkills(target:MovieClip):Void{
        target.主动战技 = {空手: null, 兵器: null, 长枪: null};
        target.装载主动战技(target.手部装备数据.skill, "空手");
        target.装载主动战技(target.刀数据.skill, "兵器");
        target.装载主动战技(target.长枪数据.skill, "长枪");
    }

    public static function updateLifeCycles(target:MovieClip):Void{
        for (var id = target.生命周期函数列表.length; id > 0; --id) {
            var 卸载对象 = target.生命周期函数列表[id];
            卸载对象.动作(卸载对象.额外参数);
        }
        target.生命周期函数列表.length = 0;

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

        var loadFunc = target._name === _root.控制目标 ? loadHeroEquipment : loadEquipment;
        var defaultLevel = getEquipmentDefaultLevel(target.等级, target.名字);
        // 逐个检查装备并附加装备数据
        for(var key in equipmentKeys){
            loadEquipmentData(target, key, loadFunc, defaultLevel);
        }
        // 更新装扮数据
        updateDressupKeys(target);

        // 更新人物属性
        updateProperties(target);
        // 更新重量速度
        updateWeightAndSpeed(target);

        // 更新人物动作
        updateActions(target);

        // 装载武器战技
        updateWeqaponSkills(target);
        // 装载生命周期函数
        updateLifeCycles(target);

        if(target._name === _root.控制目标) _root.玩家信息界面.刷新攻击模式();
    }
}
