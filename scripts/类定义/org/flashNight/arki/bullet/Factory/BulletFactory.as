/**
 * BulletFactory.as
 * 位于 org.flashNight.arki.bullet.BulletComponent.Factory 包下
 *
 * 提供创建子弹及更新子弹统计的静态方法接口，便于平滑迁移原有 _root 方法。
 */
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.arki.bullet.Factory.*;

class org.flashNight.arki.bullet.Factory.BulletFactory {

    // 私有构造函数，禁止实例化
    private function BulletFactory() {
    }

    private static var count:Number = 0;
    
    /**
     * 创建子弹
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     * @param shootingAngle 发射角度
     * @return 创建的子弹实例
     */
    public static function createBullet(Obj, shooter, shootingAngle){
        var fireCount:Number = Obj.联弹检测 ? 1 : Obj.霰弹值;
        var bulletInstance:Object;
        
        Obj.联弹霰弹值 = Obj.联弹检测 ? Obj.霰弹值 : 1; // 修正大小写问题
        
        do {
            bulletInstance = createBulletInstance(Obj, shooter, shootingAngle);
        } while (--fireCount > 0);
        
        
        return bulletInstance;
    }
    
    /**
     * 创建子弹实例
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     * @param shootingAngle 发射角度
     * @return 创建的子弹实例
     */
    public static function createBulletInstance(Obj, shooter, shootingAngle) {
        var gameWorld:MovieClip = _root.gameworld,
            isTransparent:Boolean = Obj.透明检测,
            isChain:Boolean = Obj.联弹检测,
            zyRatio:Number = Obj.ZY比例,
            speedX:Number = Obj.速度X,
            speedY:Number = Obj.速度Y,
            velocity:Number = Obj.子弹速度,

            // 散射角度计算
            scatteringAngle:Number = Obj.近战检测 ? 0 : (shootingAngle + (isChain ? 0 : _root.随机偏移(Obj.子弹散射度))),

            angleRadians = scatteringAngle * (Math.PI / 180),
            bulletInstance;

        // 设置旋转角度

        // 优化后的条件判断和角度计算
        Obj._rotation = (zyRatio && speedX && speedY) 
            ? (Math.atan2(speedY, speedX) * (180 / Math.PI) + 360) % 360 
            : scatteringAngle;

        // 创建子弹实例
        if (isTransparent) {
            bulletInstance = _root.对象浅拷贝(Obj);
        } else {
            // 利用子弹计数来管理子弹深度
            bulletInstance = gameWorld.子弹区域.attachMovie(
                Obj.baseAsset, 
                Obj.发射者名 + Obj.子弹种类 + count + scatteringAngle,
                count, 
                Obj);
        }

        count = (++count) % 100; // 让深度值在 100 之间循环

        // 设置运动参数

        bulletInstance.霰弹值 = isChain ? Obj.霰弹值 : 1;

        // 初始化纳米毒性功能
        BulletInitializer.initializeNanoToxicfunction(Obj, bulletInstance, shooter);

        var lifecycle:ILifecycle;

        if (isTransparent) {
            lifecycle = TransparentBulletLifecycle.BASIC;
        }
        else
        {
            if(bulletInstance.近战检测)
            {
                lifecycle = MeleeBulletLifecycle.BASIC;
            }
            else
            {
                lifecycle = NormalBulletLifecycle.BASIC;

                bulletInstance.xmov = velocity * Math.cos(angleRadians);
                bulletInstance.ymov = velocity * Math.sin(angleRadians);
                
                var movement:IMovement = LinearBulletMovement.create(
                    speedX, 
                    speedY, 
                    zyRatio
                );
                bulletInstance.updateMovement = Delegate.create(movement, movement.updateMovement);
                bulletInstance.shouldDestroy = Delegate.create(lifecycle, lifecycle.shouldDestroy);
            }
        }

        // 绑定生命周期逻辑

        lifecycle.bindLifecycle(bulletInstance);

        // 统计钩子调用（注释关闭）
        // BulletFactoryDebugger.updateBulletStats(gameWorld, Obj, shooter);

        return bulletInstance;
    };
}