/**
 * 药剂使用系统
 *
 * 重构说明:
 * - 新系统优先使用 XML 中的 effects 数组（词条系统）
 * - 无 effects 时回退到旧的 friend 分支逻辑（兼容期）
 * - 保持 _root.使用药剂(物品名) 接口不变，FLA快捷栏无需改动
 *
 * @author FlashNight
 * @version 2.0
 */
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.drug.*;

/**
 * 使用药剂（主入口）
 *
 * @param 物品名 String 药剂物品名称
 */
_root.使用药剂 = function(物品名:String):Void {
    var 控制对象:Object = TargetCacheManager.findHero();
    if (!控制对象 || 控制对象.hp <= 0) {
        return;
    }

    var itemData:Object = _root.getItemData(物品名);
    if (!itemData || !itemData.data) {
        trace("[使用药剂] 无效的物品数据: " + 物品名);
        return;
    }

    var drugData:Object = itemData.data;

    // 优先使用新词条系统
    if (drugData.effects && drugData.effects.length > 0) {
        // 初始化注册表（首次调用时自动注册所有词条）
        DrugEffectRegistry.initialize();

        // 创建执行上下文
        var context:DrugContext = DrugContext.create(物品名);
        if (!context.isValid()) {
            trace("[使用药剂] 上下文无效");
            return;
        }

        // 执行所有词条
        var successCount:Number = DrugEffectRegistry.executeAll(drugData.effects, context);
        // trace("[使用药剂] 执行完成，成功词条数: " + successCount);
    } else {
        // 回退到旧逻辑（兼容期）
        _root.使用药剂_旧逻辑(控制对象, drugData);
    }
};

/**
 * 使用药剂（旧逻辑，兼容期保留）
 *
 * @param 控制对象 Object 目标单位
 * @param drugData Object 药剂数据
 */
_root.使用药剂_旧逻辑 = function(控制对象:Object, drugData:Object):Void {
    var 炼金等级:Number = 0;
    if (_root.主角被动技能.炼金 && _root.主角被动技能.炼金.启用) {
        炼金等级 = _root.主角被动技能.炼金.等级;
    }

    switch (drugData.friend) {
        case "单体":
            var hp增加值:Number = drugData.affecthp + Math.min(Math.floor(drugData.affecthp * 炼金等级 * 0.05), 500);
            if (hp增加值 + 控制对象.hp <= Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp += hp增加值;
            } else if (控制对象.hp < Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp = Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03));
            }
            _root.玩家信息界面.刷新hp显示();

            var mp增加值:Number = drugData.affectmp + Math.min(Math.ceil(drugData.affectmp * 炼金等级 * 0.1), 1000);
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
            var 淬毒量:Number = drugData.poison;
            if (淬毒量) {
                控制对象.淬毒 = 淬毒量 + Math.min(Math.floor(淬毒量 * 炼金等级 * 0.07), 2000);
            }
            EffectSystem.Effect("淬毒动画", 控制对象._x, 控制对象._y, 100);
            break;

        case "净化":
            var 净化量:Number = Number(drugData.clean) + Math.min(Math.floor(5 * 炼金等级), 50);
            if (净化量) {
                if (_root.地形伤害系数) {
                    _root.地形伤害系数 = 0.09 + (_root.地形伤害系数 - 0.09) * 20 / 净化量;
                }
                控制对象.麻痹值 = -10 * 净化量;
            }
            var debuff清除概率:Number = 净化量 * 2;
            EffectSystem.Effect("净化动画", 控制对象._x, 控制对象._y, 100);
            break;

        case "鸡尾酒":
            var hp增加值2:Number = drugData.affecthp + Math.min(Math.floor(drugData.affecthp * 炼金等级 * 0.05), 500);
            if (hp增加值2 + 控制对象.hp <= Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp += hp增加值2;
            } else if (控制对象.hp < Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03))) {
                控制对象.hp = Math.ceil(控制对象.hp满血值 * (1 + 炼金等级 * 0.03));
            }
            _root.玩家信息界面.刷新hp显示();

            var mp增加值2:Number = drugData.affectmp + Math.min(Math.ceil(drugData.affectmp * 炼金等级 * 0.1), 1000);
            if (mp增加值2 + 控制对象.mp <= 控制对象.mp满血值) {
                控制对象.mp += mp增加值2;
            } else {
                控制对象.mp = 控制对象.mp满血值;
            }
            _root.玩家信息界面.刷新mp显示();

            var 淬毒量2:Number = drugData.poison;
            if (淬毒量2) {
                控制对象.淬毒 = 淬毒量2 + Math.min(Math.floor(淬毒量2 * 炼金等级 * 0.07), 2000);
            }

            var 净化量2:Number = 30 + Math.min(Math.floor(5 * 炼金等级), 50);
            if (_root.地形伤害系数) {
                _root.地形伤害系数 = 0.09 + (_root.地形伤害系数 - 0.09) * 20 / 净化量2;
            }
            控制对象.麻痹值 = -10 * 净化量2;

            var flag:Boolean = ItemUtil.singleAcquire("幻层残响", 1);
            _root.发布消息(flag, "酒精渗透神经的瞬间，区块链中流窜的数据碎片涌入了你的意识...");
            EffectSystem.Effect("药剂动画", 控制对象._x, 控制对象._y, 100);
            break;
    }
};
