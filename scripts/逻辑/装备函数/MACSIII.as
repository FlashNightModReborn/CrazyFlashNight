
import org.flashNight.neur.Event.*;

_root.装备生命周期函数.MACSIII初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // --- 性能参数常量化 ---
    ref.maxSpinCount = param.maxSpinCount || 29;            // 最大连射计数 
    ref.spinUpAmount = param.spinUpAmount || 5;             // 每次射击增加的连射计数 
    ref.spinSpeedFactor = param.spinSpeedFactor || 0.1;     // 连射计数转换为转速的系数
    ref.spinDownRate = param.spinDownRate || 0.33;          // 连射计数的自然衰减率

    // --- 状态变量 ---
    ref.gunFrame = 1;              // 当前动画帧 (浮点数)
    ref.fireCount = 0;             // 当前连射计数
    ref.isFiring = false;          // 是否正在射击 


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
    var execBonus  :Number = (upgradeLevel >= executeLevel)  ? 10 : 0;
    var lifeBonus  :Number = (upgradeLevel >= lifeStealLevel)? 18 : 0;

    // —— 组合索引：0b00‑0b11（直观点就是 0‑3）——————————
    var combo:Number = (execBonus ? 1 : 0) | (lifeBonus ? 2 : 0);

    // —— 预先声明 4 个瘦身模板—————
    function mkHandler0(ref:Object):Function {      // 无任何额外效果
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
    function mkHandlerE(ref:Object):Function {      // 只有斩杀
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play(); 
            prop.区域定位 = area;
            if(mc.MACSIII超载打击许可) {
                prop.斩杀 = 8;         // 常量写死，0 分支
            } else {
                prop.斩杀 = 0;
            }  
        };
    }
    function mkHandlerL(ref:Object):Function {      // 只有吸血，虽然没用但写了再说
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
    function mkHandlerEL(ref:Object):Function {     // 同时斩杀 + 吸血
        return function () {
            ref.isFiring = true;
            var mc = ref.自机;
            var gun = mc.长枪_引用;
            var prop = mc.man.子弹属性;
            var area = gun.枪口位置;
            spark.play(); spark._visible = true;
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

    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount, ref.maxSpinCount))) || 
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));


    // 2. 如果枪在转动，则计算并更新动画
    if (ref.fireCount > 0) {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor;
        ref.gunFrame += currentSpeed;

        // 使用高效的单行取模运算来处理动画帧循环
        if (ref.gunFrame > gun._totalFrames) {
            ref.gunFrame = ((ref.gunFrame - 1) % gun._totalFrames) + 1;
        }
        
        gun.gotoAndStop(Math.floor(ref.gunFrame));
    } else if(gun._currentFrame != 1) {
        // 如果不在射击状态且当前帧不是第一帧，则重置到第一帧
        gun.gotoAndStop(1);
    }

    // 3. 重置射击状态
    ref.isFiring = false;

    if(target.MACSIII超载打击许可) {
        if(--target.MACSIII超载打击剩余时间 < 0) {
            target.MACSIII超载打击许可 = false;
        }
    }
};