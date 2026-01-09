import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.neur.Event.*;
import org.flashNight.naki.RandomNumberEngine.*
import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.item.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.unit.*;

// _root.玩家与佣兵区分装扮刷新 = false;

_root.主角函数 = new Object();

/*防止被自动格式折叠
   _root.技能表 = [
   {技能名:"兴奋剂", 点数:10, 冷却:2, 消耗:16, 限制:1, 距离min:200, 距离max:4100, 类型:"增益", 功能:"速度"},
   {技能名:"小跳", 点数:10, 冷却:1, 消耗:5, 限制:1, 距离min:0, 距离max:100, 类型:"躲避", 功能:"高频位移"},
   {技能名:"铁布衫", 点数:20, 冷却:5, 消耗:16, 限制:10, 距离min:200, 距离max:400, 类型:"增益", 功能:"防护"},
   {技能名:"闪现", 点数:30, 冷却:2, 消耗:10, 限制:15, 距离min:0, 距离max:100, 类型:"躲避", 功能:"长距位移"},
   {技能名:"霸体", 点数:25, 冷却:20, 消耗:40, 限制:15, 距离min:0, 距离max:400, 类型:"增益", 功能:"解围霸体"},
   {技能名:"觉醒霸体", 点数:150, 冷却:20, 消耗:60, 限制:30, 距离min:0, 距离max:400, 类型:"增益", 功能:"解围霸体"},
   {技能名:"觉醒不坏金身", 点数:200, 冷却:100, 消耗:45, 限制:1, 距离min:0, 距离max:400, 类型:"增益", 功能:"无敌"},
   {技能名:"寸拳", 点数:15, 冷却:5, 消耗:20, 限制:1, 距离min:0, 距离max:50, 类型:"格斗", 功能:"爆发输出"},
   {技能名:"气动波", 点数:20, 冷却:5, 消耗:20, 限制:1, 距离min:0, 距离max:200, 类型:"格斗", 功能:"远程输出"},
   {技能名:"踩人", 点数:15, 冷却:5, 消耗:15, 限制:1, 距离min:0, 距离max:50, 类型:"格斗", 功能:"贴身输出"},
   {技能名:"日字冲拳", 点数:20, 冷却:5, 消耗:15, 限制:10, 距离min:0, 距离max:50, 类型:"格斗", 功能:"贴身持续输出"},
   {技能名:"组合拳", 点数:20, 冷却:5, 消耗:15, 限制:10, 距离min:0, 距离max:50, 类型:"格斗", 功能:"贴身持续蓄力输出"},
   {技能名:"震地", 点数:25, 冷却:5, 消耗:30, 限制:10, 距离min:0, 距离max:100, 类型:"格斗", 功能:"爆发解围输出"},
   {技能名:"地震", 点数:60, 冷却:10, 消耗:60, 限制:30, 距离min:0, 距离max:10, 类型:"格斗", 功能:"持续解围输出"},
   {技能名:"觉醒地震", 点数:500, 冷却:25, 消耗:150, 限制:50, 距离min:0, 距离max:100, 类型:"格斗", 功能:"持续解围爆发输出"},
   {技能名:"瞬步斩", 点数:25, 冷却:5, 消耗:20, 限制:10, 距离min:0, 距离max:400, 类型:"刀技", 功能:"位移持续输出"},
   {技能名:"凶斩", 点数:25, 冷却:5, 消耗:20, 限制:15, 距离min:50, 距离max:100, 类型:"刀技", 功能:"蓄力输出"},
   {技能名:"拔刀术", 点数:50, 冷却:6, 消耗:40, 限制:25, 距离min:50, 距离max:200, 类型:"刀技", 功能:"位移持续输出"},
   {技能名:"龙斩", 点数:100, 冷却:30, 消耗:80, 限制:35, 距离min:0, 距离max:100, 类型:"刀技", 功能:"解围持续爆发输出"},
   {技能名:"火力支援", 点数:40, 冷却:15, 消耗:40, 限制:25, 距离min:200, 距离max:400, 类型:"火器", 功能:"持续输出"},
   {技能名:"拔刀术", 点数:50, 冷却:12, 消耗:120, 限制:35, 距离min:50, 距离max:200, 类型:"刀技", 功能:"位移持续输出"}
   ];
 */

// ==================== 技能点数查找表预计算（脚本加载时执行） ====================
// 预计算0-150级的技能点数，运行时直接查表，避免重复计算
var 技能点数查找表:Array = [];
var 技能点数最大预计算等级:Number = 150;
var 技能点数分界表:Array = [0, 150, 350, 600, 950, 1450, 2050, 2850];
var 技能点数分界表长度:Number = 技能点数分界表.length;

for (var 技能点lv:Number = 0; 技能点lv <= 技能点数最大预计算等级; 技能点lv++) {
    var 技能点索引:Number = (技能点lv / 10) >> 0;
    if (技能点索引 >= 技能点数分界表长度) 技能点索引 = 技能点数分界表长度 - 1;
    var 技能点数:Number = 技能点数分界表[技能点索引];
    if (技能点索引 < 技能点数分界表长度 - 1) {
        技能点数 += ((技能点lv % 10) * (技能点数分界表[技能点索引 + 1] - 技能点数分界表[技能点索引]) / 10) >> 0;
    } else if (技能点lv > 70) {
        技能点数 += (技能点lv - 70) * 100;
    }
    技能点数查找表[技能点lv] = 技能点数;
}

_root.技能点数查找表 = 技能点数查找表;
_root.技能点数最大预计算等级 = 技能点数最大预计算等级;

// 运行时直接查表，超出范围则使用最大预计算等级的值 + 额外计算
_root.计算技能点数总和 = function(目标等级:Number):Number {
    if (目标等级 <= 技能点数最大预计算等级) {
        return 技能点数查找表[目标等级];
    }
    // 超出预计算范围：基于70级后每级+100的规则
    return 技能点数查找表[技能点数最大预计算等级] + (目标等级 - 技能点数最大预计算等级) * 100;
};

//用于实现可控的伪随机生成
_root.初始化种子 = function(名字:String, 等级:Number):Number {
    var 种子:Number = 0;
    for (var i:Number = 0; i < 名字.length; i++) {
        种子 += 名字.charCodeAt(i);
    }
    种子 += 等级;
    return 种子;
};

_root.线性同余生成器 = function(种子:Number):Function {
    var a:Number = 1664525; // 乘数
    var c:Number = 1013904223; // 增量
    var m:Number = Math.pow(2, 32); // 模数

    return function():Number {
        种子 = (a * 种子 + c) % m;
        return 种子 / m;
    };
};

_root.根据等级计算值 = function(最小值, 最大值, 目前等级, 允许小数, 禁止超出最大等级, param) {
    if (禁止超出最大等级 === true && 目前等级 > _root.最大等级)
        目前等级 = _root.最大等级;
    var 该等级值 = 最小值 + (最大值 - 最小值) / (_root.最大等级 - 1) * 目前等级;
    if (!允许小数)
        该等级值 = Math.floor(该等级值);
    if (!isNaN(该等级值) && 该等级值 > 0)
        return 该等级值;
    return 1;
}

_root.身高百分比转换 = UnitUtil.getHeightPercentage;

_root.获取操控编号 = function(目标名) {
    return 目标名 == _root.控制目标 ? 0 : -1;
}

_root.技能缓存 = new Object();

_root.技能缓存["尾上世莉架_30"] = [];
_root.技能缓存["尾上世莉架_30"].push({技能名: "小跳", 点数: 10, 冷却: 1, 消耗: 5, 限制: 1, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "高频位移", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "闪现", 点数: 30, 冷却: 2, 消耗: 10, 限制: 15, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "长距位移", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "霸体", 点数: 25, 冷却: 20, 消耗: 40, 限制: 15, 距离min: 0, 距离max: 400, 类型: "增益", 功能: "解围霸体", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "寸拳", 点数: 15, 冷却: 5, 消耗: 20, 限制: 1, 距离min: 30, 距离max: 100, 类型: "格斗", 功能: "爆发输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "日字冲拳", 点数: 20, 冷却: 5, 消耗: 15, 限制: 10, 距离min: 0, 距离max: 100, 类型: "格斗", 功能: "贴身持续输出", 技能等级: 10, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "瞬步斩", 点数: 25, 冷却: 5, 消耗: 20, 限制: 10, 距离min: 50, 距离max: 250, 类型: "刀技", 功能: "位移持续输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "凶斩", 点数: 25, 冷却: 5, 消耗: 20, 限制: 15, 距离min: 40, 距离max: 80, 类型: "刀技", 功能: "蓄力输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_30"].push({技能名: "拔刀术", 点数: 50, 冷却: 6, 消耗: 40, 限制: 25, 距离min: 0, 距离max: 400, 类型: "刀技", 功能: "蓄力输出", 技能等级: 1, 上次使用时间: NaN});


_root.技能缓存["尾上世莉架_40"] = [];
_root.技能缓存["尾上世莉架_40"].push({技能名: "小跳", 点数: 10, 冷却: 1, 消耗: 5, 限制: 1, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "高频位移", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "闪现", 点数: 40, 冷却: 2, 消耗: 10, 限制: 15, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "长距位移", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "霸体", 点数: 25, 冷却: 20, 消耗: 40, 限制: 15, 距离min: 0, 距离max: 400, 类型: "增益", 功能: "解围霸体", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "寸拳", 点数: 15, 冷却: 5, 消耗: 20, 限制: 1, 距离min: 40, 距离max: 100, 类型: "格斗", 功能: "爆发输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "日字冲拳", 点数: 20, 冷却: 5, 消耗: 15, 限制: 10, 距离min: 0, 距离max: 100, 类型: "格斗", 功能: "贴身持续输出", 技能等级: 10, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "瞬步斩", 点数: 25, 冷却: 5, 消耗: 20, 限制: 10, 距离min: 50, 距离max: 250, 类型: "刀技", 功能: "位移持续输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "凶斩", 点数: 25, 冷却: 5, 消耗: 20, 限制: 15, 距离min: 40, 距离max: 80, 类型: "刀技", 功能: "蓄力输出", 技能等级: 1, 上次使用时间: NaN});
_root.技能缓存["尾上世莉架_40"].push({技能名: "拔刀术", 点数: 50, 冷却: 6, 消耗: 40, 限制: 25, 距离min: 0, 距离max: 400, 类型: "刀技", 功能: "蓄力输出", 技能等级: 1, 上次使用时间: NaN});


/*
   _root.佣兵装备位映射对象 = {
   头部装备:6,
   上装装备:7,
   手部装备:8,
   下装装备:9,
   脚部装备:10,
   颈部装备:11,
   长枪:12,
   手枪:13,
   手枪2:14,
   刀:15,
   手雷:16
   }

   //装备强化度
   _root.佣兵装备位映射数组 = [];
   _root.佣兵装备位映射数组[6] = "头部装备";
   _root.佣兵装备位映射数组[7] = "上装装备";
   _root.佣兵装备位映射数组[8] = "手部装备";
   _root.佣兵装备位映射数组[9] = "下装装备";
   _root.佣兵装备位映射数组[10] = "脚部装备";
   _root.佣兵装备位映射数组[11] = "颈部装备";
   _root.佣兵装备位映射数组[12] = "长枪";
   _root.佣兵装备位映射数组[13] = "手枪";
   _root.佣兵装备位映射数组[14] = "手枪2";
   _root.佣兵装备位映射数组[15] = "刀";
   _root.佣兵装备位映射数组[16] = "手雷";
 */

_root.刷新人物装扮 = function(目标) {
    var 目标人物 = _root.gameworld[目标];
    目标人物.hasDressup = true;
    目标人物.enableShoot = true;

    if (!目标人物.新版人物文字信息) {
        目标人物.新版人物文字信息 = 目标人物.人物文字信息;
        目标人物.新版人物文字信息._name = "新版人物文字信息";
        目标人物.人物文字信息 = null;
    }

    // 清理射击相关任务，防止武器切换时射速继承问题
    ShootCore.cleanup(目标人物);

    StaticInitializer.initializeUnit(目标人物); // 包含了整理后的刷新装扮函数

    //佣兵战力强化修正                                                                                                              
    if (目标人物.是否为敌人 == false && _root.控制目标 != 目标) {
        目标人物.mp满血值 /= 10;
        目标人物.mp = Math.min(目标人物.mp, 目标人物.mp满血值);
    }

    目标人物.读取基础被动效果();
    目标人物.buff.初始();
    目标人物.buff.更新();
    if (目标人物.变形手枪) {
        目标人物.变形手枪.切换武器形态为当前模式();
    }

    目标人物.gotoAndPlay("刷新装扮");
};


//主角函数

var 人形怪技能表 = new Array();

人形怪技能表.push({技能名: "兴奋剂", 点数: 10, 冷却: 120, 消耗: 16, 限制: 1, 距离min: 200, 距离max: 400, 类型: "增益", 功能: "速度"});
人形怪技能表.push({技能名: "小跳", 点数: 10, 冷却: 1, 消耗: 5, 限制: 1, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "高频位移"});
人形怪技能表.push({技能名: "铁布衫", 点数: 20, 冷却: 120, 消耗: 16, 限制: 10, 距离min: 200, 距离max: 400, 类型: "增益", 功能: "防护"});
人形怪技能表.push({技能名: "闪现", 点数: 30, 冷却: 2, 消耗: 10, 限制: 25, 距离min: 0, 距离max: 100, 类型: "躲避", 功能: "长距位移"});
人形怪技能表.push({技能名: "霸体", 点数: 10, 冷却: 20, 消耗: 40, 限制: 15, 距离min: 0, 距离max: 400, 类型: "增益", 功能: "解围霸体"});
人形怪技能表.push({技能名: "觉醒霸体", 点数: 150, 冷却: 120, 消耗: 60, 限制: 30, 距离min: 0, 距离max: 400, 类型: "增益", 功能: "解围霸体"});
人形怪技能表.push({技能名: "寸拳", 点数: 10, 冷却: 5, 消耗: 20, 限制: 1, 距离min: 30, 距离max: 100, 类型: "格斗", 功能: "爆发输出"});
人形怪技能表.push({技能名: "气动波", 点数: 15, 冷却: 5, 消耗: 20, 限制: 1, 距离min: 50, 距离max: 400, 类型: "格斗", 功能: "远程输出"});
人形怪技能表.push({技能名: "踩人", 点数: 15, 冷却: 5, 消耗: 15, 限制: 1, 距离min: 0, 距离max: 50, 类型: "格斗", 功能: "贴身输出"});
人形怪技能表.push({技能名: "日字冲拳", 点数: 20, 冷却: 5, 消耗: 15, 限制: 10, 距离min: 30, 距离max: 60, 类型: "格斗", 功能: "贴身持续输出"});
人形怪技能表.push({技能名: "组合拳", 点数: 5, 冷却: 5, 消耗: 15, 限制: 10, 距离min: 30, 距离max: 60, 类型: "格斗", 功能: "贴身持续蓄力输出"});
人形怪技能表.push({技能名: "虎拳", 点数: 30, 冷却: 8, 消耗: 30, 限制: 30, 距离min: 30, 距离max: 60, 类型: "格斗", 功能: "贴身持续输出"});
人形怪技能表.push({技能名: "震地", 点数: 25, 冷却: 5, 消耗: 30, 限制: 10, 距离min: 0, 距离max: 100, 类型: "格斗", 功能: "爆发解围输出"});
人形怪技能表.push({技能名: "地震", 点数: 60, 冷却: 10, 消耗: 60, 限制: 30, 距离min: 0, 距离max: 100, 类型: "格斗", 功能: "持续解围输出"});
//人形怪技能表.push({技能名:"觉醒地震", 点数:500, 冷却:25, 消耗:150, 限制:50, 距离min:0, 距离max:100, 类型:"格斗", 功能:"持续解围爆发输出"});
人形怪技能表.push({技能名: "瞬步斩", 点数: 20, 冷却: 5, 消耗: 20, 限制: 10, 距离min: 50, 距离max: 250, 类型: "刀技", 功能: "位移持续输出"});
人形怪技能表.push({技能名: "凶斩", 点数: 25, 冷却: 5, 消耗: 20, 限制: 15, 距离min: 40, 距离max: 80, 类型: "刀技", 功能: "蓄力输出"});
人形怪技能表.push({技能名: "拔刀术", 点数: 50, 冷却: 6, 消耗: 40, 限制: 25, 距离min: 0, 距离max: 400, 类型: "刀技", 功能: "位移持续输出"});
人形怪技能表.push({技能名: "龙斩", 点数: 100, 冷却: 30, 消耗: 80, 限制: 35, 距离min: 0, 距离max: 150, 类型: "刀技", 功能: "解围持续爆发输出"});
人形怪技能表.push({技能名: "能量盾", 点数: 20, 冷却: 60, 消耗: 50, 限制: 10, 距离min: 100, 距离max: 400, 类型: "增益", 功能: "防护"});
人形怪技能表.push({技能名: "翻滚换弹", 点数: 15, 冷却: 15, 消耗: 50, 限制: 15, 距离min: 200, 距离max: 500, 类型: "火器", 功能: "换弹"});
//人形怪技能表.push({技能名:"火力支援", 点数:40, 冷却:15, 消耗:40, 限制:25, 距离min:200, 距离max:400, 类型:"火器", 功能:"持续输出"});
//人形怪技能表.push({技能名:"拔刀术", 点数:50, 冷却:12, 消耗:120, 限制:35, 距离min:50, 距离max:400, 类型:"刀技", 功能:"位移持续输出"});

_root.主角函数.人形怪技能表 = 人形怪技能表;

// ==================== 技能等级桶 + 装备类型预分桶初始化（脚本加载时执行） ====================
// 按等级分桶：桶[等级] 包含所有 限制 <= 等级 的技能索引
// 按装备类型分桶：装备技能桶[等级][装备组合] = 技能索引数组
// 装备组合: 0=无刀无枪, 1=有刀无枪, 2=无刀有枪, 3=有刀有枪
var 技能桶初始化用技能表:Array = 人形怪技能表;
var 技能桶:Object = {};
var 装备技能桶:Object = {};
var 技能桶最大等级限制:Number = 0;
var 技能桶初始化表长度:Number = 技能桶初始化用技能表.length;

// 第一遍：找出最大等级限制
for (var 技能桶i:Number = 0; 技能桶i < 技能桶初始化表长度; 技能桶i++) {
    if (技能桶初始化用技能表[技能桶i].限制 > 技能桶最大等级限制) {
        技能桶最大等级限制 = 技能桶初始化用技能表[技能桶i].限制;
    }
}

// 第二遍：构建等级桶和装备分类桶
var 技能桶当前桶:Array = [];
var 装备桶0:Array = []; // 无刀无枪
var 装备桶1:Array = []; // 有刀无枪
var 装备桶2:Array = []; // 无刀有枪
var 装备桶3:Array = []; // 有刀有枪

for (var 技能桶lv:Number = 1; 技能桶lv <= 技能桶最大等级限制 + 10; 技能桶lv++) {
    for (var 技能桶j:Number = 0; 技能桶j < 技能桶初始化表长度; 技能桶j++) {
        if (技能桶初始化用技能表[技能桶j].限制 == 技能桶lv) {
            var 技能类型:String = 技能桶初始化用技能表[技能桶j].类型;
            技能桶当前桶.push(技能桶j);

            // 根据技能类型分配到不同装备组合桶
            if (技能类型 == "刀技") {
                // 刀技只加到有刀的组合 (1, 3)
                装备桶1.push(技能桶j);
                装备桶3.push(技能桶j);
            } else if (技能类型 == "火器") {
                // 火器只加到有枪的组合 (2, 3)
                装备桶2.push(技能桶j);
                装备桶3.push(技能桶j);
            } else {
                // 通用技能，所有组合都加
                装备桶0.push(技能桶j);
                装备桶1.push(技能桶j);
                装备桶2.push(技能桶j);
                装备桶3.push(技能桶j);
            }
        }
    }
    技能桶[技能桶lv] = 技能桶当前桶.slice(0);
    装备技能桶[技能桶lv] = [装备桶0.slice(0), 装备桶1.slice(0), 装备桶2.slice(0), 装备桶3.slice(0)];
}

_root.主角函数.技能等级桶 = 技能桶;
_root.主角函数.装备技能桶 = 装备技能桶;
_root.主角函数.技能等级桶最大等级 = 技能桶最大等级限制 + 10;

_root.主角函数.初始化可用技能 = function() {
    if (this.佣兵参数 && this.佣兵参数.被动技能) {
        this.被动技能 = this.佣兵参数.被动技能;
    }

    // 缓存 _root 引用，减少链式访问开销
    var 主角函数:Object = _root.主角函数;
    var 技能缓存:Object = _root.技能缓存;
    var 技能点数表:Array = _root.技能点数查找表;

    var 缓存键:String = 名字 + "_" + 等级;
    if (技能缓存 && 技能缓存[缓存键] != undefined) {
        this.已学技能表 = 技能缓存[缓存键];
        return;
    }

    var 可学技能数:Number = 3 + ((等级 / 5) >> 0); // 位运算替代Math.floor

    // 计算装备组合索引: 0=无刀无枪, 1=有刀无枪, 2=无刀有枪, 3=有刀有枪
    var 有刀:Number = 刀 ? 1 : 0;
    var 有枪:Number = (长枪 || 手枪 || 手枪2) ? 2 : 0;
    var 装备组合:Number = 有刀 + 有枪;

    // 内联种子初始化
    var 种子:Number = 等级;
    var 名字长度:Number = 名字.length;
    for (var i:Number = 0; i < 名字长度; i++) {
        种子 += 名字.charCodeAt(i);
    }

    // 线性同余生成器常量（内联使用，避免闭包）
    var LCG_A:Number = 1664525;
    var LCG_C:Number = 1013904223;
    var LCG_M:Number = 4294967296;

    // 调用函数获取技能点数（内部已处理查表和超范围计算）
    var 技能点总数:Number = _root.计算技能点数总和(等级);
    var 技能表:Array = 主角函数.人形怪技能表;

    // 从预处理的装备技能桶直接获取可用技能索引（已按装备类型过滤）
    var 桶最大等级:Number = 主角函数.技能等级桶最大等级;
    var 查询等级:Number = 等级 > 桶最大等级 ? 桶最大等级 : 等级;
    var 预过滤索引:Array = 主角函数.装备技能桶[查询等级][装备组合];

    // 复制一份用于随机抽取（避免修改原数组）
    var 可用技能表:Array = 预过滤索引.slice(0);

    var 可用技能强化表:Array = [];
    this.已学技能表 = [];
    var 可用长度:Number;
    var 随机索引:Number;
    var 最后索引:Number;
    var 原始技能:Object;
    var 点数:Number;

    // 从符合条件的技能中随机选择技能
    while (可学技能数 > 0 && (可用长度 = 可用技能表.length) > 0) {
        // 内联随机数生成
        种子 = (LCG_A * 种子 + LCG_C) % LCG_M;
        随机索引 = (种子 / LCG_M * 可用长度) >> 0;

        // 内联交换删除
        var 待检测技能索引:Number = 可用技能表[随机索引];
        最后索引 = 可用长度 - 1;
        if (随机索引 != 最后索引) {
            可用技能表[随机索引] = 可用技能表[最后索引];
        }
        可用技能表.pop();

        原始技能 = 技能表[待检测技能索引];
        点数 = 原始技能.点数;

        if (技能点总数 >= 点数) {
            // 内联显式属性拷贝
            可用技能强化表.push({
                技能名: 原始技能.技能名,
                点数: 点数,
                冷却: 原始技能.冷却,
                消耗: 原始技能.消耗,
                限制: 原始技能.限制,
                距离min: 原始技能.距离min,
                距离max: 原始技能.距离max,
                类型: 原始技能.类型,
                功能: 原始技能.功能,
                技能等级: 1,
                上次使用时间: NaN
            });
            可学技能数--;
            技能点总数 -= 点数;
        }
    }

    var 待强化技能:Object;
    var 强化点数:Number;

    // 随机分配技能点，用于提升技能等级
    while (技能点总数 > 0 && (可用长度 = 可用技能强化表.length) > 0) {
        // 内联随机数生成
        种子 = (LCG_A * 种子 + LCG_C) % LCG_M;
        随机索引 = (种子 / LCG_M * 可用长度) >> 0;

        待强化技能 = 可用技能强化表[随机索引];
        强化点数 = 待强化技能.点数;

        if (技能点总数 >= 强化点数 && 待强化技能.技能等级 < 10) {
            待强化技能.技能等级 += 1;
            技能点总数 -= 强化点数;
        } else {
            // 内联交换删除并添加到已学技能表
            最后索引 = 可用长度 - 1;
            if (随机索引 != 最后索引) {
                可用技能强化表[随机索引] = 可用技能强化表[最后索引];
            }
            this.已学技能表.push(待强化技能);
            可用技能强化表.pop();
        }
    }

    // 将剩余的技能添加到技能表
    var 强化表长度:Number = 可用技能强化表.length;
    for (var i:Number = 0; i < 强化表长度; i++) {
        this.已学技能表.push(可用技能强化表[i]);
    }

    技能缓存[缓存键] = this.已学技能表;
};

_root.主角函数.行走_玩家 = function() {
    // 提取频繁访问的属性到局部变量
    var self = this;
    var isFlying = self.飞行浮空;
    var rightMove = self.右行;
    var leftMove = self.左行;
    var upMove = self.上行;
    var downMove = self.下行;
    var currentDirection = self.方向;
    var isMainHandShooting = self.主手射击中;
    var isOffHandShooting = self.副手射击中;
    var isReloading = self.man.换弹标签;
    var isActionA = self.动作A;
    var isActionB = self.动作B;

    // 提前计算复合条件
    var isShooting = isMainHandShooting || isOffHandShooting;
    var isMoving = rightMove || leftMove || upMove || downMove;
    var isShootingRestricted = isShooting && (射击最大后摇中 || isActionA || isActionB);
    var shouldRestrictMovement = (isShootingRestricted || isReloading);
    var isBackwardsShooting = false;

    // 飞行状态检查 - 如果在飞行状态则直接返回
    if (isFlying)
        return;

    // 重置旋转
    self._rotation = 0;
    self.移动射击倒退 = false;

    // 射击时移动限制
    if (shouldRestrictMovement) {
        强制奔跑 = false;

        if (!self.移动射击) {
            rightMove = leftMove = false;
        }

        if (!self.上下移动射击) {
            upMove = downMove = false;
        }
    }

    // 处理移动逻辑
    if (isMoving) {
        var isWalking = self.状态 != self.攻击模式 + "跑" && !强制奔跑;

        // 行走状态处理
        if (isWalking) {
            // 水平移动处理
            if (rightMove) {
                if (self.移动射击 && isShooting && currentDirection === "左") {
                    isBackwardsShooting = true;
                } else {
                    self.方向改变("右");
                }
                self.移动("右", self.行走X速度);
                self.状态改变(self.攻击模式 + "行走");
            } else if (leftMove) {
                if (self.移动射击 && isShooting && currentDirection === "右") {
                    isBackwardsShooting = true;
                } else {
                    self.方向改变("左");
                }
                self.移动("左", self.行走X速度);
                self.状态改变(self.攻击模式 + "行走");
            }

            // 垂直移动处理
            if (downMove) {
                self.移动("下", self.行走Y速度);
                self.状态改变(self.攻击模式 + "行走");
            } else if (upMove) {
                self.移动("上", self.行走Y速度);
                self.状态改变(self.攻击模式 + "行走");
            }
        }
        // 奔跑状态处理
        else {
            // 水平奔跑处理
            if (rightMove) {
                self.方向改变("右");
                self.移动("右", self.跑X速度);
                self.状态改变(self.攻击模式 + "跑");
            } else if (leftMove) {
                self.方向改变("左");
                self.移动("左", self.跑X速度);
                self.状态改变(self.攻击模式 + "跑");
            }

            // 垂直奔跑处理
            if (downMove) {
                self.移动("下", self.跑Y速度);
                self.状态改变(self.攻击模式 + "跑");
            } else if (upMove) {
                self.移动("上", self.跑Y速度);
                self.状态改变(self.攻击模式 + "跑");
            }
        }
    }
    // 站立状态处理
    else {
        self.状态改变(self.攻击模式 + "站立");
    }

    // 更新移动射击倒退状态
    self.移动射击倒退 = isBackwardsShooting;
};

_root.主角函数.行走 = function() {
    // 提取频繁访问的属性到局部变量
    var self = this;
    var rightMove = self.右行;
    var leftMove = self.左行;
    var upMove = self.上行;
    var downMove = self.下行;
    var currentDirection = self.方向;
    var isMainHandShooting = self.主手射击中;
    var isOffHandShooting = self.副手射击中;
    var isReloading = self.man.换弹标签;
    var isActionA = self.动作A;
    var isActionB = self.动作B;

    // 提前计算复合条件
    var isShooting = isMainHandShooting || isOffHandShooting;
    var isMoving = rightMove || leftMove || upMove || downMove;
    var isShootingRestricted = isShooting && (射击最大后摇中 || isActionA || isActionB);
    var shouldRestrictMovement = (isShootingRestricted || isReloading);
    var isBackwardsShooting = false;

    // 重置移动射击倒退状态
    self.移动射击倒退 = false;

    // 射击时移动限制
    if (shouldRestrictMovement) {
        强制奔跑 = false;

        if (!移动射击) {
            rightMove = leftMove = false;
        }

        if (!上下移动射击) {
            upMove = downMove = false;
        }
    }

    // 处理移动逻辑
    if (isMoving) {
        var isWalking = 状态 != 攻击模式 + "跑" && !强制奔跑;

        // 行走状态处理
        if (isWalking) {
            // 水平移动处理
            if (rightMove) {
                if (移动射击 && isShooting && currentDirection === "左") {
                    isBackwardsShooting = true;
                } else {
                    方向改变("右");
                }
                移动("右", 行走X速度);
                状态改变(攻击模式 + "行走");
            } else if (leftMove) {
                if (移动射击 && isShooting && currentDirection === "右") {
                    isBackwardsShooting = true;
                } else {
                    方向改变("左");
                }
                移动("左", 行走X速度);
                状态改变(攻击模式 + "行走");
            }

            // 垂直移动处理
            if (downMove) {
                移动("下", 行走Y速度);
                状态改变(攻击模式 + "行走");
            } else if (upMove) {
                移动("上", 行走Y速度);
                状态改变(攻击模式 + "行走");
            }
        }
        // 奔跑状态处理
        else {
            // 水平奔跑处理
            if (rightMove) {
                方向改变("右");
                移动("右", 跑X速度);
                状态改变(攻击模式 + "跑");
            } else if (leftMove) {
                方向改变("左");
                移动("左", 跑X速度);
                状态改变(攻击模式 + "跑");
            }

            // 垂直奔跑处理
            if (downMove) {
                移动("下", 跑Y速度);
                状态改变(攻击模式 + "跑");
            } else if (upMove) {
                移动("上", 跑Y速度);
                状态改变(攻击模式 + "跑");
            }
        }
    }
    // 站立状态处理
    else {
        状态改变(攻击模式 + "站立");
    }

    // 更新移动射击倒退状态
    self.移动射击倒退 = isBackwardsShooting;
};

_root.主角函数.人物暂停 = function() {
    this.上键 = 0;
    this.下键 = 0;
    this.左键 = 0;
    this.右键 = 0;
    this.A键 = 0;
    this.B键 = 0;
    this.C键 = 0;
    this.切换武器键 = 0;
    this.技能键 = 0;
    this.物品键 = 0;
    this.闪避键 = 0;
    this.菜单键 = 0;
};

_root.主角函数.获取键值 = function() {
    this.上键 = _root.上键;
    this.下键 = _root.下键;
    this.左键 = _root.左键;
    this.右键 = _root.右键;
    this.A键 = _root.A键;
    this.B键 = _root.B键;
    this.C键 = _root.C键;
    this.切换武器键 = _root.切换武器键;
    this.技能键 = null;
    this.物品键 = null;
    this.闪避键 = null;
    this.菜单键 = null;
};

_root.主角函数.根据等级初始数值 = function(等级值) {
    this.hp基本满血值 = _root.根据等级计算值(this.hp_min, this.hp_max, 等级值);
    this.mp基本满血值 = _root.根据等级计算值(this.mp_min, this.mp_max, 等级值);
    this.hp满血值 = this.hp基本满血值 + this.hp满血值装备加层;
    this.mp满血值 = this.mp基本满血值 + this.mp满血值装备加层;
    if (this.是否为敌人 == false && _root.控制目标 != this._name) {
        this.hp满血值 *= 3;
        this.mp满血值 /= 10;
    }
    this.空手攻击力 = _root.根据等级计算值(this.空手攻击力_min, this.空手攻击力_max, 等级值);
    this.基本防御力 = _root.根据等级计算值(this.基本防御力_min, this.基本防御力_max, 等级值);
    this.防御力 = this.基本防御力 + this.装备防御力;
    this.躲闪率 = _root.根据等级计算值(this.躲闪率_min, this.躲闪率_max, 等级值, true, true); // 允许小数，且在60级后不再增长防止出现小于1的躲闪率
    _root.刷新人物装扮(this._name);
};

_root.主角函数.非主角外观刷新 = function() {
    _root.刷新人物装扮(this._name);
};


_root.主角函数.移动 = function(移动方向, 速度) {
    if (this.飞行浮空)
        return;

    // 浮空状态下，上/下使用跳跃移动
    if (this.浮空) {
        // 使用 2.5D 跳跃移动（跳跃状态传 true）
        Mover.move25D(this, 移动方向, 速度);
        return;
    }

    // 其他情况采用常规 2D 移动
    Mover.move2D(this, 移动方向, 速度);

/*
   if(_root.调试模式) {
   var point:Vector = new Vector(this._x, this._y);
   _root.collisionLayer.localToGlobal(point);
   _root.gameworld.globalToLocal(point)
   EffectSystem.Effect("调试用定位", point.x, point.y, 100, true);
   }
 */
};

_root.主角函数.攻击时移动 = function(慢速度, 快速度) {
    if (this._name != _root.控制目标 || isNaN(快速度)) {
        Mover.move2D(this, this.方向, 慢速度);
        return;
    }

    var func:Function = 快速度 > 100 ? Mover.move2D : Mover.move2DStrict;
    if (this.右行)
        func(this, "右", 快速度);
    else if (this.左行)
        func(this, "左", 快速度);
    else
        Mover.move2D(this, this.方向, 慢速度);
}

_root.主角函数.严格移动 = function(移动方向, 速度) {
    Mover.move2DStrict(this, 移动方向, 速度);
};

_root.主角函数.跳跃上下移动 = function(移动方向, 速度) {
    // 调用 Mover.move25D，跳跃状态传 true
    Mover.move25D(this, 移动方向, 速度);
};

_root.主角函数.强制移动 = function(移动方向, 速度) {
    // 调用 2.5D 移动
    Mover.move25D(this, 移动方向, 速度);
};


// 保持全局引用
_root.移动 = _root.主角函数.移动;


_root.主角函数.被击移动 = function(移动方向, 速度, 摩擦力) {
    移动钝感硬直(_root.钝感硬直时间);
    减速度 = 摩擦力;
    speed = 速度;
    if (移动方向 === "右") {
        this.onEnterFrame = function() {
            if (硬直中 == false) {
                speed -= 减速度;
                this.移动("右", speed);
                if (speed <= 0) {
                    delete this.onEnterFrame;
                }
            }
        };
    } else {
        this.onEnterFrame = function() {
            if (硬直中 == false) {
                speed -= 减速度;
                this.移动("左", speed);
                if (speed <= 0) {
                    delete this.onEnterFrame;
                }
            }
        };
    }
};


_root.主角函数.拾取 = function() {
    if (this.hp > 0 && this.状态 != "技能" && this.状态 != "战技") {
        状态改变("拾取");
    }
};

_root.主角函数.跳 = function() {
    // 判断是否飞行浮空状态
    if (this.飞行浮空) {
        // _root.服务器.发布服务器消息("跳跃取消：飞行浮空中");
        return;
    }

    // **新增：如果当前状态已是 跳，就取消后续初始化。**
    var 跳跃状态名 = 攻击模式 + "跳";
    if (状态 === 跳跃状态名) {
        // _root.服务器.发布服务器消息("跳跃取消：已在跳跃中，忽略重复触发");
        return;
    }

    // _root.服务器.发布服务器消息("触发跳跃");

    // 当前状态记录
    // _root.服务器.发布服务器消息("当前状态: " + 状态);
    // _root.服务器.发布服务器消息("攻击模式: " + 攻击模式);

    // 根据状态设置跳跃速度
    if (状态 === 攻击模式 + "站立") {
        跳横移速度 = 0;
        跳跃中移动速度 = 行走X速度;
            // _root.服务器.发布服务器消息("跳跃起始状态：站立 → 跳横移速度 = 0, 跳跃中移动速度 = " + 行走X速度);
    } else if (状态 === 攻击模式 + "行走") {
        跳横移速度 = 行走X速度;
        跳跃中移动速度 = 行走X速度;
            // _root.服务器.发布服务器消息("跳跃起始状态：行走 → 跳横移速度 = " + 行走X速度);
    } else if (状态 === 攻击模式 + "跑") {
        跳横移速度 = 跑X速度;
        跳跃中移动速度 = 跑X速度;
            // _root.服务器.发布服务器消息("跳跃起始状态：跑 → 跳横移速度 = " + 跑X速度);
    } else {
        // _root.服务器.发布服务器消息("未知状态，未设置跳跃速度");
    }

    // 判断左右方向
    if (this.右行) {
        跳跃中左右方向 = "右";
    } else if (this.左行) {
        跳跃中左右方向 = "左";
    } else {
        跳跃中左右方向 = "无";
    }

    // _root.服务器.发布服务器消息("跳跃中左右方向: " + 跳跃中左右方向);

    // 判断上下方向
    if (this.上行) {
        跳跃中上下方向 = "上";
    } else if (this.下行) {
        跳跃中上下方向 = "下";
    } else {
        跳跃中上下方向 = "无";
    }
    // _root.服务器.发布服务器消息("跳跃中上下方向: " + 跳跃中上下方向);

    // 设置动画播放状态
    this.动画是否正在播放 = true;
    // _root.服务器.发布服务器消息("动画是否正在播放: true");

    // 变更状态
    var 新状态 = 攻击模式 + "跳";
    状态改变(新状态);
    // _root.服务器.发布服务器消息("状态改变为: " + 新状态);
};


_root.主角函数.冲击 = function() {
    状态改变(攻击模式 + "冲击");
};

_root.主角函数.攻击 = function() {
    //适配移动射击
    if (攻击模式 === "长枪" || 攻击模式 === "双枪" || 攻击模式 === "手枪" || 攻击模式 === "手枪2") {
        if (!移动射击 && 状态 != 攻击模式 + "站立") {
            状态改变(攻击模式 + "站立");
        } else if (移动射击 && 状态 === 攻击模式 + "跑") {
            状态改变(攻击模式 + "行走");
        }

        this.man.开始射击();
    } else {
        状态改变(攻击模式 + "攻击");
    }
};

_root.主角函数.方向改变 = function(新方向) {
    if (this.锁定方向)
        return;
    //加上飞行浮空的判断
    if (this.飞行浮空)
        return;

    旧方向 = 方向;
    if (新方向 === "右") {
        方向 = "右";
        this._xscale = myxscale;
        新版人物文字信息._xscale = 100;
    } else if (新方向 === "左") {
        方向 = "左";
        this._xscale = -myxscale;
        新版人物文字信息._xscale = -100;
    }
};


_root.主角函数.动画完毕 = function() {
    this.技能名 = null;
    if (this.hp <= 0) {
        this.状态改变("血腥死");
        return;
    }
    if (this.状态 === this.攻击模式 + "跳" && 跳横移速度 === 跑X速度 && (this.左行 || this.右行 || this.上行 || this.下行)) {
        this.状态改变(this.攻击模式 + "跑");
        return;
    }
    // 技能浮空检查：使用单位级别的技能浮空标记
    if (this.技能浮空) {
        // _root.是否阴影 = true;
        if (this.攻击模式 === "空手" || this.攻击模式 === "兵器") {
            this.状态改变(this.攻击模式 + "跳");
            return;
        } else {
            this.状态改变("空手跳");
            return;
        }
    }
    this.状态改变(this.攻击模式 + "站立");
    this.aabbCollider.updateFromUnitArea(this);
};

_root.主角函数.硬直 = function(目标, 时间) {
    if (this.stiffID != null)
        return;
    var 自机:Object = this; // 在外部保存对当前对象的引用
    目标.stop();

    this.stiffID = EnhancedCooldownWheel.I().addTask(function() {
        自机.stiffID = null;
        目标.play();
    }, 时间, 1);

    if (_root.控制目标 === this._name && this.浮空) {
        if (this.垂直速度 > -1 && this.状态 != "技能" && !this.man.坠地中) {
            if (this.状态 == "空手跳" && this.被动技能.拳脚攻击 && this.被动技能.拳脚攻击.启用) {
                this.垂直速度 = -9;
                if (!isNaN(this.man.反作用力速度)) {
                    this.垂直速度 = this.man.反作用力速度;
                }
            } else if (this.状态 == "兵器跳" && this.被动技能.刀剑攻击 && this.被动技能.刀剑攻击.启用) {
                this.垂直速度 = -9;
            }
        } else if (this.垂直速度 > -1 && this.getSmallState() == "龙斩中") {
            this.垂直速度 = -5;
        } else if (this.垂直速度 > -10 && this.getSmallState() == "踩人中") {
            this.垂直速度 = -15;
        } else if (this.垂直速度 > -10 && this.getSmallState() == "凶斩中") {
            this.垂直速度 = -16;
        } else if (this.垂直速度 > -10 && this.getSmallState() == "瞬步斩一段中") {
            this.垂直速度 = -13;
        } else if (this.垂直速度 > -10 && this.getSmallState() == "六连中") {
            this.垂直速度 = -0;
        } else if (this.垂直速度 > -10 && this.getSmallState() == "拔刀术中") {
            this.垂直速度 = -0;
        }
        if (this.飞行浮空 && this.状态.indexOf("跳") == -1) {
            if (this.flySpeed < 3 && this.getSmallState() == "踩人中") {
                this.flySpeed = 3;
            } else if (this.flySpeed < 3 && this.getSmallState() == "凶斩中") {
                this.flySpeed = 3;
            } else if (this.flySpeed < 3 && this.getSmallState() == "瞬步斩一段中") {
                this.flySpeed = 3;
            }
        }
    }
};
_root.主角函数.移动钝感硬直 = function(时间) {
    if (this.knockStiffID != null)
        return;
    var 自机:Object = this; // 在外部保存对当前对象的引用

    this.硬直中 = true;
    this.knockStiffID = EnhancedCooldownWheel.I().addTask(function() {
        自机.knockStiffID = null;
        自机.硬直中 = false;
    }, 时间, 1);
};

//切换武器
_root.主角函数.攻击模式切换 = function(模式) {
    if (this.飞行浮空 && this._name === _root.控制目标) {
        存储当前飞行状态("切换武器");
    }
    if (模式 != "手枪") {
        this.根据模式重新读取武器加成(模式);
    }
    if (模式 === "空手") {
        攻击模式 = 模式;
        状态改变("攻击模式切换");
    }
    if (模式 === "手雷" && 手雷) {
        if (是否允许发送联机数据 != true) {
            攻击模式 = 模式;
            状态改变("攻击模式切换");
        }
    }
    if (模式 === "长枪" && 长枪) {
        攻击模式 = 模式;
        状态改变("攻击模式切换");
    }
    if (模式 === "兵器" && 刀) {
        攻击模式 = 模式;
        状态改变("攻击模式切换");
    }
    if (模式 === "手枪") {
        if (手枪2 && 手枪) {
            攻击模式 = "双枪";
            this.根据模式重新读取武器加成("手枪2");
            this.根据模式重新读取武器加成("手枪");
            状态改变("攻击模式切换");
        } else if (手枪) {
            攻击模式 = "手枪";
            this.根据模式重新读取武器加成("手枪");
            状态改变("攻击模式切换");
        } else if (手枪2) {
            攻击模式 = "手枪2";
            this.根据模式重新读取武器加成("手枪2");
            状态改变("攻击模式切换");
        }
    }
    if (_root.控制目标 === this._name) {
        _root.玩家信息界面.刷新攻击模式(this.攻击模式);
    }

};


_root.主角函数.根据模式重新读取武器加成 = function(模式) {
    if (this[模式 + "伤害类型"]) {
        this.伤害类型 = this[模式 + "伤害类型"] || "物理";
    } else {
        this.伤害类型 = this.基础伤害类型 || "物理";
    }
    if (this[模式 + "魔法伤害属性"]) {
        this.魔法伤害属性 = this[模式 + "魔法伤害属性"];
    } else {
        this.魔法伤害属性 = this.基础魔法伤害属性
    }
    if (this[模式 + "毒"]) {
        this.毒 = this.基础毒 + this[模式 + "毒"];
    } else {
        this.毒 = this.基础毒;
    }
    if (this[模式 + "吸血"]) {
        this.吸血 = this.基础吸血 + this[模式 + "吸血"];
    } else {
        this.吸血 = this.基础吸血;
    }
    if (this[模式 + "击溃"]) {
        this.击溃 = this.基础击溃 + this[模式 + "击溃"];
    } else {
        this.击溃 = this.基础击溃;
    }
    if (this[模式 + "命中加成"]) {
        this.命中加成 = this.基础命中加成 + this[模式 + "命中加成"];
    } else {
        this.命中加成 = this.基础命中加成;
    }
    if (this[模式 + "暴击"]) {
        this.暴击 = this[模式 + "暴击"];
    } else {
        this.暴击 = undefined;
    }
    if (this[模式 + "斩杀"]) {
        this.斩杀 = this[模式 + "斩杀"];
    } else {
        this.斩杀 = 0;
    }
    this.命中率 = Math.max(this.基础命中率 * (1 + this.命中加成 / 100), DodgeHandler.HIT_RATE_LIMIT);
}

_root.主角函数.按键控制攻击模式 = function() {
    if (_root.当前玩家总数 == 1) {
        if (Key.isDown(_root.键1)) {
            攻击模式切换("空手");
        } else if (Key.isDown(_root.键2)) {
            攻击模式切换("兵器");
        } else if (Key.isDown(_root.键3)) {
            攻击模式切换("手枪");
        } else if (Key.isDown(_root.键4)) {
            攻击模式切换("长枪");
        } else if (Key.isDown(_root.键5)) {
            攻击模式切换("手雷");
        }
    }
    // if (Key.isDown(this.切换武器键))
    // {
    // 	循环切换攻击模式();
    // }
};

_root.主角函数.循环切换攻击模式 = function() {
/*
   if (循环切换攻击模式计数 == 1)
   {
   循环切换攻击模式计数++;
   攻击模式切换("空手");
   }
   else if (循环切换攻击模式计数 == 2)
   {
   循环切换攻击模式计数++;
   攻击模式切换("兵器");
   }
   else if (循环切换攻击模式计数 == 3)
   {
   循环切换攻击模式计数++;
   攻击模式切换("手枪");
   }
   else if (循环切换攻击模式计数 == 4)
   {
   循环切换攻击模式计数++;
   攻击模式切换("长枪");
   }
   else if (循环切换攻击模式计数 == 5)
   {
   循环切换攻击模式计数 = 1;
   if (_root.控制目标 == this._name)
   {
   攻击模式切换("手雷");
   }
   }
 */
};

_root.主角函数.随机切换攻击模式 = function() {
    var X轴距离 = Math.abs(this._x - _root.gameworld[攻击目标]._x);
    var 是否装备武器:Boolean = 长枪 || 刀 || 手枪 || 手枪2;
    var 切换攻击模式:Boolean = false;
    var 攻击模式随机数:Number = 0;
    var 当前时间 = _root.帧计时器.当前帧数;
    if (isNaN(上次思考时间)) {
        切换攻击模式 = true;

    } else if (当前时间 - 上次思考时间 > _root.佣兵思考时间间隔) {
        切换攻击模式 = _root.成功率(30);

    }
    //_root.发布调试消息(this._name + " " + (当前时间 - 上次思考时间) / 1000);                             
    if (是否装备武器 && 切换攻击模式) {
        上次思考时间 = 当前时间 + _root.随机整数(0, _root.佣兵思考时间间隔);

        var 近战判定:Number = Math.min(100 / X轴距离 * 100 / 3, 60);
        //越近越倾向于使用刀，越远越倾向于使用长枪，如果没有刀则将短枪视作刀
        if (_root.成功率(近战判定) && 刀 && 攻击模式 != "兵器") {
            攻击模式随机数 = 1;
        } else {
            攻击模式随机数 = _root.成功率(近战判定 + 10) ? 2 : 3;
        }
        switch (攻击模式随机数) {
            case 0:
                攻击模式切换("空手");
                break;
            case 1:
                攻击模式切换(刀 ? "兵器" : 手枪 || 手枪2 ? "手枪" : "长枪");
                break;
            case 2:
                攻击模式切换(手枪 || 手枪2 ? "手枪" : "长枪");
                break;
            case 3:
                攻击模式切换(长枪 ? "长枪" : "手枪");
                break;
                // 省略了 case 4 因为没有相关的逻辑
        }
    }
};

_root.主角函数.攻击呐喊 = function() {
    var arr:Array = 性别 === "女" ? 女_攻击呐喊_库 : 男_攻击呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.主角函数.中招呐喊 = function() {
    var arr:Array = 性别 === "女" ? 女_中招呐喊_库 : 男_中招呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.主角函数.击倒呐喊 = function() {
    var time = getTimer();
    if (time - this.上次击倒呐喊时间 < 300)
        return; // 击倒呐喊的最低间隔为300毫秒
    this.上次击倒呐喊时间 = time;
    var arr:Array = 性别 === "女" ? 女_击倒呐喊_库 : 男_击倒呐喊_库;
    _root.soundEffectManager.playSound(LinearCongruentialEngine.instance.getRandomArrayElement(arr));
};

_root.主角函数.跑步音效 = function(type) {
    if (this._name !== _root.控制目标)
        return;

    var 性别后缀 = (this.性别 == "女") ? "_female" : "";
    var 音效编号 = (type == 0) ? "" : "1";
    var 音效名 = "soundfootstep" + 性别后缀 + 音效编号 + ".wav";

    _root.soundEffectManager.playSound(音效名);
};


_root.主角函数.获取佣兵装备属性 = function(id) {
    var _loc4_ = undefined;
    if (_root.佣兵装备属性表[id] == undefined) {
        var _loc5_ = new Array();
        _loc5_[0] = _root.根据物品名查找属性(头部装备, 14);
        _loc5_[1] = _root.根据物品名查找属性(头部装备, 15);
        _loc5_[2] = this.性别 + _root.根据物品名查找属性(上装装备, 15) + "身体";
        _loc5_[3] = this.性别 + _root.根据物品名查找属性(上装装备, 15) + "上臂";
        _loc5_[4] = this.性别 + _root.根据物品名查找属性(上装装备, 15) + "左下臂";
        _loc5_[5] = this.性别 + _root.根据物品名查找属性(上装装备, 15) + "右下臂";
        _loc5_[6] = _root.根据物品名查找属性(手部装备, 15) + "左手";
        _loc5_[7] = _root.根据物品名查找属性(手部装备, 15) + "右手";
        _loc5_[8] = this.性别 + _root.根据物品名查找属性(下装装备, 15) + "屁股";
        _loc5_[9] = this.性别 + _root.根据物品名查找属性(下装装备, 15) + "左大腿";
        _loc5_[10] = this.性别 + _root.根据物品名查找属性(下装装备, 15) + "右大腿";
        _loc5_[11] = this.性别 + _root.根据物品名查找属性(下装装备, 15) + "小腿";
        _loc5_[12] = _root.根据物品名查找属性(脚部装备, 15);
        _loc5_[13] = _root.根据物品名查找属性(刀, 15);
        _loc5_[14] = _root.根据物品名查找属性(长枪, 15);
        _loc5_[15] = _root.根据物品名查找属性(手枪, 15);
        _loc5_[16] = _root.根据物品名查找属性(手枪2, 15);
        _loc5_[17] = _root.根据物品名查找属性(手雷, 15);
        _loc5_[18] = _root.根据物品名查找属性(头部装备, 8);
        _loc5_[19] = _root.根据物品名查找属性(上装装备, 8);
        _loc5_[20] = _root.根据物品名查找属性(手部装备, 8);
        _loc5_[21] = _root.根据物品名查找属性(下装装备, 8);
        _loc5_[22] = _root.根据物品名查找属性(脚部装备, 8);
        _root.佣兵装备属性表[id] = _loc5_;
        _loc4_ = _loc5_;
    } else {
        _loc4_ = _root.佣兵装备属性表[id];
    }
    return _loc4_;
};

_root.主角函数.初始化掉落物 = function() {
    // _root.发布消息("初始化掉落物:" + this._name, ObjectUtil.toString(this.长枪), ObjectUtil.toString(this.手枪), ObjectUtil.toString(this.手枪2), ObjectUtil.toString(this.刀));

    if (this.掉落物 != null || this.不掉装备) {
        // _root.发布消息(ObjectUtil.toString(this.掉落物));
        return;
    }
    if (this.是否为敌人 == false) {
        this.掉落物 = null;
        // _root.发布消息("非敌人不掉落物品:" + this._name,this.是否为敌人);
        return;
    }
    this.掉落物 = [];

    if (this.长枪) {
        this.掉落物.push({名字: this.长枪, 概率: 100});
    }
    if (this.手枪) {
        this.掉落物.push({名字: this.手枪, 概率: 100});
    }
    if (this.手枪2) {
        this.掉落物.push({名字: this.手枪2, 概率: 100});
    }
    if (this.刀) {
        this.掉落物.push({名字: this.刀, 概率: 100});
    }
};

_root.主角函数.计算经验值 = function() {
    this.掉落物判定();
    _root.经验值计算(最小经验值, 最大经验值, 等级, _root.最大等级);
    _root.主角是否升级(_root.等级, _root.经验值);
    this.已加经验值 = true;
};
_root.主角函数.播放二级动画 = function(一级帧名, 二级帧名) {
    this.man.gotoAndPlay(二级帧名);
    this.二级动画帧名 = 二级帧名;
    联机2015单纯状态改变(一级帧名);
    this.gotoAndStop(一级帧名);
    this.man.gotoAndPlay(二级帧名);
};

/*
   _root.主角函数.联机数据接收处理 = function(数据)
   {
   if (是否允许发送联机数据 == true)
   {

   this._x = Number(数据[1]);
   this._y = Number(数据[2]);
   Z轴坐标 = Number(数据[3]);
   左行 = Number(数据[4]);
   右行 = Number(数据[5]);
   上行 = Number(数据[6]);
   下行 = Number(数据[7]);
   播放二级动画(数据[8],Number(数据[9]));
   if (Number(数据[10]) != undefined)
   {
   hp = Number(数据[10]);
   }
   联机2015单纯方向改变(数据[11]);
   攻击模式 = 数据[12];

   }
   };
   _root.主角函数.联机2015发送角色数据 = function()
   {
   if (是否允许发送联机数据 == true)
   {
   var _loc3_ = "2~1~0~" + 用户ID + "," + Math.floor(this._x) + "," + Math.floor(this._y) + "," + Math.floor(Z轴坐标) + "," + 左行 + "," + 右行 + "," + 上行 + "," + 下行 + "," + 状态 + "," + this.man._currentframe + "," + hp + "," + 方向 + "," + 攻击模式;
   联机2015新发送数据 = _loc3_ + "~" + _loc3_.length;
   if (联机2015旧发送数据 != 联机2015新发送数据)
   {
   _root.scock2015.sendData(联机2015新发送数据);
   联机2015旧发送数据 = 联机2015新发送数据;
   }
   }

   };
 */


_root.主角函数.存储当前飞行状态 = function(type) {
    if (!type) {
        type = "状态改变";
    }
    if (this._name === _root.控制目标 && this.飞行浮空 && this.flyType == 1) {
        if (type === "切换武器" && _root.fly_isFly1 != true) {
            _root.fly_isFly1 = true;
            _root.fly_isFly2 = false;
            _root.fly_flySpeed1 = this.flySpeed;
            _root.fly_leftFlySpeed1 = this.leftFlySpeed;
            _root.fly_rightFlySpeed1 = this.rightFlySpeed;
            _root.fly_upFlySpeed1 = this.upFlySpeed;
            _root.fly_downFlySpeed1 = this.downFlySpeed;
            _root.fly_y1 = this._y;
            _root.fly_起始Y1 = this.起始Y;
            _root.fly_Z轴坐标1 = this.Z轴坐标;
                //_root.发布调试消息("开始触发的切换武器"+this.flySpeed+"/"+this.飞行浮空+"/"+this._y+"/"+this.起始Y+"/"+this.Z轴坐标+"/"+_root.fly_isFly1);
        }
        if (type === "状态改变" && _root.fly_isFly1 != true) {
            _root.fly_isFly2 = true;
            _root.fly_flySpeed2 = this.flySpeed;
            _root.fly_leftFlySpeed2 = this.leftFlySpeed;
            _root.fly_rightFlySpeed2 = this.rightFlySpeed;
            _root.fly_upFlySpeed2 = this.upFlySpeed;
            _root.fly_downFlySpeed2 = this.downFlySpeed;
            _root.fly_y2 = this._y;
            _root.fly_起始Y2 = this.起始Y;
            _root.fly_Z轴坐标2 = this.Z轴坐标;
                //_root.发布调试消息("开始触发的状态改变"+this.flySpeed+"/"+this.飞行浮空+"/"+this._y+"/"+this.起始Y+"/"+this.Z轴坐标+"/"+_root.fly_isFly2);
        }
    }
};


_root.主角函数.读取当前飞行状态 = function(type) {
    if (this._name !== _root.控制目标)
        return;
    if (!type) {
        type = "状态改变";
    }
    if (type === "切换武器" && _root.fly_isFly1 == true) {
        _root.fly_isFly1 = false;
        this.flySpeed = _root.fly_flySpeed1;
        this.leftFlySpeed = _root.fly_leftFlySpeed1;
        this.rightFlySpeed = _root.fly_rightFlySpeed1;
        this.upFlySpeed = _root.fly_upFlySpeed1;
        this.downFlySpeed = _root.fly_downFlySpeed1;
        this._y = _root.fly_y1;
        this.起始Y = _root.fly_起始Y1;
        this.Z轴坐标 = _root.fly_Z轴坐标1;
        this.飞行浮空 = true;
            //this.jetpack(this.flySpeed,1,this.leftFlySpeed,this.rightFlySpeed,this.upFlySpeed,this.downFlySpeed);
            //_root.发布调试消息("结束时触发的切换武器"+this.flySpeed+"/"+this.飞行浮空+"/"+this._y+"/"+this.起始Y+"/"+this.Z轴坐标+"/"+_root.fly_isFly1);
    } else if (type === "状态改变" && _root.fly_isFly2 == true && _root.fly_isFly1 != true) {
        _root.fly_isFly2 = false;
        this.flySpeed = _root.fly_flySpeed2;
        this.leftFlySpeed = _root.fly_leftFlySpeed2;
        this.rightFlySpeed = _root.fly_rightFlySpeed2;
        this.upFlySpeed = _root.fly_upFlySpeed2;
        this.downFlySpeed = _root.fly_downFlySpeed2;
        this._y = _root.fly_y2;
        this.起始Y = _root.fly_起始Y2;
        this.Z轴坐标 = _root.fly_Z轴坐标2;
        this.飞行浮空 = true;
            //this.jetpack(this.flySpeed,1,this.leftFlySpeed,this.rightFlySpeed,this.upFlySpeed,this.downFlySpeed);
            //_root.发布调试消息("结束时触发的状态改变"+this.flySpeed+"/"+this.飞行浮空+"/"+this._y+"/"+this.起始Y+"/"+this.Z轴坐标+"/"+_root.fly_isFly1);
    }
};




_root.主角函数.状态改变 = function(新状态名) {
    var self = this;
    //_root.发布调试消息("状态改变"+this.shadow._x+"/"+this.shadow._y+"/"+this.shadow._visible+"/"+this.状态+"/"+_root.是否阴影);
    if (self._name === _root.控制目标 && (新状态名 === self.攻击模式 + "攻击" || 新状态名 === self.攻击模式 + "站立")) {
        self.存储当前飞行状态("状态改变");
    }
    if (self.飞行浮空 && 新状态名.indexOf("跑") > -1)
        return;

    if (!self.攻击模式)
        self.攻击模式 = "空手";

    self.旧状态 = self.状态;

    // 状态别名/跳转帧映射：用于将“容器化实现”伪装为旧的逻辑状态名，降低全局特判改造成本
    // - 逻辑状态（self.状态）：供代码判定使用，例如 `状态 == "技能"`
    // - 跳转帧标签（gotoLabel）：实际 gotoAndStop 的帧名，例如 `"技能容器"`
    var logicalState:String = 新状态名;
    var gotoLabel:String = 新状态名;
    var prevGotoLabel:String = (self.__stateGotoLabel != undefined) ? self.__stateGotoLabel : self.旧状态;

    // 仅对已容器化的主角-男启用映射（避免影响其他单位/模板）
    if (self.兵种 === "主角-男") {

        // 容器化帧：逻辑状态维持不变，显示层跳转到“容器”帧
        if (logicalState === "技能" || logicalState === "战技" || logicalState === "兵器攻击容器") {
            gotoLabel = "容器";
        }
    }

    // 容器化man清理：attachMovie 动态创建的 man 不会随 gotoAndStop 自动销毁，需要手动移除
    // 通过 __isDynamicMan 标记识别（技能容器已在路由 attachMovie 时写入该标记）
    if (self.man && self.man.__isDynamicMan) {
        self.man.removeMovieClip();
        // _root.发布消息("移除旧的动态man");
    }

    // 记录本次实际跳转的帧标签，供下次状态切换时判断“从哪个显示帧离开”
    self.__stateGotoLabel = gotoLabel;

    // 逻辑状态变化 or 显示帧变化 时才执行跳转
    if (self.旧状态 != logicalState || prevGotoLabel != gotoLabel) {
        self.状态 = logicalState;
        // _root.发布消息(self.旧状态, self.状态);
        self.gotoAndStop(gotoLabel);
    }
};


_root.主角函数.UpdateBigState = function(newState) {
    bigState.push(newState);
    if (bigState.length > 6) {
        bigState.shift();
    }
};
_root.主角函数.UpdateState = function(newState) {
    状态改变(newState);
};
_root.主角函数.UpdateSmallState = function(newState) {
    smallState.push(newState);
    if (smallState.length > 11) {
        smallState.shift();
    }
};
_root.主角函数.UpdateBigSmallState = function(newBigState, newSmallState) {
    bigState.push(newBigState);
    if (bigState.length > 6) {
        bigState.shift();
    }
    smallState.push(newSmallState);
    if (smallState.length > 11) {
        smallState.shift();
    }
};
_root.主角函数.getBigState = function() {
    return bigState[bigState.length - 1];
};
_root.主角函数.getState = function() {
    return state[state.length - 1];
};
_root.主角函数.getSmallState = function() {
    return smallState[smallState.length - 1];
};
_root.主角函数.getAllState = function() {
    return [bigState[bigState.length - 1], state[state.length - 1], smallState[smallState.length - 1]];
};
_root.主角函数.getPastBigStates = function(numStates) {
    return bigState[bigState.length - 1 - numStates];
};
_root.主角函数.getPastStates = function(numStates) {
    return state[state.length - 1 - numStates];
};
_root.主角函数.getPastSmallStates = function(numStates) {
    return smallState[smallState.length - 1 - numStates];
};
_root.主角函数.按键检测 = function(按键, ai使用率) {
    if (_root.控制目标 === this._name) {
        return Key.isDown(按键);
    } else {
        if (isNaN(ai使用率)) {
            ai使用率 = 0.5;
        }
        return _root.成功率(ai使用率);
    }
};

//死亡检测
_root.主角函数.死亡检测 = function() {
    // 早期返回：单位未死亡
    if (this.hp > 0)
        return;

    // _root.服务器.发布服务器消息("角色 " + this._name + " 死亡");

    // 只在已经进入血腥死状态时才停止man动画
    // 避免在击倒/倒地状态时停止，导致后续切换到血腥死时无法播放动画
    if (this.状态 === "血腥死") {
        this.man.stop();
    }

    // 播放死亡音效
    if (已加经验值 != true) {
        击倒呐喊();
    }

    // 主角死亡特殊处理
    if (this._name === _root.控制目标) {
        _root.关卡结束界面.询问复活();
    }

    // 早期返回：已经处理过经验值
    if (已加经验值 === true)
        return;

    // === 处理佣兵死亡 ===
    if (用户ID != undefined && 已删除 != true) {
        var 是佣兵 = false;
        for (var i = 0; i < _root.同伴数; i++) {
            if (_root.同伴数据[i][2] == 用户ID) {
                是佣兵 = true;
                break;
            }
        }
        if (是佣兵) {
            _root.佣兵是否出战信息[佣兵是否出战信息id] = -1;
            _root.佣兵信息界面.排列佣兵图标();
            this.新版人物文字信息._visible = false;
            _root.add2map(this, 2);
            this.removeMovieClip();
            return;
        }
        已删除 = true;
    }

    // === 处理敌人死亡 ===
    if (UnitUtil.isEnemy(this)) {
        // 统计敌人数量
        if (是否为敌人 === true) {
            _root.敌人死亡计数++;
            _root.gameworld[产生源].僵尸型敌人场上实际人数--;
            _root.gameworld[产生源].僵尸型敌人总个数--;
        }
        // 计算经验值并清理
        计算经验值();
        this.新版人物文字信息._visible = false;
        _root.add2map(this, 2);
        this.removeMovieClip();
        return;
    }

    // === 处理友军死亡（非玩家角色） ===
    // 只有非玩家控制的友军单位才需要被删除
    if (this._name !== _root.控制目标) {
        this.新版人物文字信息._visible = false;
        _root.add2map(this, 2);
        this.removeMovieClip();
    }
}

//迁移刀口位置生成子弹
// Point对象静态复用 - 减少GC压力
_root.主角函数.刀口坐标缓存 = {x: 0, y: 0};
// 矩阵解算用缓存点
_root.主角函数.trans_p0 = {x: 0, y: 0};
_root.主角函数.trans_px = {x: 0, y: 0};
_root.主角函数.trans_py = {x: 0, y: 0};

_root.主角函数.刀口位置生成子弹 = function(子弹参数:Object):Void {
    var 主角函数:Object = _root.主角函数;
    var shoot:Function = _root.子弹区域shoot传递;
    var 装扮:MovieClip = this.man.刀.刀.装扮;
    var gameworld:MovieClip = _root.gameworld;

    // 基础属性每次调用构建一次（避免额外属性残留问题）
    var 子弹属性:Object = {
        发射者: this._name,
        声音: "",
        霰弹值: 1,
        子弹散射度: 0,
        发射效果: "",
        子弹种类: "近战子弹",
        子弹速度: 0,
        击中地图效果: "",
        击中后子弹的效果: "空手攻击火花",
        shootZ: this.Z轴坐标,
        子弹威力: 0,
        Z轴攻击范围: 10,
        击倒率: 10
    };

    // 参数覆盖只执行一次
    for (var key:String in 子弹参数) {
        子弹属性[key] = 子弹参数[key];
    }

    // 复用变量声明
    var node:MovieClip, x:Number, y:Number;
    var node1:MovieClip = 装扮.刀口位置1;
    var node2:MovieClip = 装扮.刀口位置2;
    var node3:MovieClip = 装扮.刀口位置3;
    var node4:MovieClip = 装扮.刀口位置4;

    // 检测刀口4判断走哪条路径
    if (node4._x == undefined) {
        // ==========================================
        // 3刀口快速路径 - 逐点变换
        // ==========================================
        var myPoint:Object = 主角函数.刀口坐标缓存;

        x = node1._x;
        if (x != undefined) {
            myPoint.x = x;
            myPoint.y = node1._y;
            装扮.localToGlobal(myPoint);
            gameworld.globalToLocal(myPoint);
            子弹属性.shootX = myPoint.x;
            子弹属性.shootY = myPoint.y;
            子弹属性.区域定位area = node1;
            shoot(子弹属性);
        }

        x = node2._x;
        if (x != undefined) {
            myPoint.x = x;
            myPoint.y = node2._y;
            装扮.localToGlobal(myPoint);
            gameworld.globalToLocal(myPoint);
            子弹属性.shootX = myPoint.x;
            子弹属性.shootY = myPoint.y;
            子弹属性.区域定位area = node2;
            shoot(子弹属性);
        }

        x = node3._x;
        if (x != undefined) {
            myPoint.x = x;
            myPoint.y = node3._y;
            装扮.localToGlobal(myPoint);
            gameworld.globalToLocal(myPoint);
            子弹属性.shootX = myPoint.x;
            子弹属性.shootY = myPoint.y;
            子弹属性.区域定位area = node3;
            shoot(子弹属性);
        }
    } else {
        // ==========================================
        // 4+刀口矩阵路径 - 批量变换优化
        // ==========================================
        var p:Object = 主角函数.trans_p0; p.x = 0; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var Tx:Number = p.x, Ty:Number = p.y;

        p = 主角函数.trans_px; p.x = 1; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var a:Number = p.x - Tx, b:Number = p.y - Ty;

        p = 主角函数.trans_py; p.x = 0; p.y = 1;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var c:Number = p.x - Tx, d:Number = p.y - Ty;

        // 刀口1
        x = node1._x;
        if (x != undefined) {
            y = node1._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node1;
            shoot(子弹属性);
        }

        // 刀口2
        x = node2._x;
        if (x != undefined) {
            y = node2._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node2;
            shoot(子弹属性);
        }

        // 刀口3
        x = node3._x;
        if (x != undefined) {
            y = node3._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node3;
            shoot(子弹属性);
        }

        // 刀口4 (已确认存在)
        x = node4._x; y = node4._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node4;
        shoot(子弹属性);

        // 刀口5
        node = 装扮.刀口位置5;
        x = node._x;
        if (x != undefined) {
            y = node._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node;
            shoot(子弹属性);
        }
    }
}

// 目前未被使用，留着以备其他资源swf需要使用
_root.主角函数.检查弹匣数量 = function(使用弹匣名称) {
    return org.flashNight.arki.item.ItemUtil.getTotal(使用弹匣名称);
}


var config:FragmentConfig = new FragmentConfig();

// 直接设置属性，避免loadFromObject的开销
config.gravity = 2.8;
config.fragmentCount = 15;
config.groundY = 330;
config.baseVelocityX = 26;
config.velocityXRange = 14;
config.rotationRange = 48;
config.bounce = 0.25;
config.collisionProbability = 0; // 无碰撞，性能最优
config.massScale = 400;

// 缓存配置对象
_root.主角函数._主角破碎配置缓存 = config;

_root.主角函数.破碎动画 = function(scope:MovieClip, fragmentPrefix:String):Number {

    // 最简验证
    if (!scope || !fragmentPrefix)
        return -1;

    var config:FragmentConfig = _root.主角函数._主角破碎配置缓存;
    // config.groundY = scope._parent._y;

    // 直接使用缓存的配置
    return FragmentAnimator.startAnimation(scope, fragmentPrefix, config);
};

_root.主角函数.跳转到招式 = function(target:MovieClip, key:String, countMax:Number) {
    var frame:String = LinearCongruentialEngine.getInstance().randomKey(key, countMax);
    // frame = "a7";
    target.gotoAndPlay(frame);
}


//释放技能与战技
_root.主角函数.释放技能 = function(技能名, 消耗mp, 技能按键值) {
    // 防护：技能名为空时直接返回，避免空技能栏触发导致异常
    if (!技能名 || 技能名 == "" || 技能名 == "空")
        return false;
    if (this.hp <= 0 || this.mp < 消耗mp)
        return false;

    var 技能等级 = Number(_root.根据技能名查找主角技能等级(技能名));
    if (技能等级 <= 0 || isNaN(技能等级) || 技能等级 > 10)
        技能等级 = 1;
    //用函数托管技能的释放条件
    var 释放条件函数 = _root.技能函数.释放条件[技能名] ? _root.技能函数.释放条件[技能名] : _root.技能函数.释放条件.默认;
    var 释放许可 = 释放条件函数.apply(this);
    if (释放许可) {
        this.temp_y = (this.浮空 || this.倒地) ? this._y : 0; //记录临时y轴
        this.mp -= 消耗mp;
        //用函数托管技能的释放行为，配合buff系统实装后部分不需要进技能动画即可释放的技能
        var 释放行为函数 = _root.技能函数.释放行为[技能名] ? _root.技能函数.释放行为[技能名] : _root.技能函数.释放行为.默认;
        释放行为函数.apply(this, [技能名, 技能等级]);
        this.技能按键值 = 技能按键值;
        return true;
    }
    return false;
}

_root.主角函数.释放主动战技 = function() {
    var 当前战技 = this.主动战技[攻击模式];
    if (!当前战技 || !当前战技.战技函数)
        return false;

    var 战技函数 = 当前战技.战技函数;
    if (!战技函数.释放许可判定 || !战技函数.释放)
        return false;

    if (this.hp <= 当前战技.消耗hp || this.mp < 当前战技.消耗mp)
        return false;
    if (战技函数.释放许可判定(this)) {
        if (this.浮空) {
            this.temp_y = this._y;
        } else {
            this.temp_y = 0;
        }
        this.hp -= 当前战技.消耗hp;
        this.mp -= 当前战技.消耗mp;
        战技函数.释放(this);
        this.dispatcher.publish("WeaponSkill", 攻击模式);
        return true;
    }
    return false;
}

_root.主角函数.装载主动战技 = function(战技信息, 攻击模式) {
    if (!战技信息.skillname) {
        this.主动战技[攻击模式] = null;
        return;
    }
    var 当前战技 = {};
    当前战技.名字 = 战技信息.skillname;
    当前战技.冷却时间 = 战技信息.cd > 100 ? Number(战技信息.cd) : 100; //冷却时间的下限为0.1秒
    if (战技信息.hp.indexOf("%") === 战技信息.hp.length - 1 && 战技信息.hp.split("%")[0] > 0) {
        var 消耗百分比 = Number(战技信息.hp.split("%")[0]);
        当前战技.消耗hp = Math.floor(消耗百分比 * this.hp满血值 * 0.01);
    } else {
        当前战技.消耗hp = 战技信息.hp > 0 ? Number(战技信息.hp) : 0;
    }
    if (战技信息.mp.indexOf("%") === 战技信息.mp.length - 1 && 战技信息.mp.split("%")[0] > 0) {
        var 消耗百分比 = Number(战技信息.mp.split("%")[0]);
        当前战技.消耗mp = Math.floor(消耗百分比 * this.mp满血值 * 0.01);
    } else {
        当前战技.消耗mp = 战技信息.mp > 0 ? Number(战技信息.mp) : 0;
    }
    // 当前战技.伤害参数 = 战技信息.damage > 0 ? Number(战技信息.damage) : 0;
    var 战技函数表 = _root.主动战技函数[攻击模式];
    if (!战技函数表 || !战技函数表[战技信息.skillname]) {
        this.主动战技[攻击模式] = null;
        return;
    }
    当前战技.战技函数 = 战技函数表[战技信息.skillname];
    this.主动战技[攻击模式] = 当前战技;
    if (当前战技.战技函数.初始化)
        当前战技.战技函数.初始化(this);
}
_root.主角函数.读取基础被动效果 = function() {
    //独行者
    if (this.被动技能.独行者 && this.被动技能.独行者.启用) {
        var 是否独行 = true;
        //若禁用同伴词条开启则无需额外判定，否则遍历佣兵与宠物出战情况
        if (!(!_root.限制系统.limitLevel || _root.难度等级 >= _root.限制系统.limitLevel) || !_root.限制系统.DisableCompanion) {
            for (var i = 0; i < _root.宠物信息.length; i++) {
                var 当前宠物信息 = _root.宠物信息[i];
                if (当前宠物信息[4] == 1) {
                    是否独行 = false;
                    break;
                }
            }
            for (var i = 0; i < _root.佣兵个数限制; i++) {
                var 同伴信息 = _root.同伴数据[i];
                if (_root.佣兵是否出战信息[i] == 1 && 同伴信息[1] != undefined && 同伴信息[1] != "undefined") {
                    是否独行 = false;
                    break;
                }
            }
        }
        if (是否独行) {
            if (this.hp == this.hp满血值)
                this.hp += this.被动技能.独行者.等级 * 50;
            this.hp满血值 += this.被动技能.独行者.等级 * 50;
            if (this.mp == this.mp满血值)
                this.mp += this.被动技能.独行者.等级 * 50;
            this.mp满血值 += this.被动技能.独行者.等级 * 50;
            this.伤害加成 += this.被动技能.独行者.等级 * 10;
            this.防御力 += this.被动技能.独行者.等级 * 30;
        }
    }
}

_root.主角函数.读取被动效果 = function() {
    if (this.被动技能.移动射击 && this.被动技能.移动射击.启用) {
        this.移动射击 = true;
    } else {
        this.移动射击 = false;
    }
    if (this.被动技能.枪械师 && this.被动技能.枪械师.启用 && this.被动技能.枪械师.等级) {
        this.buff.赋值("手枪威力", "加算", this.被动技能.枪械师.等级 * 5, "增益");
        this.buff.赋值("手枪2威力", "加算", this.被动技能.枪械师.等级 * 5, "增益");
        if (this.变形手枪) {
            this.变形手枪.切换武器形态为当前模式();
        }
    } else {
        this.buff.删除("手枪威力", "加算");
        this.buff.删除("手枪2威力", "加算");
        if (this.变形手枪) {
            this.变形手枪.切换武器形态为当前模式();
        }
    }
    if (this.man.初始化长枪射击函数) {
        this.man.初始化长枪射击函数();
    } else if (this.man.初始化手枪射击函数) {
        this.man.初始化手枪射击函数();
    } else if (this.man.初始化手枪2射击函数) {
        this.man.初始化手枪2射击函数();
    } else if (this.man.初始化双枪射击函数) {
        this.man.初始化双枪射击函数();
    }
}

_root.主角函数.按距离索敌 = function(距离, 是否强行重新索敌, 优先索敌属性, 优先索敌排序) {
    var 当前攻击目标 = _root.gameworld[this.攻击目标];
    var 距离X = Math.abs(this._x - 当前攻击目标._x);
    var 距离Z = Math.abs(this.Z轴坐标 - 当前攻击目标.Z轴坐标);
    var 实际距离 = Math.sqrt(距离X * 距离X + 距离Z * 距离Z);
    var 索敌属性 = 优先索敌属性 ? 优先索敌属性 : "距离";
    var 索敌排序 = 优先索敌排序 ? 优先索敌排序 : "顺序";
    var 索敌距离 = 距离 ? 距离 : Math.sqrt(this.x轴攻击范围 * this.x轴攻击范围 + this.y轴攻击范围 * this.y轴攻击范围);
    if (当前攻击目标.hp > 0 && 实际距离 <= 索敌距离 && !是否强行重新索敌) {
        this.索敌目标列表 = [{敌人: 当前攻击目标, 距离: 实际距离, 血量: 当前攻击目标.hp}];
        var 敌人列表 = _root.帧计时器.获取敌人缓存(this, 30);
        for (i = 0; i < 敌人列表.length; i++) {
            var 敌人 = 敌人列表[i];
            if (敌人.hp > 0 && 敌人 != 当前攻击目标) {
                距离X = Math.abs(this._x - 敌人._x);
                距离Z = Math.abs(this.Z轴坐标 - 敌人.Z轴坐标);
                实际距离 = Math.sqrt(距离X * 距离X + 距离Z * 距离Z);
                if (实际距离 <= 索敌距离) {
                    this.索敌目标列表.push({敌人: 敌人, 距离: 实际距离, 血量: 敌人.hp});
                }
            }
        }
        return 当前攻击目标;
    } else {
        var 敌人列表 = _root.帧计时器.获取敌人缓存(this, 30);
        this.索敌目标列表 = [];
        for (i = 0; i < 敌人列表.length; i++) {
            var 敌人 = 敌人列表[i];
            if (敌人.hp > 0) {
                距离X = Math.abs(this._x - 敌人._x);
                距离Z = Math.abs(this.Z轴坐标 - 敌人.Z轴坐标);
                实际距离 = Math.sqrt(距离X * 距离X + 距离Z * 距离Z);
                if (实际距离 <= 索敌距离) {
                    this.索敌目标列表.push({敌人: 敌人, 距离: 实际距离, 血量: 敌人.hp});
                }
            }
        }
        if (this.索敌目标列表.length > 0) {
            this.索敌目标列表 = _root.数组内对象冒泡排序(this.索敌目标列表, 索敌属性);
            if (索敌排序 != "顺序") {
                if (索敌排序 == "随机") {
                    // 随机选取一个目标
                    var 随机索引:Number = Math.floor(Math.random() * this.索敌目标列表.length);
                    敌人 = this.索敌目标列表[随机索引].敌人;
                } else {
                    this.索敌目标列表 = _root.反转数组(this.索敌目标列表);
                    敌人 = this.索敌目标列表[0].敌人;
                }
            } else {
                敌人 = this.索敌目标列表[0].敌人;
            }
            this.dispatcher.publish("aggroSet", this, 敌人);
            return 敌人;
        } else {
            return false;
        }
    }
    return false;
}

// 冒泡排序函数
_root.数组内对象冒泡排序 = function(arr, 属性) {
    var arr = arr;
    var n = arr.length;
    for (var i = 0; i < n - 1; i++) {
        for (var j = 0; j < n - i - 1; j++) {
            if (arr[j][属性] > arr[j + 1][属性]) {
                // 交换位置
                var temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
    return arr;
}

_root.反转数组 = function(arr) {
    var arr = arr;
    var 开始 = 0;
    var 结束 = arr.length - 1;

    while (开始 < 结束) {
        // 交换 arr[开始] 和 arr[结束] 的值
        var temp = arr[开始];
        arr[开始] = arr[结束];
        arr[结束] = temp;

        // 更新索引
        开始++;
        结束--;
    }
    return arr;
}

//初始化玩家模板
_root.初始化玩家模板 = function() {
    // this.循环切换攻击模式 = _root.主角函数.循环切换攻击模式;
    this.随机切换攻击模式 = _root.主角函数.随机切换攻击模式;
    this.攻击呐喊 = _root.主角函数.攻击呐喊;
    this.中招呐喊 = _root.主角函数.中招呐喊;
    this.击倒呐喊 = _root.主角函数.击倒呐喊;
    this.跑步音效 = _root.主角函数.跑步音效;
    this.获取佣兵装备属性 = _root.主角函数.获取佣兵装备属性;
    this.初始化掉落物 = _root.主角函数.初始化掉落物;
    //人形怪与敌人直接使用同一套掉落函数
    this.掉落物判定 = _root.敌人函数.掉落物判定;
    this.掉落物品 = _root.敌人函数.掉落物品;

    //

    this.计算经验值 = _root.主角函数.计算经验值;
    this.播放二级动画 = _root.主角函数.播放二级动画;
    this.联机数据接收处理 = _root.主角函数.联机数据接收处理;
    // this.联机2015发送角色数据 = _root.主角函数.联机2015发送角色数据;
    // this.联机2015单纯方向改变 = _root.主角函数.联机2015单纯方向改变;
    // this.状态改变新状态机实装前使用 = _root.主角函数.状态改变新状态机实装前使用;
    // this.联机2015单纯状态改变 = _root.主角函数.联机2015单纯状态改变;

    //

    this.动画完毕 = _root.主角函数.动画完毕;

    //

    this.硬直 = _root.主角函数.硬直;

    this.移动钝感硬直 = _root.主角函数.移动钝感硬直;


    //
    this.攻击模式切换 = _root.主角函数.攻击模式切换;
    this.按键控制攻击模式 = _root.主角函数.按键控制攻击模式;
    this.根据模式重新读取武器加成 = _root.主角函数.根据模式重新读取武器加成;
    this.跳 = _root.主角函数.跳;


    //
    this.冲击 = _root.主角函数.冲击;
    this.攻击 = _root.主角函数.攻击;
    this.方向改变 = _root.主角函数.方向改变;
    this.移动 = _root.主角函数.移动;
    this.攻击时移动 = _root.主角函数.攻击时移动;
    this.跳跃上下移动 = _root.主角函数.跳跃上下移动;
    this.被击移动 = _root.主角函数.被击移动;
    this.强制移动 = _root.主角函数.强制移动;
    this.拾取 = _root.主角函数.拾取;
    this.非主角外观刷新 = _root.主角函数.非主角外观刷新;
    this.状态改变 = _root.主角函数.状态改变;
    this.UpdateBigState = _root.主角函数.UpdateBigState;
    this.UpdateState = _root.主角函数.UpdateState;
    this.UpdateSmallState = _root.主角函数.UpdateSmallState;
    this.UpdateBigSmallState = _root.主角函数.UpdateBigSmallState;
    this.getBigState = _root.主角函数.getBigState;
    this.getState = _root.主角函数.getState;
    this.getSmallState = _root.主角函数.getSmallState;
    this.getAllState = _root.主角函数.getAllState;
    this.getPastBigStates = _root.主角函数.getPastBigStates;
    this.getPastStates = _root.主角函数.getPastStates;
    this.getPastSmallStates = _root.主角函数.getPastSmallStates;
    this.人物暂停 = _root.主角函数.人物暂停;
    this.获取键值 = _root.主角函数.获取键值;
    this.根据等级初始数值 = _root.主角函数.根据等级初始数值;
    this.行走 = _root.控制目标 === this._name ? _root.主角函数.行走_玩家 : _root.主角函数.行走;
    this.初始化可用技能 = _root.主角函数.初始化可用技能;
    this.存储当前飞行状态 = _root.主角函数.存储当前飞行状态;
    this.读取当前飞行状态 = _root.主角函数.读取当前飞行状态;
    this.按键检测 = _root.主角函数.按键检测;

    this.死亡检测 = _root.主角函数.死亡检测;

    this.刀口位置生成子弹 = _root.主角函数.刀口位置生成子弹;

    this.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
    this.手枪射击 = WeaponFireCore.PISTOL_SHOOT;
    this.手枪2射击 = WeaponFireCore.PISTOL2_SHOOT;
    // this.检查弹匣数量 = _root.主角函数.检查弹匣数量;

    this.释放技能 = _root.主角函数.释放技能;
    this.释放主动战技 = _root.主角函数.释放主动战技;
    this.装载主动战技 = _root.主角函数.装载主动战技;
    this.装载生命周期函数 = _root.主角函数.装载生命周期函数;
    this.完成生命周期函数装载 = _root.主角函数.完成生命周期函数装载;
    this.读取被动效果 = _root.主角函数.读取被动效果;
    this.读取基础被动效果 = _root.主角函数.读取基础被动效果;
    this.按距离索敌 = _root.主角函数.按距离索敌;
    this.jetpack = _root.jetpack;
    this.jetpackCheck = _root.jetpackCheck;

    最小经验值 = 16;
    最大经验值 = 134;
    hp_min = 200;
    hp_max = 1000;
    mp_min = 100;
    mp_max = 900;
    速度_min = 40;
    速度_max = 60;
    空手攻击力_min = 10;
    空手攻击力_max = 150;
    被击硬直度_min = 1000;
    被击硬直度_max = 200;
    躲闪率_min = 10;
    躲闪率_max = 2;
    基本防御力_min = 10;
    基本防御力_max = 400;
    内力 = 65 + Math.floor(等级 * 0.56);
    if (!this.装备防御力)
        this.装备防御力 = 0;

    //新加属性
    重量 = 0;
    基础命中率 = 10;
    命中率 = 基础命中率;
    韧性系数 = 1;
    血包数量 = 3;
    血包使用间隔 = 8 * _root.帧计时器.帧率;
    血包恢复比例 = 33;
    上次使用血包时间 = _root.帧计时器.当前帧数;

    不掉钱 = 不掉钱 ? true : false;
    不掉装备 = 不掉装备 ? true : false;
    主动战技 = {空手: null, 兵器: null, 长枪: null};

    操控编号 = _root.获取操控编号(this._name);
    if (操控编号 != -1) {
        获取键值();
    }

    if (this.hp满血值装备加层 == undefined) {
        this.hp满血值装备加层 = 0;
    }
    if (mp满血值装备加层 == undefined) {
        mp满血值装备加层 = 0;
    }

    //_root.发布调试消息(重量 + " " + 命中率 + " " + 韧性系数 + " " + 躲闪率);
    //_root.发布调试消息(_root.gameworld[this._name].名字 + " hp:" + _root.gameworld[this._name].hp满血值 + "/" + _root.gameworld[this._name].hp + " mp:" + _root.gameworld[this._name].mp满血值 + "/" + _root.gameworld[this._name].mp + " atk" + _root.gameworld[this._name].伤害加成);
    dispatcher.publish("aggroClear", this);
    x轴攻击范围 = 100;
    y轴攻击范围 = 20;
    x轴保持距离 = 50;
    攻击模式 = 攻击模式 ? 攻击模式 : "空手";
    状态 = 攻击模式 + "站立";
    方向 = 方向 ? 方向 : "右";
    格斗架势 = false;
    击中效果 = 击中效果 ? 击中效果 : "飙血";
    Z轴坐标 = this._y;
    浮空 = false;
    倒地 = false;
    硬直中 = false;
    强制换弹夹 = false;

    // if (!长枪射击次数)
    //     长枪射击次数 = new Object();
    // if (!手枪射击次数)
    //     手枪射击次数 = new Object();
    // if (!手枪2射击次数)
    //     手枪2射击次数 = new Object();
    手雷射击次数 = 0;
    // 循环切换攻击模式计数 = 1;
    // 单发枪射击速度 = 1000;
    // 单发枪射击速度_2 = 1000;
    // 单发枪计时_时间结束 = true;
    // 单发枪计时_时间结束_2 = true;
    主手射击中 = false;
    副手射击中 = false;
    移动射击 = false;
    上下移动射击 = false;
    移动射击倒退 = false;

    男_攻击呐喊_库 = ["11_kda_a_1-22.wav", "23_kda_sy_1-22.wav", "01_kyn_a_2-22.wav", "25_kyo_sb-22.wav", "20_kyn_h_9-22.wav"];
    女_攻击呐喊_库 = ["01_kin_a_1-22.wav", "02_kin_a_2-22.wav", "03_kin_a_3-22.wav", "19_kin_nage-22.wav"];
    男_中招呐喊_库 = ["男-主角-0.wav", "男-主角-1.wav", "男-主角-2.wav", "主角中招0.wav", "主角中招1.wav", "主角中招2.wav"];
    女_中招呐喊_库 = ["women_hit0.wav", "women_hit1.wav", "women_hit2.wav", "women_hit3.wav", "women_hit4.wav", "women_hit5.wav", "women_hit6.wav"];
    男_击倒呐喊_库 = ["08_kyo_d_f-22.wav", "07_ben_d_f-22.wav", "06_cla_d_f-22.wav", "04_and_df1-22.wav"];
    女_击倒呐喊_库 = ["women_die1.wav", "women_die2.wav", "women_die3.wav", "women_die4.wav", "women_die5.wav"];
    bigState = [];
    state = [];
    smallState = [];
    //allStage = [bigState, state, smallState];//暂时取消
    //以下为ffdec时期的注释方式
//	useBigState = ["技能中", "技能结束", "普攻中", "普攻结束"];
//	useSmallStateSkill = ["闪现中", "闪现结束", "六连中", "六连结束", "踩人中", "踩人结束", "技能结束"];
//	useSmallStateWeapon = ["兵器一段前", "兵器一段中", "兵器二段中", "兵器三段中", "兵器四段中", "兵器五段中", "兵器五段结束", "兵器普攻结束", "长枪攻击前", "长枪攻击中", "长枪攻击结束"];
//	useStateWeapon = ["空手", "兵器", "手枪", "手枪2", "双枪", "长枪", "手雷"];
//	useStateWeaponAction = ["站立", "行走", "攻击", "跑", "冲击", "跳", "拾取", "躲闪"];
//	useStateOtherType = ["技能", "挂机", "被击", "击倒", "被投", "血腥死"];

    // if (!_root.玩家与佣兵区分装扮刷新 || _root.控制目标 === this._name)

    身高转换值 = UnitUtil.getHeightPercentage(this.身高);
    this._xscale = 身高转换值;
    this._yscale = 身高转换值;
    myxscale = this._xscale;
    this.swapDepths(this._y + random(10) - 5);

    被动技能 = {};
    if (_root.控制目标 != this._name) {
        初始化可用技能();
    } else {
        被动技能 = _root.主角被动技能;
    }

    this.buff = new 主角模板数值buff(this);

    //初始化完毕
    this.初始化掉落物();
    根据等级初始数值(等级);
    //上一个函数已经刷新人物装扮了

    this.读取被动效果();
    if (_root.控制目标 === this._name) {
        _root.玩家信息界面.刷新攻击模式(this.攻击模式);
    }

    方向改变(方向);
    gotoAndStop(状态);
};



_root.初始化佣兵NPC模板 = function() {
    this.获取佣兵装备属性 = _root.主角函数.获取佣兵装备属性;

    this.动画完毕 = _root.主角函数.动画完毕;
    //
    this.方向改变 = _root.主角函数.方向改变;
    this.移动 = _root.主角函数.移动;
    // this.跳跃上下移动 = _root.主角函数.跳跃上下移动;
    // this.被击移动 = _root.主角函数.被击移动;
    this.强制移动 = _root.主角函数.强制移动;
    this.非主角外观刷新 = _root.主角函数.非主角外观刷新;
    this.状态改变 = _root.主角函数.状态改变;

    this.根据等级初始数值 = _root.主角函数.根据等级初始数值;
    this.行走 = _root.主角函数.行走;

    // this.死亡检测 = _root.主角函数.死亡检测;

    this.装载生命周期函数 = _root.主角函数.装载生命周期函数;
    this.完成生命周期函数装载 = _root.主角函数.完成生命周期函数装载;

    this.删除可雇用单位 = function() {
        this.removeMovieClip();
    }

    最小经验值 = 1;
    最大经验值 = 1;
    hp_min = 2000000;
    hp_max = 10000000;
    mp_min = 100;
    mp_max = 600;
    速度_min = 40;
    速度_max = 60;
    空手攻击力_min = 10;
    空手攻击力_max = 150;
    被击硬直度_min = 1000;
    被击硬直度_max = 200;
    躲闪率_min = 10;
    躲闪率_max = 2;
    基本防御力_min = 1000;
    基本防御力_max = 4000;
    内力 = 65 + Math.floor(等级 * 0.56);
    if (!this.装备防御力)
        this.装备防御力 = 0;

    //新加属性
    重量 = 0;
    基础命中率 = 10;
    命中率 = 基础命中率;
    韧性系数 = 1;

    操控编号 = -1;

    状态 = 攻击模式 + "站立";
    方向 = 方向 ? 方向 : "右";
    击中效果 = 击中效果 ? 击中效果 : "飙血";
    Z轴坐标 = this._y;
    浮空 = false;
    倒地 = false;
    硬直中 = false;

    身高转换值 = UnitUtil.getHeightPercentage(this.身高);
    this._xscale = 身高转换值;
    this._yscale = 身高转换值;
    myxscale = this._xscale;
    this.swapDepths(this._y + random(10) - 5);

    //状态机类型为佣兵NPC
    this.unitAIType = "Mecenary";

    根据等级初始数值(等级);
    方向改变(方向);
    gotoAndStop(状态);
};
