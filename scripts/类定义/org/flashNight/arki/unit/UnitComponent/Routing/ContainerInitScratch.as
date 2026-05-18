/**
 * ContainerInitScratch — 容器化 attachMovie 的 initObject scratch 池
 *
 * 目的：替代 _root.路由基础.构建容器初始化对象 系列每次 new Object literal 的写法，
 *       消除动作切换热路径上的小对象 GC 压力。
 *
 * 模式：纯 static + static method self-replacing（参考 BaseRandomNumberEngine.getInstance
 *       已验证的 static self-replacing 模板，见
 *       scripts/类定义/org/flashNight/naki/RandomNumberEngine/BaseRandomNumberEngine.as）
 *       首次调用 getXxx 完成 scratch 完整装配 + 把 getXxx 本身替换为只刷 transform 的 closure；
 *       后续调用直接走 closure，仅刷新 4 个 transform 字段（_x/_y/_xscale/_yscale）。
 *
 * scratch 复用安全性：AS2 attachMovie(linkage, name, depth, initObject) 同步 enumerate
 *       initObject 的 own 属性 copy 到新 MovieClip，调用返回后 initObject 立即可复用。
 *
 * 字段对齐：装配内容必须与 source location 保持一致：
 *       - getPublic   ↔ scripts/引擎/引擎_fs_路由基础.as 构建容器初始化对象
 *       - getUnarmed  ↔ scripts/引擎/引擎_fs_空手攻击路由.as 构建空手攻击容器初始化对象
 *       - getWeapon   ↔ scripts/引擎/引擎_fs_兵器攻击路由.as 构建兵器攻击容器初始化对象
 *
 * 异常契约：装配代码不得抛异常。异常会跳过末尾的 getXxx = function(){...} 替换语句，
 *       下次调用又走 trampoline 重新装配。良性退化但损失性能，
 *       boot 阶段须保证 _root.技能函数 / _root.空手攻击路由 已就绪后再调用。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerInitScratch {

    private static var __publicScratch:Object;
    private static var __unarmedScratch:Object;
    private static var __weaponScratch:Object;

    // ═══════ getPublic — 技能 / 战技容器共用 ═══════

    public static function getPublic(c:MovieClip):Object {
        __publicScratch = {
            __isDynamicMan: true,
            _x: c._x,
            _y: c._y,
            _xscale: c._xscale,
            _yscale: c._yscale,
            攻击时移动: _root.技能函数.攻击时移动,
            攻击时后退移动: _root.技能函数.攻击时移动,
            攻击时按键四向移动: _root.技能函数.攻击时按键四向移动,
            攻击时可改变移动方向: _root.技能函数.攻击时可改变移动方向,
            攻击时可斜向改变移动方向: _root.技能函数.攻击时可斜向改变移动方向,
            攻击时斜向移动: _root.技能函数.攻击时斜向移动,
            攻击时可斜向改变移动方向2: _root.技能函数.攻击时可斜向改变移动方向2,
            获取移动方向: _root.技能函数.获取移动方向
        };
        getPublic = function(c:MovieClip):Object {
            __publicScratch._x = c._x;
            __publicScratch._y = c._y;
            __publicScratch._xscale = c._xscale;
            __publicScratch._yscale = c._yscale;
            return __publicScratch;
        };
        return __publicScratch;
    }

    // ═══════ getUnarmed — 空手攻击容器 ═══════

    public static function getUnarmed(c:MovieClip):Object {
        __unarmedScratch = {
            __isDynamicMan: true,
            _x: c._x,
            _y: c._y,
            _xscale: c._xscale,
            _yscale: c._yscale,
            // 空手专用移动函数（覆盖 base 的通用版本）
            攻击时移动: _root.空手攻击路由.攻击时移动,
            攻击时后退移动: _root.空手攻击路由.攻击时移动,
            攻击时按键四向移动: _root.空手攻击路由.攻击时按键四向移动,
            攻击时可改变移动方向: _root.空手攻击路由.攻击时可改变移动方向,
            攻击时可斜向改变移动方向: _root.空手攻击路由.攻击时可斜向改变移动方向,
            攻击时斜向移动: _root.空手攻击路由.攻击时斜向移动,
            攻击时可斜向改变移动方向2: _root.空手攻击路由.攻击时可斜向改变移动方向2,
            获取移动方向: _root.技能函数.获取移动方向,
            变招判定: _root.空手攻击路由.变招判定,
            // 搓招/派生函数
            空手攻击搓招: _root.技能函数.空手攻击搓招,
            诛杀步可派生搓招: _root.技能函数.诛杀步可派生搓招,
            后撤步可派生搓招: _root.技能函数.后撤步可派生搓招,
            波动拳可派生搓招: _root.技能函数.波动拳可派生搓招,
            能量喷泉可派生搓招: _root.技能函数.能量喷泉可派生搓招,
            燃烧指节可派生搓招: _root.技能函数.燃烧指节可派生搓招,
            狼炮可派生搓招: _root.技能函数.狼炮可派生搓招,
            连环踢可派生搓招: _root.技能函数.连环踢可派生搓招
        };
        getUnarmed = function(c:MovieClip):Object {
            __unarmedScratch._x = c._x;
            __unarmedScratch._y = c._y;
            __unarmedScratch._xscale = c._xscale;
            __unarmedScratch._yscale = c._yscale;
            return __unarmedScratch;
        };
        return __unarmedScratch;
    }

    // ═══════ getWeapon — 兵器攻击容器 ═══════

    public static function getWeapon(c:MovieClip):Object {
        __weaponScratch = {
            __isDynamicMan: true,
            _x: c._x,
            _y: c._y,
            _xscale: c._xscale,
            _yscale: c._yscale,
            // 兵器专用移动函数（覆盖 base 的 攻击时移动 / 攻击时按键四向移动）
            攻击时移动: _root.技能函数.兵器攻击时移动,
            攻击时按键四向移动: _root.技能函数.兵器攻击时按键四向移动,
            // 通用移动函数（兵器未覆盖，沿用 base）
            攻击时后退移动: _root.技能函数.攻击时移动,
            攻击时可改变移动方向: _root.技能函数.攻击时可改变移动方向,
            攻击时可斜向改变移动方向: _root.技能函数.攻击时可斜向改变移动方向,
            攻击时斜向移动: _root.技能函数.攻击时斜向移动,
            攻击时可斜向改变移动方向2: _root.技能函数.攻击时可斜向改变移动方向2,
            获取移动方向: _root.技能函数.获取移动方向,
            // 兵器攻击核心函数
            变招判定: _root.技能函数.变招判定,
            刀口触发特效: _root.技能函数.刀口触发特效,
            兵器攻击: _root.技能函数.兵器攻击,
            // 搓招/派生函数（对齐 flashswf/arts/things0/LIBRARY/容器/兵器攻击容器/兵器攻击.xml）
            轻型武器攻击搓招: _root.技能函数.轻型武器攻击搓招,
            大型武器攻击搓招: _root.技能函数.大型武器攻击搓招,
            剑气释放搓招窗口: _root.技能函数.剑气释放搓招窗口,
            飞沙走石搓招窗口: _root.技能函数.飞沙走石搓招窗口,
            贯穿突刺搓招窗口: _root.技能函数.贯穿突刺搓招窗口,
            蓄力重劈搓招窗口: _root.技能函数.蓄力重劈搓招窗口,
            十六夜月华可派生: _root.技能函数.十六夜月华可派生,
            千山破晓钟可派生: _root.技能函数.千山破晓钟可派生,
            幻影剑舞可派生: _root.技能函数.幻影剑舞可派生,
            百万突刺可派生: _root.技能函数.百万突刺可派生,
            粉碎切割可派生: _root.技能函数.粉碎切割可派生,
            猎影十字可派生: _root.技能函数.猎影十字可派生,
            空坠强袭可派生: _root.技能函数.空坠强袭可派生,
            次元斩可派生: _root.技能函数.次元斩可派生,
            追地祀可派生: _root.技能函数.追地祀可派生,
            月光斩可派生: _root.技能函数.月光斩可派生,
            见切可派生: _root.技能函数.见切可派生
        };
        getWeapon = function(c:MovieClip):Object {
            __weaponScratch._x = c._x;
            __weaponScratch._y = c._y;
            __weaponScratch._xscale = c._xscale;
            __weaponScratch._yscale = c._yscale;
            return __weaponScratch;
        };
        return __weaponScratch;
    }
}
