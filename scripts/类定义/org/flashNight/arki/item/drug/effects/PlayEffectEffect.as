import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Effect.*;

/**
 * PlayEffectEffect - 播放特效词条
 *
 * 在指定位置播放视觉特效。
 *
 * XML配置示例:
 * <effect type="playEffect" name="药剂动画"/>
 * <effect type="playEffect" name="淬毒动画" x="0" y="0" scale="100"/>
 * <effect type="playEffect" name="净化动画" offsetX="10" offsetY="-20"/>
 *
 * 参数说明:
 * - name: 特效名称（必需）
 * - x: 绝对X坐标（可选，默认使用目标位置）
 * - y: 绝对Y坐标（可选，默认使用目标位置）
 * - offsetX: 相对于目标的X偏移（可选，默认0）
 * - offsetY: 相对于目标的Y偏移（可选，默认0）
 * - scale: 缩放比例（可选，默认100）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.PlayEffectEffect implements IDrugEffect {

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

        var target:Object = ctx.target;

        // 计算位置
        var posX:Number;
        var posY:Number;

        if (effectData.x != undefined) {
            posX = Number(effectData.x);
        } else {
            posX = target._x;
            var offsetX:Number = Number(effectData.offsetX);
            if (!isNaN(offsetX)) posX += offsetX;
        }

        if (effectData.y != undefined) {
            posY = Number(effectData.y);
        } else {
            posY = target._y;
            var offsetY:Number = Number(effectData.offsetY);
            if (!isNaN(offsetY)) posY += offsetY;
        }

        // 缩放
        var scale:Number = Number(effectData.scale);
        if (isNaN(scale)) scale = 100;

        // 播放特效
        EffectSystem.Effect(effectName, posX, posY, scale);

        return true;
    }
}
