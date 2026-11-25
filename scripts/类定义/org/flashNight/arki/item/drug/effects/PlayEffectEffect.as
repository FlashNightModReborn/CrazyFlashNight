import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Effect.*;

/**
 * PlayEffectEffect - 播放特效词条
 *
 * 在指定位置播放视觉特效；支持 target="group" 对自身及存活友军播特效。
 *
 * XML配置示例:
 * <effect type="playEffect" name="药剂动画"/>
 * <effect type="playEffect" name="淬毒动画" x="0" y="0" scale="100"/>
 * <effect type="playEffect" name="净化动画" offsetX="10" offsetY="-20"/>
 *
 * 参数说明:
 * - name: 特效名称（必需）
 * - target: 作用范围（"self" 默认单体；"group" 自身及存活友军，可选 rangeX/rangeY）
 * - x: 绝对X坐标（可选，默认使用目标位置）
 * - y: 绝对Y坐标（可选，默认使用目标位置）
 * - offsetX: 相对于目标的X偏移（可选，默认0）
 * - offsetY: 相对于目标的Y偏移（可选，默认0）
 * - scale: 缩放比例（可选，默认100）
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.arki.item.drug.effects.PlayEffectEffect implements IDrugEffect {

    /** 单元测试可注入的群体友军解析钩子；生产环境保持 null 并走 TargetCacheManager */
    public static var groupTargetResolver:Function = null;

    public function PlayEffectEffect() {
    }

    public function getType():String {
        return "playEffect";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var effectName:String = effectData.name;
        if (!effectName || effectName.length == 0) {
            trace("[PlayEffectEffect] 缺少必要参数: name");
            return false;
        }

        // 缩放
        var scale:Number = Number(effectData.scale);
        if (isNaN(scale)) scale = 100;

        var offsetX:Number = Number(effectData.offsetX);
        var offsetY:Number = Number(effectData.offsetY);
        var hasExplicitX:Boolean = (effectData.x != undefined);
        var hasExplicitY:Boolean = (effectData.y != undefined);

        var targetMode:String = (effectData.target != null && String(effectData.target).length > 0)
            ? String(effectData.target) : "self";

        if (targetMode == "group") {
            var targets:Array = org.flashNight.arki.item.drug.effects.PurifyEffect.resolveGroupTargetsWithResolver(
                ctx.target, effectData, groupTargetResolver
            );
            for (var i:Number = 0; i < targets.length; i++) {
                var u:Object = targets[i];
                if (!u) continue;
                var gx:Number = hasExplicitX ? Number(effectData.x) : u._x + (isNaN(offsetX) ? 0 : offsetX);
                var gy:Number = hasExplicitY ? Number(effectData.y) : u._y + (isNaN(offsetY) ? 0 : offsetY);
                EffectSystem.Effect(effectName, gx, gy, scale);
            }
            return true;
        }

        var target:Object = ctx.target;
        var posX:Number = hasExplicitX ? Number(effectData.x) : target._x + (isNaN(offsetX) ? 0 : offsetX);
        var posY:Number = hasExplicitY ? Number(effectData.y) : target._y + (isNaN(offsetY) ? 0 : offsetY);

        EffectSystem.Effect(effectName, posX, posY, scale);

        return true;
    }
}
