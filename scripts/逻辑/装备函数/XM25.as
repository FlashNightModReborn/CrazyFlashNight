import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.render.*;

/* ---------------------------------------------------------
 * XM25  初始化
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM25初始化 = function (ref:Object, param:Object)
{
    // 激光当前的角度
    ref.laserRotation = 0;
    
    // 激光旋转的平滑系数（速度）
    ref.laserRotationSpeed = 0.2; 
    
    // 定义激光的旋转角度限制
    ref.laserMaxAngle = 60;  // 最大向右旋转角度
    ref.laserMinAngle = -60; // 最大向左旋转角度
    
    // 用于存储锁定状态的敌人
    ref.lockedEnemy = null;
    
    // --- 新增：用于检测“单次按下”的按键状态变量 ---
    // 记录上一帧武器变形键是否被按下
    ref.wasTransformKeyDown = false; 
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

    // --- 1. 按键检测：实现“按键切换/Toggle”逻辑 ---
    
    var isTransformKeyDown:Boolean = _root.按键输入检测(target, _root.武器变形键);
    
    // 关键：检测按键是否为“刚刚被按下” (当前帧按下，上一帧未按下)
    if (isTransformKeyDown && !ref.wasTransformKeyDown) {
        // 如果当前已经锁定了目标，则这次按下是“解锁”
        if (ref.lockedEnemy != null) {
            ref.lockedEnemy = null;
        } 
        // 如果当前未锁定目标，则这次按下是“尝试锁定”
        else {
            // 查找最近的敌人并设为锁定目标
            ref.lockedEnemy = MovieClip(TargetCacheManager.findNearestEnemy(target, 5));
        }
    }
    
    // 在逻辑的最后，更新上一帧的按键状态，为下一帧做准备
    ref.wasTransformKeyDown = isTransformKeyDown;

    
    // --- 2. 追踪与破锁逻辑 ---

    var targetRotation:Number = 0; // 默认目标是归位到0度

    // 检查是否存在一个有效的锁定目标
    if (ref.lockedEnemy != null) {
        AABBRenderer.renderAABB(ref.lockedEnemy.aabbCollider, 0, "unhit")
        var enemyToTrack:MovieClip = ref.lockedEnemy;
        var enemyGlobalPos:Object = UnitUtil.getAimPoint(enemyToTrack);
        gun.globalToLocal(enemyGlobalPos);
        
        var dx:Number = enemyGlobalPos.x - laser._x;
        var dy:Number = enemyGlobalPos.y - laser._y;
        
        var angleRadians:Number = Math.atan2(dy, dx);
        
        if (!isNaN(angleRadians)) {
            var calculatedAngle:Number = angleRadians * RAD_TO_DEG;
            
            // --- 关键：检查锁定目标是否超出旋转限制 ---
            if (calculatedAngle > ref.laserMaxAngle || calculatedAngle < ref.laserMinAngle) {
                // 如果超出限制，则强制“破锁”
                ref.lockedEnemy = null;
                // targetRotation 保持为 0，激光开始归位
            } else {
                // 如果在限制内，则更新目标角度以继续追踪
                targetRotation = calculatedAngle;
            }
        }
    } else {
        // 如果 lockedEnemy 无效 (已被摧毁或一开始就为null)，确保它被清空
        ref.lockedEnemy = null;
        // targetRotation 保持为 0，激光归位或保持归位状态
    }
    
    // --- 3. 平滑旋转 (这部分逻辑与原来相同) ---
    var currentRotation:Number = ref.laserRotation;
    var delta:Number = targetRotation - currentRotation;

    // 确保旋转走最短路径
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