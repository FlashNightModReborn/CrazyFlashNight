import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;

class org.flashNight.arki.component.Effect.BloodBarEffectHandler {
  
    // 利用静态属性的表驱动方式管理血条色彩更新逻辑
    private static var colorActions:Object = initActions();

    private static function initActions():Object {
        var obj:Object = {};
        obj["常态"] = function(bar:MovieClip):Void {
            _root.重置色彩(bar);
        };
        obj["default"] = function(bar:MovieClip):Void {
            _root.暗化色彩(bar);
        };
        return obj;
    }
  
    /**
     * 更新血条状态：根据 hitTarget 获取血条，显示并播放动画，
     * 然后根据传入的状态更新血条颜色。
     * @param hitTarget 被击对象
     * @param state 血条状态，例如 "常态"
     */
    public static function updateStatus(hitTarget:MovieClip, state:String):Void {
        var bar:MovieClip;
        var state:String = hitTarget.barColorState;
        
        // 根据是否存在新版人物文字信息选择对应的血条
        if (hitTarget.新版人物文字信息 != undefined) {
            bar = hitTarget.新版人物文字信息.头顶血槽;
        } else {
            bar = hitTarget.人物文字信息.头顶血槽;
        }
        // 显示并播放血条动画
        bar._visible = true;
        bar.gotoAndPlay(2);
      
        // 根据状态更新血条颜色（表驱动方式）
        if (colorActions[state] != undefined) {
            colorActions[state](bar);
        } else {
            colorActions["default"](bar);
        }

        InformationComponentUpdater.update(hitTarget);
    }
}
