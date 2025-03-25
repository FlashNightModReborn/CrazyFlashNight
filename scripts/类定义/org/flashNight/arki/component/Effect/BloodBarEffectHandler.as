import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.UnitComponent.Updater.*;
import org.flashNight.naki.RandomNumberEngine.*;

class org.flashNight.arki.component.Effect.BloodBarEffectHandler {
  
    // 利用静态属性的表驱动方式管理血条色彩更新逻辑
    private static var colorActions:Object = initActions();

    private static function initActions():Object {
        var obj:Object = {};
        obj["常态"] = function(bar:MovieClip):Void {
            ColorEffects.resetColorReuse(bar);
        };
        obj["default"] = function(bar:MovieClip):Void {
            ColorEffects.darkenColorReuse(bar);
        };
        return obj;
    }
  
    /**
     * 更新血条状态：根据 hitTarget 获取血条，显示并播放动画，
     * 然后根据传入的状态更新血条颜色。
     * @param hitTarget 被击对象
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
        // 更新文本信息 MovieClip 的位置，增加些许随机抖动效果
        seed = LinearCongruentialEngine.instance.next();
        ic._y += ((seed % 2 * 0.5) * Math.sin(seed * 0.65));
        ic._x += ((((seed * 0.5 % 3) << 1) * 0.15 + 0.3) * Math.cos(seed * 0.35 + 1.6));

        // 计算实际血槽条的宽度
        var actualHpWidth:Number = hitTarget.hp / hitTarget.hp满血值 * bloodBarLength;
        var hpBarGreen:MovieClip = hpBar.血槽条;
        hpBarGreen._width = actualHpWidth;

        if (hitTarget.hpUnchangedCounter != 0) {
            hitTarget.hpUnchangedCounter = 0;
            // 使用 ColorEffects 的亮化色彩方法
            // 随机亮化强度由 _root.随机整数(25,75) 生成
            ColorEffects.lightenColorReuseRandom(hpBarGreen);
        }
    }

    /**
     * 更新血条颜色：根据 hitTarget 的 barColorState 更新血条色彩
     * @param hitTarget 被击对象
     */
    public static function updateColor(hitTarget:MovieClip):Void {
        var state:String = hitTarget.barColorState;
        var ic:MovieClip = hitTarget.新版人物文字信息;
        var hpBar:MovieClip = ic.头顶血槽;
        var hpBarGreen:MovieClip = hpBar.血槽条;

        var action:Function = colorActions[state];
      
        // 根据状态更新血条颜色（表驱动方式）
        if (action != undefined) {
            action(hpBarGreen);
        } else {
            colorActions["default"](hpBarGreen);
        }
    }
}
