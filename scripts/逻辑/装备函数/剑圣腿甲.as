/**
 * 剑圣腿甲 - 装备生命周期函数
 *
 * 功能特性：
 * - 在底层背景上挂载"武士铁血剑匣"
 * - 跟随身体_引用的位置和旋转
 * - 剑匣常驻显示，无展开/收缩动画
 * - 装载"刀剑乱舞"兵器战技
 *
 * 进阶等级效果：
 * - 无进阶：不挂载剑匣，直接移除周期函数
 * - 二阶：挂载剑匣 + 刀剑乱舞战技（CD 30秒）
 * - 三阶：挂载剑匣 + 刀剑乱舞战技（CD 26秒）
 * - 四阶：挂载剑匣 + 刀剑乱舞战技（CD 24秒）
 *
 * 平衡设计：
 * - 刀剑乱舞触发时，手甲会获得额外70%空手加成（持续12-18秒）
 * - 较长的CD设计用于区分腕刃流（单挑）和刀剑流（对群）玩法
 * - 腕刃流：使用刀剑乱舞获得100%威力，适合Boss战
 * - 刀剑流：不依赖刀剑乱舞，配合肩炮连杀减CD，适合割草
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - weapon: 武器素材名称（默认"武士铁血剑匣"）
 *   - tier_2/tier_3/tier_4: 各进阶等级的配置节点
 *     - skillCd: 战技冷却时间毫秒（二阶30000，三阶26000，四阶24000）
 */
_root.装备生命周期函数.剑圣腿甲初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 获取装备进阶等级
    var equipItem:Object = target[ref.装备类型];
    var tier:String = equipItem && equipItem.value ? equipItem.value.tier : null;
    ref.tier = tier;

    // 无进阶：不挂载剑匣，直接移除周期函数
    if (!tier) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    // 进阶等级映射
    var tierNum:String;
    switch (tier) {
        case "二阶": tierNum = "2"; break;
        case "三阶": tierNum = "3"; break;
        case "四阶": tierNum = "4"; break;
        default:
            _root.装备生命周期函数.移除周期函数(ref);
            return;
    }

    // 从XML读取进阶配置
    var tierConfig:Object = param ? param["tier_" + tierNum] : null;

    // 武器配置（从XML读取）
    ref.weaponAsset = param.weapon ? param.weapon : "武士铁血剑匣";
    ref.weaponDepth = 10002; // 与胸甲、手甲错开深度
    ref.weaponName = ref.weaponAsset + "剑圣_腿甲";

    // 挂载剑匣到底层背景
    var layer:MovieClip = target.底层背景;
    var weapon:MovieClip = layer.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
    weapon.stop();
    ref.weapon = weapon;

    // 缓存坐标转换用的点对象，避免每帧创建
    ref.localPoint = {x: 0, y: 0};
    ref.p0 = {x: 0, y: 0};
    ref.pX = {x: 100, y: 0};
    ref.pY = {x: 0, y: 100};

    // ========== 装载战技 ==========
    // 从XML进阶配置读取CD，或使用默认值
    // 默认CD按进阶等级：二阶30秒，三阶26秒，四阶24秒
    var defaultCds:Array = [];
    defaultCds[2] = 30000;  // 二阶30秒
    defaultCds[3] = 26000;  // 三阶26秒
    defaultCds[4] = 24000;  // 四阶24秒
    var skillCd:Number = (tierConfig && tierConfig.skillCd) ? Number(tierConfig.skillCd) : defaultCds[Number(tierNum)];

    var skillConfig:Object = {
        skillname: "刀剑乱舞",
        cd: skillCd,
        mp: 80
    };

    // 装载主动战技到"空手"攻击模式（配合腕刃使用）
    target.装载主动战技(skillConfig, "空手");

    // 如果是主角，刷新战技栏图标
    if (ref.是否为主角) {
        _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
    }

    // 订阅玩家模板重新初始化事件
    target.dispatcher.subscribe("UnitReInitialized", function() {
        // 清理残留weapon
        var layer:MovieClip = target.底层背景;
        if (layer[ref.weaponName]) {
            layer[ref.weaponName].removeMovieClip();
        }
    }, target);

    // 身体引用加载时同步渲染
    target.syncRefs.身体_引用 = true;
    target.dispatcher.subscribe("身体_引用", function(unit) {
        _root.装备生命周期函数.剑圣腿甲渲染更新(ref);
    }, target);

    // _root.发布消息("剑圣剑匣系统启动 - " + tier);
};

/**
 * 剑圣腿甲 - 渲染更新函数
 * 更新weapon的位置和旋转，跟随身体_引用
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣腿甲渲染更新 = function(ref:Object) {
    var weapon:MovieClip = ref.weapon;
    var target:MovieClip = ref.自机;
    var body:MovieClip = target.身体_引用;

    if (!weapon || !body) {
        return;
    }

    // weapon 的容器（底层背景）
    var container:MovieClip = target.底层背景;

    // 位移：以 身体_引用 的原点作为挂点
    var localPoint:Object = ref.localPoint;
    localPoint.x = 0;
    localPoint.y = 0;
    body.localToGlobal(localPoint);
    container.globalToLocal(localPoint);
    weapon._x = localPoint.x;
    weapon._y = localPoint.y;

    // 旋转/翻转：用坐标变换求真实朝向，兼容动作中身体引用被镜像
    var p0:Object = ref.p0;
    var pX:Object = ref.pX;
    var pY:Object = ref.pY;
    p0.x = 0;   p0.y = 0;
    pX.x = 100; pX.y = 0;
    pY.x = 0;   pY.y = 100;

    body.localToGlobal(p0);
    body.localToGlobal(pX);
    body.localToGlobal(pY);
    container.globalToLocal(p0);
    container.globalToLocal(pX);
    container.globalToLocal(pY);

    var vxX:Number = pX.x - p0.x;
    var vxY:Number = pX.y - p0.y;
    var vyX:Number = pY.x - p0.x;
    var vyY:Number = pY.y - p0.y;

    var angle:Number = Math.atan2(vxY, vxX) * 180 / Math.PI;
    var det:Number = vxX * vyY - vxY * vyX; // <0 表示发生镜像（左右翻转）
    var mirrored:Boolean = (det < 0);

    if (mirrored) {
        angle -= 180;
        if (weapon._xscale > 0) {
            weapon._xscale = -weapon._xscale;
        }
    } else {
        if (weapon._xscale < 0) {
            weapon._xscale = -weapon._xscale;
        }
    }
    weapon._rotation = angle;
    weapon.gotoAndStop(target.man.剑匣判定 ? 2 : 1);
};

/**
 * 剑圣腿甲 - 周期函数
 * 剑匣常驻显示，仅需更新位置
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣腿甲周期 = function(ref:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var tier:String = ref.tier;
    if (!tier) {
        return;
    }

    // 确保weapon存在
    if (!ref.weapon) {
        var target:MovieClip = ref.自机;
        var layer:MovieClip = target.底层背景;
        var weapon:MovieClip = layer.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
        weapon.stop();
        ref.weapon = weapon;
    }

    // 更新位置
    _root.装备生命周期函数.剑圣腿甲渲染更新(ref);
};
