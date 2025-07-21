import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;


/* ---------------------------------------------------------
 * XM25  初始化
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM25初始化 = function (ref:Object, param:Object)
{
    // 激光当前的角度
    ref.laserRotation = 0;
    
    // 激光旋转的平滑系数（速度）
    ref.laserRotationSpeed = 0.2; 
    
    // --- 新增：定义激光的旋转角度限制 ---
    ref.laserMaxAngle = 60;  // 最大向右旋转角度
    ref.laserMinAngle = -60; // 最大向左旋转角度 (用负数表示)
};

/* ---------------------------------------------------------
 * XM25  周期函数
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM25周期 = function (ref:Object, param:Object)
{
    var RAD_TO_DEG:Number = 180 / Math.PI;
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    
    if (gun == undefined) { return; }
    var laser:MovieClip = gun.激光模组;
    if (laser == undefined) { return; }
    
    var targetRotation:Number = ref.laserRotation;
    var enemy:MovieClip = MovieClip(TargetCacheManager.findNearestEnemy(target, 5));

    if (enemy != undefined && enemy != null) {
        if (gun._root == _root) {
            var enemyGlobalPos:Object = UnitUtil.getAimPoint(enemy);
            gun.globalToLocal(enemyGlobalPos);
            
            var dx:Number = enemyGlobalPos.x - laser._x;
            var dy:Number = enemyGlobalPos.y - laser._y;
            
            var angleRadians:Number = Math.atan2(dy, dx);
            
            if (!isNaN(angleRadians)) {
                targetRotation = angleRadians * RAD_TO_DEG;
            }
        }
    } else {
        // 如果没有敌人，目标是归位到 0 度
        targetRotation = 0;
    }

    // --- 新增：角度限制逻辑 ---
    // 将目标角度“钳制”在允许的范围内
    // Math.max 确保它不小于最小值，Math.min 确保它不大于最大值
    targetRotation = Math.max(ref.laserMinAngle, Math.min(ref.laserMaxAngle, targetRotation));
    
    // --- 平滑旋转的核心逻辑 (这部分无需改动) ---
    var currentRotation:Number = ref.laserRotation;
    var delta:Number = targetRotation - currentRotation;

    if (delta > 180) {
        delta -= 360;
    } else if (delta < -180) {
        delta += 360;
    }

    currentRotation += delta * ref.laserRotationSpeed;
    ref.laserRotation = currentRotation;

    if (!isNaN(ref.laserRotation)) {
        laser._rotation = ref.laserRotation;
    }
};