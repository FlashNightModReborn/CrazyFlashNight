import org.flashNight.neur.Event.*;

_root.装备生命周期函数.MACSIII初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // --- 状态变量 ---
    ref.gunFrame = 1.0;              // 当前动画帧 (浮点数，支持平滑过渡)
    ref.fireCount = 0;               // 当前连射计数
    ref.isFiring = false;            // 是否正在射击
    ref.animSpeed = 0.15;            // 基础动画速度（空闲时）
    ref.fireAnimSpeed = 1;         // 射击时动画速度（调整为不超过1.0）
    ref.currentAnimSpeed = ref.animSpeed; // 当前实际动画速度
    
    var upgradeLevel:Number;
    if(_root.控制目标 == target._name) {
        var equipment = _root.物品栏.装备栏;
        upgradeLevel = equipment.getLevel("长枪");
    } else {
        upgradeLevel = _root.主角函数.获取人形怪强化等级(target.等级, target.名字);
    }
    
    var executeLevel:Number = param.executeLevel || 3;
    var lifeStealLevel:Number = param.lifeStealLevel || 6;
    
    // ── 初始化阶段（只跑一次）─────────────────────────────────────────────────
    var execBonus:Number = (upgradeLevel >= executeLevel) ? 10 : 0;
    var lifeBonus:Number = (upgradeLevel >= lifeStealLevel) ? 18 : 0;
    
    // —— 组合索引：0b00‑0b11（直观点就是 0‑3）——————————
    var combo:Number = (execBonus ? 1 : 0) | (lifeBonus ? 2 : 0);
    
    // —— 预先声明 4 个瘦身模板—————
    function mkHandler0(ref:Object):Function {
        // 无任何额外效果
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play();
            
            prop.区域定位 = area;
        };
    }
    
    function mkHandlerE(ref:Object):Function {
        // 只有斩杀
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play();
            
            prop.区域定位 = area;
            if(mc.MACSIII超载打击许可) {
                prop.斩杀 = 8;
            } else {
                prop.斩杀 = 0;
            }
        };
    }
    
    function mkHandlerL(ref:Object):Function {
        // 只有吸血
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play();
            
            prop.区域定位 = area;
            if(mc.MACSIII超载打击许可) {
                prop.吸血 = 10;
            } else {
                prop.吸血 = 0;
            }
        };
    }
    
    function mkHandlerEL(ref:Object):Function {
        // 同时斩杀 + 吸血
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play();
            spark._visible = true;
            
            prop.区域定位 = area;
            if(mc.MACSIII超载打击许可) {
                prop.斩杀 = 10;
                prop.吸血 = 18;
            } else {
                prop.斩杀 = 0;
                prop.吸血 = 0;
            }
        };
    }
    
    // —— 选择适当模板一次性绑定 ————————————————
    var handlerTable:Array = [mkHandler0, mkHandlerE, mkHandlerL, mkHandlerEL];
    target.dispatcher.subscribe("长枪射击", handlerTable[combo](ref));
};

_root.装备生命周期函数.MACSIII周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var totalFrames:Number = 4;
    
    // 动态调整动画速度
    if(ref.isFiring) {
        // 射击时加速动画，营造电锯高速转动的效果
        ref.currentAnimSpeed += (ref.fireAnimSpeed - ref.currentAnimSpeed) * 0.2;
    } else {
        // 非射击时恢复正常速度，但保持持续转动
        ref.currentAnimSpeed += (ref.animSpeed - ref.currentAnimSpeed) * 0.1;
    }
    
    // 限制最大前进速度，避免跳帧导致的不连贯
    ref.currentAnimSpeed = Math.min(ref.currentAnimSpeed, 1.0);
    
    // 持续推进动画帧（电锯应该一直转动）
    ref.gunFrame += ref.currentAnimSpeed;
    
    // 循环处理帧数（使用浮点数取模运算）
    if(ref.gunFrame > totalFrames) {
        ref.gunFrame -= totalFrames; // 保持浮点数精度的循环
    }
    
    // 计算实际显示的帧数（向下取整并确保在1-4范围内）
    var displayFrame:Number = Math.floor(ref.gunFrame);
    if(displayFrame < 1) displayFrame = 1;
    if(displayFrame > totalFrames) displayFrame = totalFrames;
    
    var animFrame:Number = displayFrame;
    
    // 超载打击效果
    if(target.MACSIII超载打击许可) {
        if(--target.MACSIII超载打击剩余时间 < 0) {
            target.MACSIII超载打击许可 = false;
        }
        animFrame += 4; // 超载打击时动画帧偏移
        
    }
    
    gun.gotoAndStop(animFrame);
    
    // 重置射击状态（放在最后，确保动画速度调整完成）
    ref.isFiring = false;
    
    _root.发布消息(animFrame);
};