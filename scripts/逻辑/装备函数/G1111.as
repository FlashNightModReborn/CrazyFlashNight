// =======================================================
// G1111 · 装备生命周期函数 (单向推进版)
// =======================================================

_root.装备生命周期函数.G1111初始化 = function (ref, param)
{
    var target:MovieClip = ref.自机;

    /* ---------- 1. 帧常量 ---------- */
    ref.RIFLE_START      = param.rifleStart  ||  1;
    ref.RIFLE_END        = param.rifleEnd    || 15;
    ref.TRANSFORM_START  = param.transStart  || 16;
    ref.TRANSFORM_END    = param.transEnd    || 30;
    ref.ROCKET_START     = param.rocketStart || 31;
    ref.ROCKET_END       = param.rocketEnd   || 45;

    /* ---------- 2. 状态变量 ---------- */
    ref.isRocketMode     = false;   // false = 步枪, true = 导弹
    ref.isTransforming   = false;
    ref.transformToRock  = false;   // true = 步枪→导弹, false = 导弹→步枪
    ref.isFiring         = false;   // 射击进行中
    ref.fireRequest      = false;   // 当帧射击触发
    ref.currentFrame     = ref.RIFLE_START;
    ref.isWeaponActive   = false;

    /* ---------- 3. 变形冷却 ---------- */
    ref.transformCooldown = 0;
    ref.TRANSFORM_CD_F    = param.transformInterval || 30; // 30 fps = 1 s

    /* ---------- 4. 激光模组自动锁定系统 ---------- */
    ref.laserRotation = 0;              // 激光当前角度
    ref.laserRotationSpeed = param.laserRotationSpeed || 0.15;      // 激光旋转平滑系数
    ref.laserMaxAngle = param.laserMaxAngle || 45;             // 最大向右旋转角度
    ref.laserMinAngle = param.laserMinAngle || -45;            // 最大向左旋转角度
    ref.autoTarget = null;              // 自动锁定的目标
    ref.targetSearchCooldown = 0;       // 搜索目标冷却
    ref.TARGET_SEARCH_INTERVAL = param.targetSearchInterval || 10;    // 搜索间隔(帧)
    ref.ENEMY_SEARCH_DISTANCE = param.enemySearchDistance || 5;      // 敌人搜索距离

    /* ---------- 5. 全局主角同步 ---------- */
    if (ref.是否为主角) {
        var key = ref.标签名 + ref.初始化函数;
        // 确保全局参数对象存在
        if (!_root.装备生命周期函数.全局参数) {
            _root.装备生命周期函数.全局参数 = {};
        }
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl = _root.装备生命周期函数.全局参数[key];
        ref.isRocketMode  = gl.isRocketMode || false;
        ref.currentFrame  = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        ref.globalData    = gl;
        // 确保全局数据同步
        gl.isRocketMode = ref.isRocketMode;
    }

    /* ---------- 5. 射击事件监听 ---------- */
    target.dispatcher.subscribe("长枪射击", function () {
        if(target.攻击模式 !== "长枪") return;
        var prop:Object = target.man.子弹属性;

        // 根据当前帧判断子弹类型，处理变形阶段
        var isRocketMode;
        if (ref.currentFrame >= ref.TRANSFORM_START && ref.currentFrame <= ref.TRANSFORM_END) {
            // 变形阶段：根据变形方向判断
            isRocketMode = ref.transformToRock;
        } else {
            // 非变形阶段：使用状态变量
            isRocketMode = ref.isRocketMode;
        }

        var isCharged = target.铁枪之锋许可;
        if(isCharged) {
            if(isRocketMode) {
                prop.子弹种类 = param.rocketBulletType || "横向拖尾追踪联弹-普通无壳子弹";
                prop.伤害类型 = param.rocketDamageType || "破击";
                prop.魔法伤害属性 = param.rocketMagicType || "首领";
                prop.霰弹值 =  Math.ceil((param.chargedRocketPellets || 16) * target.铁枪之锋倍率);
            } else {
                var chargedProp:Object = ObjectUtil.clone(prop);

                chargedProp.子弹种类 = param.chargedRifleBulletType || "近战联弹";
                chargedProp.伤害类型 = param.chargedRifleDamageType || "真伤";
                chargedProp.霰弹值 =  Math.ceil((param.chargedRiflePellets || 4) * target.铁枪之锋倍率);

                // _root.发布消息(param.chargedRiflePellets, target.铁枪之锋倍率, chargedProp.霰弹值);

                var autoTarget:MovieClip = ref.autoTarget;
                chargedProp.区域定位area  = autoTarget.area;
                chargedProp.shootX = autoTarget._x;
                chargedProp.shootY = autoTarget._y;
                chargedProp.shootZ = autoTarget.Z轴坐标;

                _root.子弹区域shoot传递(chargedProp);

                // 狙击运镜：切换到被狙击单位身上
                var focusFrames = param.focusFrames || 10;
                var focusSnap = (param.focusSnap == "true" || param.focusSnap === true) ? true : false;
                var focusEaseSpeed = param.focusEaseSpeed || 5;
                var focusMinZoom = param.focusMinZoom || 3.0;
                HorizontalScroller.pushFocus(autoTarget, focusFrames, focusSnap, focusEaseSpeed, 0, 0, 0, focusMinZoom);
                
                prop.子弹种类 = param.rifleBulletType || "铁枪磁轨弹";
                prop.伤害类型 = param.rifleDamageType || "魔法";
                prop.魔法伤害属性 = param.rifleMagicType || "能";
                prop.霰弹值 = param.riflePellets || 1;
            }
        } else {
            if(isRocketMode) {
                prop.子弹种类 = param.rocketBulletType || "横向拖尾追踪联弹-普通无壳子弹";
                prop.伤害类型 = param.rocketDamageType || "破击";
                prop.魔法伤害属性 = param.rocketMagicType || "首领";
                prop.霰弹值 = param.rocketPellets || 6;        
            } else {
                prop.子弹种类 = param.rifleBulletType || "铁枪磁轨弹";
                prop.伤害类型 = param.rifleDamageType || "魔法";
                prop.魔法伤害属性 = param.rifleMagicType || "能";
                prop.霰弹值 = param.riflePellets || 1;
            }
        }

        // 铁枪磁轨弹自瞄算法（充能和非充能模式均适用）
        if (prop.子弹种类 == "铁枪磁轨弹") {
            var aimTarget = ref.autoTarget;
            if (aimTarget && aimTarget.hp > 0) {
                // 计算到目标的轨迹
                var distX:Number = aimTarget._x - prop.shootX;
                var defaultHeight:Number = typeof UnitUtil !== "undefined" && UnitUtil.calculateCenterOffset ? 
                                          UnitUtil.calculateCenterOffset(aimTarget) : 0;
                var distY:Number = aimTarget._y - defaultHeight - prop.shootY;
                var distZ:Number = aimTarget.Z轴坐标 - prop.shootZ;
                
                // 计算水平速度，保持子弹速度恒定
                var speedX:Number = distX >= 0 ? prop.子弹速度 : -prop.子弹速度;
                var speedY:Number = speedX * distY / distX;
                
                // 限制垂直速度，确保不超过子弹速度上限
                if (speedY > prop.子弹速度 || speedY < -prop.子弹速度) {
                    speedY = speedY >= 0 ? prop.子弹速度 : -prop.子弹速度;
                    speedX = speedY * distX / distY;
                }
                
                // 设置子弹速度和Z轴比例参数
                prop.速度X = speedX;
                prop.速度Y = speedY;
                prop.ZY比例 = aimTarget.Z轴坐标 / (aimTarget._y - defaultHeight);
            }
        }
    });

    target.dispatcher.subscribe
    ("processShot", function () {
        if(target.攻击模式 !== "长枪") return;
        var prop:Object = target.man.子弹属性;
        if(prop.子弹种类 != "铁枪磁轨弹") return;
        var aimTarget = ref.autoTarget;
        if (!(aimTarget.hp > 0)) return;
            // 计算到目标的轨迹
        var distX:Number = aimTarget._x - prop.shootX;
        var defaultHeight:Number = UnitUtil.calculateCenterOffset(aimTarget);
        var distY:Number = aimTarget._y - defaultHeight - prop.shootY;
        var distZ:Number = aimTarget.Z轴坐标 - prop.shootZ;
        
        // 计算水平速度，保持子弹速度恒定
        var speedX:Number = distX >= 0 ? prop.子弹速度 : -prop.子弹速度;
        var speedY:Number = speedX * distY / distX;
        
        // 限制垂直速度，确保不超过子弹速度上限
        if (speedY > prop.子弹速度 || speedY < -prop.子弹速度) {
            speedY = speedY >= 0 ? prop.子弹速度 : -prop.子弹速度;
            speedX = speedY * distX / distY;
        }
        
        // 设置子弹速度和Z轴比例参数
        prop.速度X = speedX;
        prop.速度Y = speedY;
        prop.ZY比例 = aimTarget.Z轴坐标 / (aimTarget._y - defaultHeight);
    });


    target.dispatcher.subscribe
    ("updateBullet", function () {
        if(target.攻击模式 !== "长枪") return;
        ref.fireRequest = true;
    });
};

/*--------------------------------------------------------
 * 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.G1111周期 = function (ref)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机  = ref.自机;
    var 长枪  = 自机.长枪_引用;
    var prevFrame = ref.currentFrame;
    var prevFiring = ref.isFiring;
    var prevTransforming = ref.isTransforming;

    /* ===== 0. 武器激活检测 ===== */
    var prevActive = ref.isWeaponActive;
    ref.isWeaponActive = (自机.攻击模式 === "长枪");
    
    
    if (!ref.isWeaponActive) {
        // 收枪：立即复位并清状态
        ref.isTransforming = ref.isFiring = ref.fireRequest = false;
        ref.currentFrame   = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 1. 读取并清除 fireRequest ===== */
    var wantFire = ref.fireRequest;
    ref.fireRequest = false;

    /* ===== 2. 冷却计数 ===== */
    if (ref.transformCooldown > 0) --ref.transformCooldown;

    /* ===== 3. 变形键触发 ===== */
    if (!ref.isTransforming && ref.transformCooldown == 0) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            ref.isTransforming   = true;
            ref.transformToRock  = !ref.isRocketMode;          // 目标形态
            ref.transformCooldown = ref.TRANSFORM_CD_F;

            // 选定起始帧（单向推进）
            ref.currentFrame = ref.transformToRock ?
                               ref.TRANSFORM_START : ref.TRANSFORM_END;
        }
    }

    /* ===== 4. 射击优先级处理（可打断变形和重触发） ===== */
    if (wantFire) {
        // 如果正在变形，停止变形并切换到目标形态
        if (ref.isTransforming) {
            ref.isTransforming = false;
            ref.isRocketMode   = ref.transformToRock;
            if (ref.是否为主角 && ref.globalData)
                ref.globalData.isRocketMode = ref.isRocketMode;
        }
        
        // 设置射击状态并跳转到第一帧
        ref.isFiring = true;
        ref.currentFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        长枪.gotoAndStop(ref.currentFrame);  // 立即绘制第一帧

        自机.isRocketMode = ref.isRocketMode;
        return; // 本周期只绘制第一帧，下周期开始推进
    }

    /* ===== 5. 动画推进 ===== */
    // 5-A 变形段 ---------------------------------------------------
    if (ref.isTransforming) {
        长枪.gotoAndStop(ref.currentFrame);  // 先绘制

        if (ref.transformToRock) {           // 步枪→导弹（增帧）
            if (ref.currentFrame < ref.TRANSFORM_END) {
                ++ref.currentFrame;          // 只增不减
            } else {                         // 到 30，切导弹待机
                ref.isTransforming = false;
                ref.isRocketMode   = true;
                ref.currentFrame   = ref.ROCKET_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isRocketMode = true;
            }
        } else {                             // 导弹→步枪（减帧）
            if (ref.currentFrame > ref.TRANSFORM_START) {
                --ref.currentFrame;          // 只减不增
            } else {
                ref.isTransforming = false;
                ref.isRocketMode   = false;
                ref.currentFrame   = ref.RIFLE_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isRocketMode = false;
            }
        }

        自机.isRocketMode = ref.isRocketMode;
        return; // 变形帧已绘制完毕
    }

    // 5-B 射击段 ----------------------------------------------------
    if (ref.isFiring) {
        var endF = ref.isRocketMode ? ref.ROCKET_END : ref.RIFLE_END;

        if (ref.currentFrame < endF) {
            ++ref.currentFrame;                // 只向前播
        } else {
            // 播到 15 / 45 后回待机
            ref.isFiring     = false;
            ref.currentFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        }
    } else {
        // 待机：保证在 1 / 31，不平滑渐变
        var idleFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        if (ref.currentFrame !== idleFrame) {
            ref.currentFrame = idleFrame;
        }
    }


    /* ===== 6. 激光模组自动锁定 ===== */
    if (ref.isWeaponActive) {
        var laser = 长枪.激光模组;
        if (laser != undefined) {
            var RAD_TO_DEG = 180 / Math.PI;
            var targetRotation = 0; // 默认归位到0度
            
            // 目标搜索冷却
            if (ref.targetSearchCooldown > 0) {
                ref.targetSearchCooldown--;
            }
            
            // 定期搜索新目标或验证当前目标
            if (ref.targetSearchCooldown <= 0) {
                ref.targetSearchCooldown = ref.TARGET_SEARCH_INTERVAL;
                
                // 如果没有目标或当前目标无效，搜索新目标
                if (ref.autoTarget == null || ref.autoTarget._x == undefined) {
                    if (typeof TargetCacheManager !== "undefined") {
                        ref.autoTarget = TargetCacheManager.findNearestEnemy(自机, ref.TARGET_SEARCH_INTERVAL);
                    }
                }

                自机.autoTarget = ref.autoTarget;
            }
            
            // 如果有有效目标，计算追踪角度
            if (ref.autoTarget != null && ref.autoTarget._x != undefined) {
                var enemyGlobalPos = {x: ref.autoTarget._x, y: ref.autoTarget._y};
                if (typeof UnitUtil !== "undefined" && UnitUtil.getAimPoint) {
                    enemyGlobalPos = UnitUtil.getAimPoint(ref.autoTarget);
                }
                
                长枪.globalToLocal(enemyGlobalPos);
                
                var dx = enemyGlobalPos.x - laser._x;
                var dy = enemyGlobalPos.y - laser._y;
                var angleRadians = Math.atan2(dy, dx);
                
                if (!isNaN(angleRadians)) {
                    var calculatedAngle = angleRadians * RAD_TO_DEG;
                    
                    // 检查是否超出角度限制
                    if (calculatedAngle > ref.laserMaxAngle || calculatedAngle < ref.laserMinAngle) {
                        // 超出限制，清除目标
                        ref.autoTarget = null;
                        targetRotation = 0;
                    } else {
                        // 在限制内，追踪目标
                        targetRotation = calculatedAngle;
                        
                        // 渲染锁定视觉效果
                        if (ref.autoTarget.aabbCollider) {
                            AABBRenderer.renderAABB(ref.autoTarget.aabbCollider, 0, ref.isRocketMode ? "scan4" : "scan1");
                        }
                    }
                }
            }
            
            // 平滑旋转到目标角度
            var currentRotation = ref.laserRotation;
            var delta = targetRotation - currentRotation;
            
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
        }
    }

    /* ===== 7. 绘制 ===== */
    长枪.gotoAndStop(ref.currentFrame);
    自机.isRocketMode = ref.isRocketMode;
};