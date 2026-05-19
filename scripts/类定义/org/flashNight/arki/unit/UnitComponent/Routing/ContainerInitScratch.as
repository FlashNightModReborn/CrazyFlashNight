import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerInitScratch — 容器化 attachMovie 的 initObject scratch 池
 *
 * 目的：替代 _root.路由基础.构建容器初始化对象 系列每次 new Object literal 的写法，
 *       消除动作切换热路径上的小对象 GC 压力。
 *
 * 模式：纯 static + static method self-replacing（参考 BaseRandomNumberEngine.getInstance
 *       已验证的 static self-replacing 模板，见
 *       scripts/类定义/org/flashNight/naki/RandomNumberEngine/BaseRandomNumberEngine.as）
 *       首次调用 getXxx 通过 RoutingFieldMap + assembleFromMap 完成 scratch 装配 + 把 getXxx
 *       本身替换为只刷 transform 的 closure；后续调用直接走 closure，
 *       仅刷新 4 个 transform 字段（_x/_y/_xscale/_yscale）。
 *
 * scratch 复用安全性：AS2 attachMovie(linkage, name, depth, initObject) 同步 enumerate
 *       initObject 的 own 属性 copy 到新 MovieClip，调用返回后 initObject 立即可复用。
 *
 * 字段对齐：装配字段由 [[RoutingFieldMap]] 维护（PUBLIC_FIELDS / UNARMED_FIELDS /
 *       WEAPON_FIELDS），与三个生产路由文件 + 容器 XML 末帧搓招/派生需求对齐。
 *
 * 异常契约：装配代码不得抛异常。异常会跳过末尾的 getXxx = function(){...} 替换语句，
 *       下次调用又走 trampoline 重新装配。良性退化但损失性能，
 *       boot 阶段须保证 _root.技能函数 / _root.空手攻击路由 已就绪后再调用。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerInitScratch {

    private static var __publicScratch:Object;
    private static var __unarmedScratch:Object;
    private static var __weaponScratch:Object;

    // ════════════════════════════════════════════════════════════════════
    // 装配 helper：读取 RoutingFieldMap 条目，按 [dst, srcRoot, srcKey] 写入 scratch。
    // 公开为 public static 便于 testloader 直接 assemble 任意 fieldMap 做对照测试。
    //
    // sources 参数（可选）：装配源对象，默认 = _root。
    //   生产路径：getXxx 不传 sources → fallback _root，行为同旧版。
    //   测试路径：传 fakeSources（sentinel 哨兵值）→ 反向校验 RoutingFieldMap 的
    //     [srcRoot, srcKey] 真的映射到了正确的来源；如果字段表里 srcRoot/srcKey 写
    //     错了（typo / 改错 dict 名），sentinel 测试会立刻 FAIL，弥补"测试与被测代
    //     码读同一份 _root 路径"导致的同义反复盲点。
    //   形参不标类型：兼容 fakeSources 是 plain Object 的场景，避免 strict 类型注解
    //     被生产 _root（MovieClip）和 fake plain Object 同时满足时的 IDE 类型摩擦。
    // ════════════════════════════════════════════════════════════════════
    public static function assembleFromMap(c:MovieClip, fields:Array, sources):Object {
        if (sources == undefined) {
            sources = _root;
        }
        var out:Object = {
            __isDynamicMan: true,
            _x: c._x,
            _y: c._y,
            _xscale: c._xscale,
            _yscale: c._yscale
        };
        var len:Number = fields.length;
        for (var i:Number = 0; i < len; i++) {
            var entry = fields[i];
            out[entry[0]] = sources[entry[1]][entry[2]];
        }
        return out;
    }

    // ═══════ getPublic — 技能 / 战技容器共用 ═══════

    public static function getPublic(c:MovieClip):Object {
        __publicScratch = assembleFromMap(c, RoutingFieldMap.PUBLIC_FIELDS);
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
        __unarmedScratch = assembleFromMap(c, RoutingFieldMap.UNARMED_FIELDS);
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
        __weaponScratch = assembleFromMap(c, RoutingFieldMap.WEAPON_FIELDS);
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
