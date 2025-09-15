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
    
    // --- 新增：用于检测"单次按下"的按键状态变量 ---
    // 记录上一帧武器变形键是否被按下
    ref.wasTransformKeyDown = false; 
    
    // =============== 新增：渐进式锁定系统 ===============
    
    // 锁定阶段 (1-4，对应 scan1-scan4)
    ref.lockLevel = 0;  // 0表示未锁定，1-4表示不同锁定强度
    
    // 锁定时间计时器（帧数）
    ref.lockTimer = 0;
    
    // 各个锁定阶段所需的持续时间
    ref.lockTimers = {
        level1: 0,      // scan1 立即获得
        level2: 30,     // scan2 需要持续1秒
        level3: 60,    // scan3 需要持续2秒
        level4: 120     // scan4 需要持续4秒
    };
    
    // 是否正在持续按键锁定
    ref.isHoldingLock = false;
    
    // 锁定模式字符串映射
    ref.lockModes = ["", "scan1", "scan2", "scan3", "scan4"];
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

    // --- 1. 按键检测：实现锁定与解锁逻辑 ---
    
    var isTransformKeyDown:Boolean = _root.按键输入检测(target, _root.武器变形键);
    
    // 关键：检测按键是否为"刚刚被按下" (当前帧按下，上一帧未按下)
    if (isTransformKeyDown && !ref.wasTransformKeyDown) {
        // 如果当前已经锁定了目标，则这次按下是"解锁"
        if (ref.lockedEnemy != null) {
            // 完全解锁：清除目标和重置所有锁定状态
            ref.lockedEnemy = null;
            ref.lockLevel = 0;
            ref.lockTimer = 0;
            ref.isHoldingLock = false;
        } 
        // 如果当前未锁定目标，则这次按下是"尝试锁定"
        else {
            // 查找最近的敌人并设为锁定目标
            var nearestEnemy:MovieClip = MovieClip(TargetCacheManager.findNearestEnemy(target, 5));
            if (nearestEnemy != null) {
                ref.lockedEnemy = nearestEnemy;
                ref.lockLevel = 1;      // 初始锁定等级
                ref.lockTimer = 0;      // 重置计时器
                ref.isHoldingLock = true; // 开始持续锁定
            }
        }
    }
    
    // --- 2. 持续按键锁定升级逻辑 ---
    
    if (ref.lockedEnemy != null && isTransformKeyDown) {
        ref.isHoldingLock = true;
        ref.lockTimer++;
        
        // 根据持续时间升级锁定等级
        if (ref.lockLevel == 1 && ref.lockTimer >= ref.lockTimers.level2) {
            ref.lockLevel = 2;
        } else if (ref.lockLevel == 2 && ref.lockTimer >= ref.lockTimers.level3) {
            ref.lockLevel = 3;
        } else if (ref.lockLevel == 3 && ref.lockTimer >= ref.lockTimers.level4) {
            ref.lockLevel = 4;
        }
    } else if (ref.lockedEnemy != null) {
        // 松开按键，停止升级但保持当前锁定等级
        ref.isHoldingLock = false;
        // 注意：不重置 lockTimer，这样重新按下时可以继续之前的进度
    }
    
    // 在逻辑的最后，更新上一帧的按键状态，为下一帧做准备
    ref.wasTransformKeyDown = isTransformKeyDown;

    
    // --- 3. 追踪与破锁逻辑 ---

    var targetRotation:Number = 0; // 默认目标是归位到0度

    // 检查是否存在一个有效的锁定目标
    if (ref.lockedEnemy != null && ref.lockLevel > 0) {
        // 根据当前锁定等级渲染对应的AABB
        var currentScanMode:String = ref.lockModes[ref.lockLevel];
        AABBRenderer.renderAABB(ref.lockedEnemy.aabbCollider, 0, currentScanMode);
        
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
                // 如果超出限制，则强制"破锁"，重置所有锁定状态
                ref.lockedEnemy = null;
                ref.lockLevel = 0;
                ref.lockTimer = 0;
                ref.isHoldingLock = false;
                // targetRotation 保持为 0，激光开始归位
            } else {
                // 如果在限制内，则更新目标角度以继续追踪
                targetRotation = calculatedAngle;
            }
        }
    } else if (ref.lockedEnemy != null) {
        // 如果 lockedEnemy 无效 (已被摧毁)，清空所有锁定状态
        ref.lockedEnemy = null;
        ref.lockLevel = 0;
        ref.lockTimer = 0;
        ref.isHoldingLock = false;
        // targetRotation 保持为 0，激光归位或保持归位状态
    }
    
    // --- 4. 平滑旋转 (这部分逻辑与原来相同) ---
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
    
    // --- 5. 调试信息 (可选，开发时使用) ---
    /*
    if (ref.lockedEnemy != null) {
        trace("锁定等级: " + ref.lockLevel + 
              ", 计时器: " + ref.lockTimer + 
              ", 持续按键: " + ref.isHoldingLock +
              ", 模式: " + ref.lockModes[ref.lockLevel]);
    }
    */
};