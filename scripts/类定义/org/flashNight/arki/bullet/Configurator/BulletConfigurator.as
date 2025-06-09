// 文件路径：org/flashNight/arki/bullet/Configurator/BulletConfigurator.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;

class org.flashNight.arki.bullet.Configurator.BulletConfigurator {
    /**
     * 构造函数
     * BulletConfigurator 仅包含静态方法，不需要实例化
     */
    private function BulletConfigurator() {
        // 防止实例化
    }

    /**
     * 配置子弹属性
     * @param config:Object 子弹配置对象
     * @param shooter:MovieClip 发射者对象
     */
    public static function configure(config:Object, shooter:MovieClip):Void {
        BulletConfigurator.setDefaultValues(config, shooter);
        BulletConfigurator.inheritShooterProperties(config, shooter);
        BulletConfigurator.calculateRecoilSpeed(config);
        BulletConfigurator.initializeBulletProperties(config);
    }

    /**
     * 设置子弹的默认值
     * @param config:Object 子弹配置对象
     * @param shooter:MovieClip 发射者对象
     */
    private static function setDefaultValues(config:Object, shooter:MovieClip):Void {
        config.固伤 = isNaN(config.固伤) ? 0 : Number(config.固伤);
        config.命中率 = isNaN(config.命中率) ? shooter.命中率 : Number(config.命中率);
        config.最小霰弹值 = isNaN(config.最小霰弹值) ? 1 : Number(config.最小霰弹值);
        config.远距离不消失 = config.手雷检测 || config.爆炸检测;
    }

    /**
     * 继承发射者的属性到子弹
     * @param config:Object 子弹配置对象
     * @param shooter:MovieClip 发射者对象
     */
    private static function inheritShooterProperties(config:Object, shooter:MovieClip):Void {
        // 伤害类型继承
        config.伤害类型 = (!config.伤害类型 && shooter.伤害类型) ? shooter.伤害类型 : config.伤害类型;
        
        // 魔法伤害属性继承
        config.魔法伤害属性 = (!config.魔法伤害属性 && shooter.魔法伤害属性) ? shooter.魔法伤害属性 : config.魔法伤害属性;
        
        // 吸血属性继承
        if (config.吸血 || shooter.吸血) {
            var config吸血:Number = isNaN(config.吸血) ? 0 : Number(config.吸血);
            var shooter吸血:Number = isNaN(shooter.吸血) ? 0 : Number(shooter.吸血);
            config.吸血 = Math.max(config吸血, shooter吸血);
        }
        
        // 击溃属性继承
        if (config.血量上限击溃 || shooter.击溃) {
            var config击溃:Number = isNaN(config.血量上限击溃) ? 0 : Number(config.血量上限击溃);
            var shooter击溃:Number = isNaN(shooter.击溃) ? 0 : Number(shooter.击溃);
            config.击溃 = Math.max(config击溃, shooter击溃);
        }
    }

    /**
     * 计算子弹的击退速度
     * @param config:Object 子弹配置对象
     */
    private static function calculateRecoilSpeed(config:Object):Void {
        // 水平击退速度
        config.水平击退速度 = (isNaN(config.水平击退速度) || config.水平击退速度 < 0) ? 10 : Math.min(Number(config.水平击退速度), _root.最大水平击退速度);
        
        // 垂直击退速度
        config.垂直击退速度 = isNaN(config.垂直击退速度) ? 5 : Math.min(Number(config.垂直击退速度), _root.最大垂直击退速度);
    }

    /**
     * 初始化子弹的基础属性
     * @param config:Object 子弹配置对象
     */
    private static function initializeBulletProperties(config:Object):Void {
        config.发射者名 = config.发射者;
        config._x = config.shootX;
        config._y = config.shootY;
        config.Z轴坐标 = config.shootZ;
        config.子弹区域area = config.区域定位area;
    }
}
