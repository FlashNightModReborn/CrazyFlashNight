import org.flashNight.neur.Event.*;

_root.装备生命周期函数.MACSIII初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // --- 状态变量 ---
    ref.gunFrame = 1.0;              // 当前动画帧 (浮点数，支持平滑过渡)
    ref.isFiring = false;            // 是否正在射击
    ref.animBudget = 0.0;            // 剩余的动画帧数 (浮点数支持)
    
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
            ref.自机.man.子弹属性.区域定位area = ref.自机.长枪_引用.枪口位置;
        };
    }
    
    function mkHandlerE(ref:Object):Function {
        // 只有斩杀
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if(mc.MACSIII超载打击许可) {
                prop.斩杀 = 8;
            }
        };
    }
    
    function mkHandlerL(ref:Object):Function {
        // 只有吸血
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if(mc.MACSIII超载打击许可) {
                prop.吸血 = 10;
            }
        };
    }
    
    function mkHandlerEL(ref:Object):Function {
        // 同时斩杀 + 吸血
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if(mc.MACSIII超载打击许可) {
                prop.斩杀 = 10;
                prop.吸血 = 18;
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
    var currentFrame:Number = ref.gunFrame;
    
    // 动态调整动画预算
    if(ref.isFiring) ref.animBudget += 10.0;
    if(ref.animBudget > 60.0) ref.animBudget = 60.0; // 限制最大预算
    
    // 平滑的动画帧推进系统
    var frameAdvance:Number = 0.0;
    
    if(ref.animBudget >= 1.0) {
        // 预算充足时：满速前进
        frameAdvance = 1.0;
        ref.animBudget -= 1.0;
    } else if(ref.animBudget > 0.0) {
        // 预算不足时：按剩余预算比例减速
        frameAdvance = ref.animBudget;
        ref.animBudget = 0.0; // 消耗完所有剩余预算
    }
    // else: 预算为0时，frameAdvance保持0.0，完全停止
    
    // 推进动画帧
    if(frameAdvance > 0.0) {
        currentFrame += frameAdvance;
        
        // 循环处理（保持浮点数精度）
        if(currentFrame > totalFrames) {
            currentFrame -= totalFrames;
        }
    }
    
    ref.gunFrame = currentFrame;
    
    // 计算显示帧（向下取整）
    var displayFrame:Number = Math.floor(ref.gunFrame);
    if(displayFrame < 1) displayFrame = 1;
    if(displayFrame > totalFrames) displayFrame = totalFrames;
    
    var animFrame:Number = displayFrame;
    
    // 超载打击效果
    if(target.MACSIII超载打击许可) {
        if(--target.MACSIII超载打击剩余时间 < 0) {
            target.MACSIII超载打击许可 = false;
        }
        animFrame += totalFrames; // 超载打击时动画帧偏移
        var prop = target.man.子弹属性;
        
        prop.斩杀 = 0;
        prop.吸血 = 0;
    }
    
    gun.gotoAndStop(animFrame);
    
    // 重置射击状态
    ref.isFiring = false;
};