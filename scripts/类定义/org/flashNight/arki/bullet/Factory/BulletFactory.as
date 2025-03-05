/**
 * BulletFactory.as
 * 位于 org.flashNight.arki.bullet.BulletComponent.Factory 包下
 *
 * 提供创建子弹及更新子弹统计的静态方法接口，便于平滑迁移原有 _root 方法。
 */
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.aven.Proxy.*;

class org.flashNight.arki.bullet.Factory.BulletFactory {

    // 私有构造函数，禁止实例化
    private function BulletFactory() {
    }
    
    /**
     * 创建子弹
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     * @param 射击角度 发射角度
     * @return 创建的子弹实例
     */
    public static function createBullet(Obj, shooter, 射击角度){
        var count:Number = Obj.联弹检测 ? 1 : Obj.霰弹值;
        var bulletInstance:Object;
        
        Obj.联弹霰弹值 = Obj.联弹检测 ? Obj.霰弹值 : 1; // 修正大小写问题
        
        do {
            bulletInstance = createBulletInstance(Obj, shooter, 射击角度);
        } while (--count > 0);
        
        
        return bulletInstance;
    }
    
    /**
     * 创建子弹实例
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     * @param 射击角度 发射角度
     * @return 创建的子弹实例
     */
    public static function createBulletInstance(Obj, shooter, 射击角度) {
        var gameWorld = _root.gameworld,
            isTransparent = Obj.透明检测,
            isChain = Obj.联弹检测,
            isMelee = Obj.近战检测,
            hasZY = Obj.ZY比例,
            speedX = Obj.速度X,
            speedY = Obj.速度Y,
            velocity = Obj.子弹速度,
            DEG_TO_RAD = Math.PI / 180,
            RAD_TO_DEG = 180 / Math.PI,
            // 散射角度计算
            散射角度 = isMelee ? 0 : (射击角度 + (isChain ? 0 : _root.随机偏移(Obj.子弹散射度))),
            // 形状偏角计算
            useSpeedAngle = hasZY && speedX && speedY,
            形状偏角 = useSpeedAngle ? (Math.atan2(speedY, speedX) * RAD_TO_DEG % 360 + 360) % 360 : 散射角度,
            angleRadians = 散射角度 * DEG_TO_RAD,
            bulletInstance;

        Obj._rotation = 形状偏角; // 设置旋转角度

        // 创建子弹实例
        if (isTransparent) {
            bulletInstance = _root.对象浅拷贝(Obj);
        } else {
            _root.子弹生成计数 = (_root.子弹生成计数 + 2) % 100; // 保持原计数逻辑
            var depth = _root.子弹生成计数,
                b_name = Obj.发射者名 + Obj.子弹种类 + depth + 散射角度 + _root.子弹生成计数;
            bulletInstance = gameWorld.子弹区域.attachMovie(Obj.baseAsset, b_name, depth, Obj);
        }

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
                
                var movement = LinearBulletMovement.create(
                    speedX, 
                    speedY, 
                    hasZY
                );
                bulletInstance.updateMovement = Delegate.create(movement, movement.updateMovement);
                bulletInstance.shouldDestroy = Delegate.create(lifecycle, lifecycle.shouldDestroy);
            }
        }

        // 绑定生命周期逻辑

        lifecycle.bindLifecycle(bulletInstance);

        // 统计钩子调用（注释关闭）
        // this.updateBulletStats(gameWorld, Obj, shooter);

        return bulletInstance;
    };
    
    /**
     * 更新子弹统计信息
     * @param gameWorld 游戏世界对象
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     */
    public static function updateBulletStats(游戏世界, Obj, shooter) {
        var report_len = 16;

        // 初始化统计信息（如果没有）
        if (!游戏世界.bulletStats) {
            游戏世界.bulletStats = {
                shooters: {},
                bulletTypes: {},
                totalShots: 0,
                timeStats: {},
                unitShots: {},
                lastSecondStats: {
                    shooters: {},
                    bulletTypes: {},
                    totalShots: 0
                }
            };
        }

        // 增加单位发射数量
        if (!游戏世界.bulletStats.shooters[shooter]) {
            游戏世界.bulletStats.shooters[shooter] = {
                shotCount: 0,
                bulletTypes: {}
            };
        }
        游戏世界.bulletStats.shooters[shooter].shotCount++;

        // 增加子弹类型发射数量
        if (!游戏世界.bulletStats.bulletTypes[Obj.子弹种类]) {
            游戏世界.bulletStats.bulletTypes[Obj.子弹种类] = {
                shotCount: 0,
                shooters: {}
            };
        }
        游戏世界.bulletStats.bulletTypes[Obj.子弹种类].shotCount++;

        // 增加全局子弹统计
        游戏世界.bulletStats.totalShots++;

        // 时间统计：跟踪每一帧创建的子弹数量
        var currentFrame = _root.帧计时器.当前帧数;
        var currentSecond = Math.floor(currentFrame / 30);
        if (!游戏世界.bulletStats.timeStats[currentSecond]) {
            游戏世界.bulletStats.timeStats[currentSecond] = {
                totalShots: 0,
                shooters: {}
            };
        }
        游戏世界.bulletStats.timeStats[currentSecond].totalShots++;
        if (!游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]) {
            游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter] = 0;
        }
        游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]++;

        // 增加每个单位的子弹创建数量
        if (!游戏世界.bulletStats.unitShots[shooter]) {
            游戏世界.bulletStats.unitShots[shooter] = {
                shotCount: 0,
                bulletTypes: {}
            };
        }
        游戏世界.bulletStats.unitShots[shooter].shotCount++;
        if (!游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]) {
            游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类] = 0;
        }
        游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]++;

        // 每秒汇总一次统计信息
        if (currentFrame % 30 == 0) {
            var report = "子弹创建与发射频率分析报告：\n";

            // 发射者排行（按发射数量）
            var sortedShooters = [];
            for (var shooterName in 游戏世界.bulletStats.shooters) {
                sortedShooters.push({ name: shooterName, count: 游戏世界.bulletStats.shooters[shooterName].shotCount });
            }
            sortedShooters.sort(function(a, b) { return b.count - a.count; });

            report += "发射者排行（按发射数量）：\n";
            for (var i = 0; i < Math.min(report_len, sortedShooters.length); i++) {
                var shooterSummary = sortedShooters[i];
                report += shooterSummary.name + ": " + shooterSummary.count + " 发射\n";

                // 每个发射者发射的子弹类型统计
                for (var bulletType in 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes) {
                    report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes[bulletType] + " 发射\n";
                }
            }

            // 子弹类型排行（按发射数量）
            var sortedBulletTypes = [];
            for (var bulletType in 游戏世界.bulletStats.bulletTypes) {
                sortedBulletTypes.push({ name: bulletType, count: 游戏世界.bulletStats.bulletTypes[bulletType].shotCount });
            }
            sortedBulletTypes.sort(function(a, b) { return b.count - a.count; });

            report += "子弹类型排行（按发射数量）：\n";
            for (var i = 0; i < Math.min(report_len, sortedBulletTypes.length); i++) {
                var bulletTypeSummary = sortedBulletTypes[i];
                report += bulletTypeSummary.name + ": " + bulletTypeSummary.count + " 发射\n";
            }

            // 最多创建子弹的单位（按创建子弹数量）
            var sortedUnitShots = [];
            for (var unitName in 游戏世界.bulletStats.unitShots) {
                sortedUnitShots.push({ name: unitName, count: 游戏世界.bulletStats.unitShots[unitName].shotCount });
            }
            sortedUnitShots.sort(function(a, b) { return b.count - a.count; });

            report += "最多创建子弹的单位排行：\n";
            for (var i = 0; i < Math.min(report_len, sortedUnitShots.length); i++) {
                var unitSummary = sortedUnitShots[i];
                report += unitSummary.name + ": " + unitSummary.count + " 次创建\n";

                // 每个单位创建的子弹类型统计
                for (var bulletType in 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes) {
                    report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes[bulletType] + " 次创建\n";
                }
            }

            // 每秒子弹创建频率分析
            report += "\n每秒子弹创建频率分析：\n";
            var sortedTimeStats = [];
            for (var second in 游戏世界.bulletStats.timeStats) {
                var timeData = 游戏世界.bulletStats.timeStats[second];
                sortedTimeStats.push({ second: second, shotCount: timeData.totalShots });
            }
            sortedTimeStats.sort(function(a, b) { return b.shotCount - a.shotCount; });

            for (var i = 0; i < Math.min(report_len, sortedTimeStats.length); i++) {
                var timeSummary = sortedTimeStats[i];
                report += "第 " + timeSummary.second + " 秒: " + timeSummary.shotCount + " 子弹创建\n";

                // 每秒区间内的发射者发射情况
                for (var shooterName in 游戏世界.bulletStats.timeStats[timeSummary.second].shooters) {
                    report += "  发射者 " + shooterName + ": " + 游戏世界.bulletStats.timeStats[timeSummary.second].shooters[shooterName] + " 发射\n";
                }
            }

            // 总子弹数量（全局）
            report += "总子弹数量（全局）: " + 游戏世界.bulletStats.totalShots + "\n";

            // 发送汇总后的统计信息
            _root.服务器.发布服务器消息(report);
        }
    };

}