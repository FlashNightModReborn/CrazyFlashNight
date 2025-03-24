import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.naki.RandomNumberEngine.*;

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
    public static function updateStatus(hitTarget:MovieClip):Void {
        var state:String = hitTarget.barColorState;
        var ic:MovieClip = hitTarget.新版人物文字信息;
        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarBottom:MovieClip = hpBar.血槽底;
        var bloodBarLength:Number = hpBarBottom._width;
        // 显示并播放血条动画
        hpBar._visible = true;
        hpBar.gotoAndPlay(2);

        var seed:Number;

        ic._y += ((seed = LinearCongruentialEngine.instance.next()) % 2 * 0.5) * Math.sin(seed * 0.65), 
        ic._x += ((seed * 0.5 % 3 << 1) * 0.15 + 0.3) * Math.cos(seed * 0.35 + 1.6);

        // 计算实际血槽条的宽度
        var actualHpWidth:Number = hitTarget.hp / hitTarget.hp满血值 * bloodBarLength;
        hpBar.血槽条._width = actualHpWidth;
        hitTarget.hpUnchangedCounter = 0;
    }

    public static function updateColor(hitTarget:MovieClip):Void
    {
        var state:String = hitTarget.barColorState;
        var ic:MovieClip = hitTarget.新版人物文字信息;
        var hpBar:MovieClip = ic.头顶血槽;

        var action:Function = colorActions[state];
      
        // 根据状态更新血条颜色（表驱动方式）
        if (action != undefined) {
            action(hpBar);
        } else {
            colorActions["default"](hpBar);
        }
    }
}
