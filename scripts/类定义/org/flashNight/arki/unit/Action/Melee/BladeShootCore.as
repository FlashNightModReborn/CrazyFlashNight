/**
 * BladeShootCore - 刀口位置子弹生成核心
 *
 * 职责：
 * - 根据刀口数量生成近战子弹
 * - 按刀口数精确展开，避免冗余分支和节点查询
 * - 提供函数工厂模式，保持 this 绑定
 *
 * 设计原则：
 * - 纯静态类，所有方法和缓存都是静态的
 * - 通过 getShootFunction() 返回绑定了类方法的函数
 * - 编译期类型检查，IDE 友好
 *
 * 使用方式：
 * ```actionscript
 * // 在单位初始化时获取函数
 * this.刀口位置生成子弹 = BladeShootCore.getShootFunction();
 *
 * // 调用时 this 自然指向单位
 * this.刀口位置生成子弹(子弹参数);
 * ```
 *
 * 刀口数统计（基于193把武器）：
 * - 3刀口：142把 (74%)
 * - 4刀口：38把 (20%)
 * - 5刀口：9把 (5%)
 * - 其他：<1%
 */
class org.flashNight.arki.unit.Action.Melee.BladeShootCore {

    // ========== 静态缓存 ==========

    /** 坐标变换缓存点（逐点变换用） */
    private static var pointCache:Object = {x: 0, y: 0};

    /** 矩阵变换用临时点 */
    private static var trans_p0:Object = {x: 0, y: 0};
    private static var trans_px:Object = {x: 0, y: 0};
    private static var trans_py:Object = {x: 0, y: 0};

    /** 调试开关 */
    public static var debug:Boolean = false;

    /** 缓存的射击函数引用 */
    private static var _cachedShootFunc:Function = null;

    // ========== 函数工厂 ==========

    /**
     * 获取刀口位置生成子弹函数
     *
     * 返回一个函数，该函数在调用时 this 指向调用者（单位对象）
     * 内部委托给 BladeShootCore.shoot 执行实际逻辑
     *
     * @return Function 可绑定到单位的射击函数
     */
    public static function getShootFunction():Function {
        if (_cachedShootFunc == null) {
            _cachedShootFunc = function(子弹参数:Object):Void {
                BladeShootCore.shoot(this, 子弹参数);
                // _root.发布消息("[BladeShootCore] " + this._name + " 执行刀口位置子弹生成。");
            };
        }
        return _cachedShootFunc;
    }

    // ========== 核心方法 ==========

    /**
     * 刀口位置生成子弹（主入口）
     *
     * @param unit:MovieClip 单位对象（自机）
     * @param params:Object 子弹参数覆盖
     */
    public static function shoot(unit:MovieClip, params:Object):Void {
        var shootFunc:Function = _root.子弹区域shoot传递;
        var 装扮:MovieClip = unit.man.刀.刀.装扮;
        var gameworld:MovieClip = _root.gameworld;

        // 构建基础子弹属性
        var 子弹属性:Object = {
            发射者: unit._name,
            声音: "",
            霰弹值: 1,
            子弹散射度: 0,
            发射效果: "",
            子弹种类: "近战子弹",
            子弹速度: 0,
            击中地图效果: "",
            击中后子弹的效果: "空手攻击火花",
            shootZ: unit.Z轴坐标,
            子弹威力: 0,
            Z轴攻击范围: 10,
            击倒率: 10
        };

        // 参数覆盖
        for (var key:String in params) {
            子弹属性[key] = params[key];
        }

        // 获取预缓存的刀口数
        var bladeCount:Number = unit.刀_刀口数;

        // 调试计数
        var bulletCount:Number = 0;
        var debugUnitName:String;
        var debugBladeCount:Number;

        if (debug) {
            debugUnitName = unit._name;
            debugBladeCount = bladeCount;
            var originalShoot:Function = shootFunc;
            shootFunc = function(attr:Object):Void {
                bulletCount++;
                originalShoot(attr);
            };
        }

        // 按刀口数分发到对应的处理方法
        if (bladeCount == 3) {
            shoot3(装扮, gameworld, 子弹属性, shootFunc);
        } else if (bladeCount == 4) {
            shoot4(装扮, gameworld, 子弹属性, shootFunc);
        } else if (bladeCount >= 5) {
            shoot5Plus(装扮, gameworld, 子弹属性, shootFunc, bladeCount);
        } else if (bladeCount == 2) {
            shoot2(装扮, gameworld, 子弹属性, shootFunc);
        } else {
            shootFallback(装扮, gameworld, 子弹属性, shootFunc);
        }

        // 调试输出
        if (debug) {
            _root.服务器.发布服务器消息("[BladeShootCore] " + debugUnitName + " | 预设:" + debugBladeCount + " | 实际:" + bulletCount);
        }
    }

    // ========== 按刀口数精确展开的内部方法 ==========

    /**
     * 2刀口快速路径（极少数武器）
     */
    private static function shoot2(装扮:MovieClip, gameworld:MovieClip, 子弹属性:Object, shootFunc:Function):Void {
        var myPoint:Object = pointCache;
        var node1:MovieClip = 装扮.刀口位置1;
        var node2:MovieClip = 装扮.刀口位置2;

        // 刀口1
        myPoint.x = node1._x;
        myPoint.y = node1._y;
        装扮.localToGlobal(myPoint);
        gameworld.globalToLocal(myPoint);
        子弹属性.shootX = myPoint.x;
        子弹属性.shootY = myPoint.y;
        子弹属性.区域定位area = node1;
        shootFunc(子弹属性);

        // 刀口2
        myPoint.x = node2._x;
        myPoint.y = node2._y;
        装扮.localToGlobal(myPoint);
        gameworld.globalToLocal(myPoint);
        子弹属性.shootX = myPoint.x;
        子弹属性.shootY = myPoint.y;
        子弹属性.区域定位area = node2;
        shootFunc(子弹属性);
    }

    /**
     * 3刀口快速路径（最常见：74%的武器）
     * 逐点变换，无需矩阵预计算
     */
    private static function shoot3(装扮:MovieClip, gameworld:MovieClip, 子弹属性:Object, shootFunc:Function):Void {
        var myPoint:Object = pointCache;
        var node1:MovieClip = 装扮.刀口位置1;
        var node2:MovieClip = 装扮.刀口位置2;
        var node3:MovieClip = 装扮.刀口位置3;

        // 刀口1
        myPoint.x = node1._x;
        myPoint.y = node1._y;
        装扮.localToGlobal(myPoint);
        gameworld.globalToLocal(myPoint);
        子弹属性.shootX = myPoint.x;
        子弹属性.shootY = myPoint.y;
        子弹属性.区域定位area = node1;
        shootFunc(子弹属性);

        // 刀口2
        myPoint.x = node2._x;
        myPoint.y = node2._y;
        装扮.localToGlobal(myPoint);
        gameworld.globalToLocal(myPoint);
        子弹属性.shootX = myPoint.x;
        子弹属性.shootY = myPoint.y;
        子弹属性.区域定位area = node2;
        shootFunc(子弹属性);

        // 刀口3
        myPoint.x = node3._x;
        myPoint.y = node3._y;
        装扮.localToGlobal(myPoint);
        gameworld.globalToLocal(myPoint);
        子弹属性.shootX = myPoint.x;
        子弹属性.shootY = myPoint.y;
        子弹属性.区域定位area = node3;
        shootFunc(子弹属性);
    }

    /**
     * 4刀口矩阵路径（20%的武器）
     */
    private static function shoot4(装扮:MovieClip, gameworld:MovieClip, 子弹属性:Object, shootFunc:Function):Void {
        var node1:MovieClip = 装扮.刀口位置1;
        var node2:MovieClip = 装扮.刀口位置2;
        var node3:MovieClip = 装扮.刀口位置3;
        var node4:MovieClip = 装扮.刀口位置4;

        // 矩阵预计算
        var p:Object = trans_p0; p.x = 0; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var Tx:Number = p.x, Ty:Number = p.y;

        p = trans_px; p.x = 1; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var a:Number = p.x - Tx, b:Number = p.y - Ty;

        p = trans_py; p.x = 0; p.y = 1;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var c:Number = p.x - Tx, d:Number = p.y - Ty;

        var x:Number, y:Number;

        // 刀口1
        x = node1._x; y = node1._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node1;
        shootFunc(子弹属性);

        // 刀口2
        x = node2._x; y = node2._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node2;
        shootFunc(子弹属性);

        // 刀口3
        x = node3._x; y = node3._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node3;
        shootFunc(子弹属性);

        // 刀口4
        x = node4._x; y = node4._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node4;
        shootFunc(子弹属性);
    }

    /**
     * 5+刀口矩阵路径（5%的武器）
     */
    private static function shoot5Plus(装扮:MovieClip, gameworld:MovieClip, 子弹属性:Object, shootFunc:Function, bladeCount:Number):Void {
        var node1:MovieClip = 装扮.刀口位置1;
        var node2:MovieClip = 装扮.刀口位置2;
        var node3:MovieClip = 装扮.刀口位置3;
        var node4:MovieClip = 装扮.刀口位置4;
        var node5:MovieClip = 装扮.刀口位置5;

        // 矩阵预计算
        var p:Object = trans_p0; p.x = 0; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var Tx:Number = p.x, Ty:Number = p.y;

        p = trans_px; p.x = 1; p.y = 0;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var a:Number = p.x - Tx, b:Number = p.y - Ty;

        p = trans_py; p.x = 0; p.y = 1;
        装扮.localToGlobal(p);
        gameworld.globalToLocal(p);
        var c:Number = p.x - Tx, d:Number = p.y - Ty;

        var x:Number, y:Number;

        // 刀口1
        x = node1._x; y = node1._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node1;
        shootFunc(子弹属性);

        // 刀口2
        x = node2._x; y = node2._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node2;
        shootFunc(子弹属性);

        // 刀口3
        x = node3._x; y = node3._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node3;
        shootFunc(子弹属性);

        // 刀口4
        x = node4._x; y = node4._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node4;
        shootFunc(子弹属性);

        // 刀口5
        x = node5._x; y = node5._y;
        子弹属性.shootX = x * a + y * c + Tx;
        子弹属性.shootY = x * b + y * d + Ty;
        子弹属性.区域定位area = node5;
        shootFunc(子弹属性);

        // 刀口6（如有）
        if (bladeCount >= 6) {
            var node6:MovieClip = 装扮.刀口位置6;
            x = node6._x; y = node6._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node6;
            shootFunc(子弹属性);
        }
    }

    /**
     * 回退路径：无预设值或异常情况
     * 使用运行时检测（兼容未标记bladeCount的武器）
     */
    private static function shootFallback(装扮:MovieClip, gameworld:MovieClip, 子弹属性:Object, shootFunc:Function):Void {
        var node1:MovieClip = 装扮.刀口位置1;
        var node2:MovieClip = 装扮.刀口位置2;
        var node3:MovieClip = 装扮.刀口位置3;
        var node4:MovieClip = 装扮.刀口位置4;

        var x:Number, y:Number;

        if (!node4 || node4._x == undefined) {
            // 3刀口以下快速路径
            var myPoint:Object = pointCache;

            x = node1._x;
            if (x != undefined) {
                myPoint.x = x;
                myPoint.y = node1._y;
                装扮.localToGlobal(myPoint);
                gameworld.globalToLocal(myPoint);
                子弹属性.shootX = myPoint.x;
                子弹属性.shootY = myPoint.y;
                子弹属性.区域定位area = node1;
                shootFunc(子弹属性);
            }

            x = node2._x;
            if (x != undefined) {
                myPoint.x = x;
                myPoint.y = node2._y;
                装扮.localToGlobal(myPoint);
                gameworld.globalToLocal(myPoint);
                子弹属性.shootX = myPoint.x;
                子弹属性.shootY = myPoint.y;
                子弹属性.区域定位area = node2;
                shootFunc(子弹属性);
            }

            x = node3._x;
            if (x != undefined) {
                myPoint.x = x;
                myPoint.y = node3._y;
                装扮.localToGlobal(myPoint);
                gameworld.globalToLocal(myPoint);
                子弹属性.shootX = myPoint.x;
                子弹属性.shootY = myPoint.y;
                子弹属性.区域定位area = node3;
                shootFunc(子弹属性);
            }
        } else {
            // 4+刀口矩阵路径
            var p:Object = trans_p0; p.x = 0; p.y = 0;
            装扮.localToGlobal(p);
            gameworld.globalToLocal(p);
            var Tx:Number = p.x, Ty:Number = p.y;

            p = trans_px; p.x = 1; p.y = 0;
            装扮.localToGlobal(p);
            gameworld.globalToLocal(p);
            var a:Number = p.x - Tx, b:Number = p.y - Ty;

            p = trans_py; p.x = 0; p.y = 1;
            装扮.localToGlobal(p);
            gameworld.globalToLocal(p);
            var c:Number = p.x - Tx, d:Number = p.y - Ty;

            // 刀口1-3
            x = node1._x;
            if (x != undefined) {
                y = node1._y;
                子弹属性.shootX = x * a + y * c + Tx;
                子弹属性.shootY = x * b + y * d + Ty;
                子弹属性.区域定位area = node1;
                shootFunc(子弹属性);
            }

            x = node2._x;
            if (x != undefined) {
                y = node2._y;
                子弹属性.shootX = x * a + y * c + Tx;
                子弹属性.shootY = x * b + y * d + Ty;
                子弹属性.区域定位area = node2;
                shootFunc(子弹属性);
            }

            x = node3._x;
            if (x != undefined) {
                y = node3._y;
                子弹属性.shootX = x * a + y * c + Tx;
                子弹属性.shootY = x * b + y * d + Ty;
                子弹属性.区域定位area = node3;
                shootFunc(子弹属性);
            }

            // 刀口4
            x = node4._x; y = node4._y;
            子弹属性.shootX = x * a + y * c + Tx;
            子弹属性.shootY = x * b + y * d + Ty;
            子弹属性.区域定位area = node4;
            shootFunc(子弹属性);

            // 刀口5（运行时检测）
            var node5:MovieClip = 装扮.刀口位置5;
            if (node5 && (x = node5._x) != undefined) {
                y = node5._y;
                子弹属性.shootX = x * a + y * c + Tx;
                子弹属性.shootY = x * b + y * d + Ty;
                子弹属性.区域定位area = node5;
                shootFunc(子弹属性);
            }
        }
    }
}
