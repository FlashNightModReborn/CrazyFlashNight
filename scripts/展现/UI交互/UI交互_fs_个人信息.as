import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.Action.Shoot.*;

_root.人物信息函数 = new Object();

_root.人物信息函数.获得韧性负荷 = function(自机){
	var 韧性上限 = 自机.韧性系数 * 自机.hp / DamageResistanceHandler.defenseDamageRatio(自机.防御力 / 1000);
	return Math.floor(韧性上限 / 自机.躲闪率) + " / " + Math.floor(韧性上限);
};

_root.人物信息函数.获得综合防御力 = function(自机){
	return 自机.防御力;
};

_root.人物信息函数.获得减伤率 = function(自机){
	var 伤害比例 = DamageResistanceHandler.defenseDamageRatio(自机.防御力);
	var 减伤率 = (1 - 伤害比例) * 100;
	return Math.floor(减伤率 * 10) / 10 + "%"; // 保留一位小数
};


_root.人物信息函数.获得最大HP = function(自机){
	return 自机.hp满血值;
};

_root.人物信息函数.获得最大MP = function(自机){
	return 自机.mp满血值;
};

_root.人物信息函数.获得空手攻击力 = function(自机){
	return 自机.空手攻击力;
};

_root.人物信息函数.获得内力 = function(自机){
	return 自机.内力;
};


_root.人物信息函数.获得命中力 = function(自机){
	return Math.floor(自机.命中率 * 10);
};

_root.人物信息函数.获得速度 = function(自机){
	var 速度值 = Math.floor(自机.行走X速度 * 20) / 10;
	var 速度文本 = 速度值 + "m/s";

	// 根据负重情况添加颜色
	var 基准负重 = _root.主角函数.获取基准负重(自机.等级);
	var 当前重量 = 自机.重量;
	var 轻甲阈值 = 基准负重;
	var 重甲阈值 = 基准负重 * 2;

	// 判断负重状态并添加HTML颜色
	if(当前重量 < 轻甲阈值){
		// 低负重增益 - 绿色
		return "<font color='#00FF00'>" + 速度文本 + "</font>";
	} else if(当前重量 > 重甲阈值){
		// 高负重拖累 - 红色
		return "<font color='#FF0000'>" + 速度文本 + "</font>";
	} else {
		// 标准负重 - 白色（默认颜色）
		return 速度文本;
	}
};

_root.人物信息函数.获得被击硬直度 = function(自机){
	return Math.floor(自机.被击硬直度) + "ms";
};

_root.人物信息函数.获得拆挡_坚稳 = function(自机){
	return Math.floor(50 / 自机.躲闪率) + " / " + Math.floor(100 * 自机.韧性系数);
};

// ========== 新增：魔法抗性获取函数 ==========
_root.人物信息函数.获得能量抗性 = function(自机){
	var 基础抗性 = 自机.魔法抗性["基础"];
	if(isNaN(基础抗性)) 基础抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(基础抗性);
};

_root.人物信息函数.获得热抗性 = function(自机){
	var 热抗性 = 自机.魔法抗性["热"];
	if(isNaN(热抗性)) 热抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(热抗性);
};

_root.人物信息函数.获得蚀抗性 = function(自机){
	var 蚀抗性 = 自机.魔法抗性["蚀"];
	if(isNaN(蚀抗性)) 蚀抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(蚀抗性);
};

_root.人物信息函数.获得毒抗性 = function(自机){
	var 毒抗性 = 自机.魔法抗性["毒"];
	if(isNaN(毒抗性)) 毒抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(毒抗性);
};

_root.人物信息函数.获得冷抗性 = function(自机){
	var 冷抗性 = 自机.魔法抗性["冷"];
	if(isNaN(冷抗性)) 冷抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(冷抗性);
};

_root.人物信息函数.获得电抗性 = function(自机){
	var 电抗性 = 自机.魔法抗性["电"];
	if(isNaN(电抗性)) 电抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(电抗性);
};

_root.人物信息函数.获得波抗性 = function(自机){
	var 波抗性 = 自机.魔法抗性["波"];
	if(isNaN(波抗性)) 波抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(波抗性);
};

_root.人物信息函数.获得冲抗性 = function(自机){
	var 冲抗性 = 自机.魔法抗性["冲"];
	if(isNaN(冲抗性)) 冲抗性 = 10 + (自机.等级 >> 1);
	return Math.floor(冲抗性);
};

_root.人物信息函数.获得综合抗性 = function(自机){
	// 统计7个元素抗性的平均值：电、热、冷、波、蚀、毒、冲
	var 默认值 = 10 + (自机.等级 >> 1);

	var 电 = 自机.魔法抗性["电"];
	if(isNaN(电)) 电 = 默认值;

	var 热 = 自机.魔法抗性["热"];
	if(isNaN(热)) 热 = 默认值;

	var 冷 = 自机.魔法抗性["冷"];
	if(isNaN(冷)) 冷 = 默认值;

	var 波 = 自机.魔法抗性["波"];
	if(isNaN(波)) 波 = 默认值;

	var 蚀 = 自机.魔法抗性["蚀"];
	if(isNaN(蚀)) 蚀 = 默认值;

	var 毒 = 自机.魔法抗性["毒"];
	if(isNaN(毒)) 毒 = 默认值;

	var 冲 = 自机.魔法抗性["冲"];
	if(isNaN(冲)) 冲 = 默认值;

	var 总和 = 电 + 热 + 冷 + 波 + 蚀 + 毒 + 冲;
	var 平均值 = 总和 / 7;

	return Math.floor(平均值);
};

// ========== 新增：防御拆分函数 ==========
_root.人物信息函数.获得基本防御 = function(自机){
	return Math.floor(自机.基本防御力);
};

_root.人物信息函数.获得装备防御 = function(自机){
	var 装备防御基础 = Math.floor(自机.装备防御力);
	var 加成 = 自机.装备防御力加成 ? Math.floor(自机.装备防御力加成) : 0;

	if(加成 > 0){
		return 装备防御基础 + " + " + 加成;
	} else if(加成 < 0){
		return 装备防御基础 + " " + 加成;
	}
	return 装备防御基础;
};

// ========== 新增：韧性系统函数 ==========
// ========== 工具函数：格式化大数值 ==========
_root.人物信息函数.格式化数值 = function(数值){
	// 当数值 >= 100000 (6位数)时，转换为k单位显示
	if(数值 >= 100000){
		var k值 = 数值 / 1000;
		return Math.floor(k值 * 10) / 10 + "k"; // 保留一位小数
	}
	return Math.floor(数值);
};

_root.人物信息函数.获得韧性上限 = function(自机){
	var 韧性上限 = 自机.韧性系数 * 自机.hp / DamageResistanceHandler.defenseDamageRatio(自机.防御力 / 1000);
	return _root.人物信息函数.格式化数值(韧性上限);
};

_root.人物信息函数.获得踉跄韧性 = function(自机){
	// 踉跄判定阈值 = 韧性上限 / 2 / 躲闪率
	var 韧性上限 = 自机.韧性系数 * 自机.hp / DamageResistanceHandler.defenseDamageRatio(自机.防御力 / 1000);
	var 踉跄韧性 = 韧性上限 / 2 / 自机.躲闪率;
	return _root.人物信息函数.格式化数值(踉跄韧性);
};

_root.人物信息函数.获得拆挡能力 = function(自机){
	return Math.floor(50 / 自机.躲闪率);
};

_root.人物信息函数.获得坚稳能力 = function(自机){
	return Math.floor(100 * 自机.韧性系数);
};

// ========== 新增：闪避相关函数 ==========
_root.人物信息函数.获得闪避负荷 = function(自机){
	return Math.floor(自机.躲闪率 * 10);
};

_root.人物信息函数.获得懒闪避 = function(自机){
	// 懒闪避值，通常是一个系数
	var 懒闪避值 = 自机.懒闪避 ? 自机.懒闪避 : 0;
	return Math.floor(懒闪避值 * 100);
};

// ========== 新增：伤害加成函数 ==========
_root.人物信息函数.获得伤害加成 = function(自机){
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(伤害加成);
};

// ========== 新增：武器威力函数 ==========
_root.人物信息函数.获得空手威力 = function(自机){
	// 空手威力 = 空手攻击力 + 伤害加成
	var 空手攻击力 = 自机.空手攻击力 ? 自机.空手攻击力 : 0;
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(空手攻击力 + 伤害加成);
};

_root.人物信息函数.获得冷兵威力 = function(自机){
	// 冷兵威力 = 刀属性.power + 伤害加成
	if(!自机.刀属性 || !自机.刀属性.power) return 0;
	var 刀威力 = 自机.刀属性.power;
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(刀威力 + 伤害加成);
};

_root.人物信息函数.获得主手威力 = function(自机){
	// 主手威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成
	if(!自机.手枪属性 || !自机.手枪属性.power) return 0;

	// 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
	var 武器威力 = ShootInitCore.calculateWeaponPower(自机, "手枪", 自机.手枪属性.power);
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(武器威力 + 伤害加成);
};

_root.人物信息函数.获得副手威力 = function(自机){
	// 副手威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成
	if(!自机.手枪2属性 || !自机.手枪2属性.power) return 0;

	// 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
	var 武器威力 = ShootInitCore.calculateWeaponPower(自机, "手枪2", 自机.手枪2属性.power);
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(武器威力 + 伤害加成);
};

_root.人物信息函数.获得长枪威力 = function(自机){
	// 长枪威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成
	if(!自机.长枪属性 || !自机.长枪属性.power) return 0;

	// 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
	var 武器威力 = ShootInitCore.calculateWeaponPower(自机, "长枪", 自机.长枪属性.power);
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(武器威力 + 伤害加成);
};

_root.人物信息函数.获得手雷威力 = function(自机){
	// 手雷威力 = 手雷属性.power + 伤害加成
	if(!自机.手雷属性 || !自机.手雷属性.power) return 0;
	var 手雷威力 = 自机.手雷属性.power;
	var 伤害加成 = 自机.伤害加成 ? 自机.伤害加成 : 0;
	return Math.floor(手雷威力 + 伤害加成);
};

_root.人物信息函数.获得空手加成 = function(自机){
	// 空手加成 = (当前空手攻击力 - 基础空手攻击力)
	// 基础空手攻击力 = 根据等级计算的基准值
	var 基础空手攻击力 = _root.根据等级计算值(自机.空手攻击力_min, 自机.空手攻击力_max, 自机.等级);
	var 加成 = 自机.空手攻击力 - 基础空手攻击力;
	return Math.floor(加成);
};

_root.人物信息函数.获得冷兵加成 = function(自机){
	var value:Number = 自机.装备刀锋利度加成 ? 自机.装备刀锋利度加成 : 0;

	return value;
};

_root.人物信息函数.获得枪械加成 = function(自机){
	var value:Number = 自机.装备枪械威力加成 ? 自机.装备枪械威力加成 : 0;

	return value;
};

_root.人物信息函数.获得身高 = function(自机){
	return _root.身高 + "cm";
};

_root.人物信息函数.获得体重 = function(自机){
	return 自机.体重 + "kg";
};

_root.人物信息函数.获得称号 = function(自机){
	return 自机.称号;
};

_root.人物信息函数.获得装备重量 = function(自机){
	return 自机.重量 + "kg";
};

_root.人物信息函数.获得经验值 = function(){
	// 返回 "等级 + 经验值" 组合信息，节省UI空间
	// 等级显示为绿色，经验值显示为青色（与MP相同的颜色），方括号显示为浅灰色
	return "<font color='#8E9599'>[</font><font color='#00FF00'> Lv." + String(_root.等级) + "</font> <font color='#8E9599'>]</font>  ·  <font color='#8E9599'>[</font> <font color='#66FFFF'>" + String(_root.经验值) + "</font> <font color='#8E9599'>]</font>";
}

_root.人物信息函数.显示负重情况 = function(目标:MovieClip,自机:MovieClip){
	var 基准负重 = _root.主角函数.获取基准负重(自机._root.等级);
	目标.轻甲_中甲重量 = 基准负重 + "kg";
	目标.中甲_重甲重量 = 基准负重 * 2 + "kg";
	目标.重甲重量 = 基准负重 * 4 + "kg";
	var 重量比值 = 自机.重量 / 基准负重 / 4;
	if(重量比值 < 0) 重量比值 = 0;
	if(重量比值 > 1) 重量比值 = 1;
	目标.负重滑块._x = 20 + 重量比值 * 240;
}

_root.人物信息函数.获取人物信息 = function(目标:MovieClip){
	var 自机 = TargetCacheManager.findHero();

	// ========== 基础信息 ==========
	目标.等级 = _root.等级;
	目标.身高 = _root.人物信息函数.获得身高();
	目标.体重 = _root.人物信息函数.获得体重(自机);
	目标.称号 = _root.人物信息函数.获得称号(自机);
	目标.经验值 = _root.人物信息函数.获得经验值();

	// ========== 负重系统 ==========
	目标.装备重量 = _root.人物信息函数.获得装备重量(自机);
	_root.人物信息函数.显示负重情况(目标,自机);

	// ========== 生命与能量 ==========
	目标.最大HP = _root.人物信息函数.获得最大HP(自机);
	目标.最大MP = _root.人物信息函数.获得最大MP(自机);
	目标.内力 = _root.人物信息函数.获得内力(自机);

	// ========== 魔法抗性 ==========
	目标.综合抗性 = _root.人物信息函数.获得综合抗性(自机); // 7个元素抗性平均值
	目标.能量抗性 = _root.人物信息函数.获得能量抗性(自机);
	目标.热抗性 = _root.人物信息函数.获得热抗性(自机);
	目标.蚀抗性 = _root.人物信息函数.获得蚀抗性(自机);
	目标.毒抗性 = _root.人物信息函数.获得毒抗性(自机);
	目标.冷抗性 = _root.人物信息函数.获得冷抗性(自机);
	目标.电抗性 = _root.人物信息函数.获得电抗性(自机);
	目标.波抗性 = _root.人物信息函数.获得波抗性(自机);
	目标.冲抗性 = _root.人物信息函数.获得冲抗性(自机);

	// ========== 防御系统 ==========
	目标.综合防御力 = _root.人物信息函数.获得综合防御力(自机);
	目标.基本防御 = _root.人物信息函数.获得基本防御(自机);
	目标.装备防御 = _root.人物信息函数.获得装备防御(自机);
	目标.减伤率 = _root.人物信息函数.获得减伤率(自机);

	// ========== 韧性系统 ==========
	目标.韧性负荷 = _root.人物信息函数.获得韧性负荷(自机);
	目标.韧性上限 = _root.人物信息函数.获得韧性上限(自机);
	目标.踉跄韧性 = _root.人物信息函数.获得踉跄韧性(自机);
	目标.拆挡能力 = _root.人物信息函数.获得拆挡能力(自机);
	目标.坚稳能力 = _root.人物信息函数.获得坚稳能力(自机);
	目标.拆挡_坚稳 = _root.人物信息函数.获得拆挡_坚稳(自机); // 兼容旧UI

	// ========== 闪避与命中 ==========
	目标.命中力 = _root.人物信息函数.获得命中力(自机);
	目标.闪避负荷 = _root.人物信息函数.获得闪避负荷(自机);
	目标.懒闪避 = _root.人物信息函数.获得懒闪避(自机);

	// ========== 硬直与移动 ==========
	目标.被击硬直度 = _root.人物信息函数.获得被击硬直度(自机);
	目标.速度 = _root.人物信息函数.获得速度(自机);

	// ========== 伤害加成 ==========
	目标.伤害加成 = _root.人物信息函数.获得伤害加成(自机);
	目标.空手加成 = _root.人物信息函数.获得空手加成(自机);
	目标.空手攻击力 = _root.人物信息函数.获得空手攻击力(自机); // 兼容旧UI
	目标.冷兵加成 = _root.人物信息函数.获得冷兵加成(自机);
	目标.枪械加成 = _root.人物信息函数.获得枪械加成(自机);

	// ========== 武器威力 ==========
	目标.空手威力 = _root.人物信息函数.获得空手威力(自机);
	目标.冷兵威力 = _root.人物信息函数.获得冷兵威力(自机);
	目标.主手威力 = _root.人物信息函数.获得主手威力(自机);
	目标.副手威力 = _root.人物信息函数.获得副手威力(自机);
	目标.长枪威力 = _root.人物信息函数.获得长枪威力(自机);
	目标.手雷威力 = _root.人物信息函数.获得手雷威力(自机);
}

// 速度 = Math.floor(自机.行走X速度 * 20) / 10 + "m/s";
// 被击硬直度 = Math.floor(自机.被击硬直度) + "ms";
// 拆挡_坚稳 = Math.floor(50 / 自机.躲闪率) + "/" + Math.floor(100 * 自机.韧性系数);
// 身高 = _root.身高 + "cm";
// 称号 = 自机.称号;
// 装备重量 = 自机.重量 + "kg";