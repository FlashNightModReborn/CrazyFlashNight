﻿import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.item.*;

_root.使用药剂 = function(物品名) {
    var 控制对象 = TargetCacheManager.findHero();
    if (控制对象.hp <= 0)
        return;

    var 炼金等级 = 0;
    if (_root.主角被动技能.炼金 && _root.主角被动技能.炼金.启用) {
        炼金等级 = _root.主角被动技能.炼金.等级;
    }

    var itemData = _root.getItemData(物品名);
    var drugData = itemData.data;
    
    switch(drugData.friend) {
        case "单体":
            var hp增加值 = drugData.affecthp + Math.min(Math.floor(drugData.affecthp * 炼金等级 * 0.05), 500);
            if (hp增加值 + 控制对象.hp <= Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp += hp增加值;
            } else if (控制对象.hp < Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp = Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03));
            }
            _root.玩家信息界面.刷新hp显示();
            var mp增加值 = drugData.affectmp + Math.min(Math.ceil(drugData.affectmp * 炼金等级 * 0.1), 1000);
            if (mp增加值 + 控制对象.mp <= 控制对象.mp满血值) {
                控制对象.mp += mp增加值;
            } else {
                控制对象.mp = 控制对象.mp满血值;
            }
            _root.玩家信息界面.刷新mp显示();
            EffectSystem.Effect("药剂动画", 控制对象._x, 控制对象._y, 100);
            break;
            
        case "群体":
            _root.佣兵集体加血(drugData.affecthp + Math.min(Math.floor(drugData.affecthp * 炼金等级 * 0.05), 500));
            break;
            
        case "淬毒":
            var 淬毒量 = drugData.poison;
            if (淬毒量) {
                控制对象.淬毒 = 淬毒量 + Math.min(Math.floor(淬毒量 * 炼金等级 * 0.07), 2000);
            }
            EffectSystem.Effect("淬毒动画", 控制对象._x, 控制对象._y, 100);
            break;
            
        case "净化":
            var 净化量 = Number(drugData.clean) + Math.min(Math.floor(5 * 炼金等级), 50);
            if (净化量) {
                if (_root.地形伤害系数) {
                    _root.地形伤害系数 = 0.09 + (_root.地形伤害系数 - 0.09) * 20 / 净化量;
                }
                控制对象.麻痹值 = -10 * 净化量;
            }
            var debuff清除概率 = 净化量 * 2;
            EffectSystem.Effect("净化动画", 控制对象._x, 控制对象._y, 100);
            break;

        case "鸡尾酒":
            var hp增加值 = drugData.affecthp + Math.min(Math.floor(drugData.affecthp * 炼金等级 * 0.05), 500);
            if (hp增加值 + 控制对象.hp <= Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp += hp增加值;
            } else if (控制对象.hp < Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp = Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03));
            }
            _root.玩家信息界面.刷新hp显示();
            var mp增加值 = drugData.affectmp + Math.min(Math.ceil(drugData.affectmp * 炼金等级 * 0.1), 1000);
            if (mp增加值 + 控制对象.mp <= 控制对象.mp满血值) {
                控制对象.mp += mp增加值;
            } else {
                控制对象.mp = 控制对象.mp满血值;
            }
            _root.玩家信息界面.刷新mp显示();
            var 淬毒量 = drugData.poison;
            if (淬毒量) {
                控制对象.淬毒 = 淬毒量 + Math.min(Math.floor(淬毒量 * 炼金等级 * 0.07), 2000);
            }
            
            var 净化量 = 30 + Math.min(Math.floor(5 * 炼金等级), 50);
            if (_root.地形伤害系数) {
                _root.地形伤害系数 = 0.09 + (_root.地形伤害系数 - 0.09) * 20 / 净化量;
            }
            控制对象.麻痹值 = -10 * 净化量;

            var flag:Boolean = ItemUtil.singleAcquire("幻层残响",1);
            _root.发布消息(flag, "酒精渗透神经的瞬间，区块链中流窜的数据碎片涌入了你的意识...");
            EffectSystem.Effect("药剂动画", 控制对象._x, 控制对象._y, 100);
            break;
    }
}
