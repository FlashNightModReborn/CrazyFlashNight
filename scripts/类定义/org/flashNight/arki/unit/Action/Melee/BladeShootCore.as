/**
 * BladeShootCore - 刀口位置子弹生成核心
 *
 * 职责：
 * - 根据刀口数量生成近战子弹
 * - 按刀口数内联展开，避免函数调用开销
 * - 提供函数工厂模式，保持 this 绑定
 *
 * 设计原则：
 * - 纯静态类，所有方法和缓存都是静态的
 * - getShootFunction() 返回绑定到单位 this 的函数
 * - 编译期类型检查，IDE 友好
 * - 类内部英文命名便于输入，_root 交互和属性名保持中文
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

    /** 坐标变换缓存点 */
    private static var pointCache:Object = {x: 0, y: 0};

    /** 矩阵变换用临时点 */
    private static var transP0:Object = {x: 0, y: 0};
    private static var transPx:Object = {x: 0, y: 0};
    private static var transPy:Object = {x: 0, y: 0};

    /** 调试开关 */
    public static var debug:Boolean = false;

    /** 缓存的射击函数引用 */
    private static var cachedShootFunc:Function = null;

    // ========== 函数工厂 ==========

    /**
     * 获取刀口位置生成子弹函数
     *
     * 返回一个函数，调用时 this 指向调用者（单位对象）
     * 内部委托给 BladeShootCore.shoot 执行实际逻辑
     *
     * @return Function 可绑定到单位的射击函数
     */
    public static function getShootFunction():Function {
        if (cachedShootFunc == null) {
            cachedShootFunc = function(bulletParams:Object):Void {
                BladeShootCore.shoot(this, bulletParams);
            };
        }
        return cachedShootFunc;
    }

    // ========== 核心方法 ==========

    /**
     * 刀口位置生成子弹（主入口）
     *
     * @param unit:MovieClip 单位对象
     * @param params:Object 子弹参数覆盖
     */
    public static function shoot(unit:MovieClip, params:Object):Void {
        var shootFunc:Function = _root.子弹区域shoot传递;
        var dressup:MovieClip = unit.man.刀.刀.装扮;
        var gameworld:MovieClip = _root.gameworld;

        // 构建基础子弹属性
        var bulletAttr:Object = {
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
            bulletAttr[key] = params[key];
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

        // ==========================================
        // 按刀口数内联展开，避免函数调用开销
        // ==========================================

        var x:Number, y:Number;
        var node1:MovieClip, node2:MovieClip, node3:MovieClip, node4:MovieClip, node5:MovieClip;
        var pt:Object;
        var p:Object;
        var Tx:Number, Ty:Number, a:Number, b:Number, c:Number, d:Number;

        if (bladeCount == 3) {
            // ==========================================
            // 3刀口快速路径（最常见：74%）
            // 逐点变换，无需矩阵预计算
            // ==========================================
            pt = pointCache;
            node1 = dressup.刀口位置1;
            node2 = dressup.刀口位置2;
            node3 = dressup.刀口位置3;

            // 刀口1
            pt.x = node1._x;
            pt.y = node1._y;
            dressup.localToGlobal(pt);
            gameworld.globalToLocal(pt);
            bulletAttr.shootX = pt.x;
            bulletAttr.shootY = pt.y;
            bulletAttr.区域定位area = node1;
            shootFunc(bulletAttr);

            // 刀口2
            pt.x = node2._x;
            pt.y = node2._y;
            dressup.localToGlobal(pt);
            gameworld.globalToLocal(pt);
            bulletAttr.shootX = pt.x;
            bulletAttr.shootY = pt.y;
            bulletAttr.区域定位area = node2;
            shootFunc(bulletAttr);

            // 刀口3
            pt.x = node3._x;
            pt.y = node3._y;
            dressup.localToGlobal(pt);
            gameworld.globalToLocal(pt);
            bulletAttr.shootX = pt.x;
            bulletAttr.shootY = pt.y;
            bulletAttr.区域定位area = node3;
            shootFunc(bulletAttr);

        } else if (bladeCount == 4) {
            // ==========================================
            // 4刀口矩阵路径（20%）
            // ==========================================
            node1 = dressup.刀口位置1;
            node2 = dressup.刀口位置2;
            node3 = dressup.刀口位置3;
            node4 = dressup.刀口位置4;

            // 矩阵预计算
            p = transP0; p.x = 0; p.y = 0;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            Tx = p.x; Ty = p.y;

            p = transPx; p.x = 1; p.y = 0;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            a = p.x - Tx; b = p.y - Ty;

            p = transPy; p.x = 0; p.y = 1;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            c = p.x - Tx; d = p.y - Ty;

            // 刀口1
            x = node1._x; y = node1._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node1;
            shootFunc(bulletAttr);

            // 刀口2
            x = node2._x; y = node2._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node2;
            shootFunc(bulletAttr);

            // 刀口3
            x = node3._x; y = node3._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node3;
            shootFunc(bulletAttr);

            // 刀口4
            x = node4._x; y = node4._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node4;
            shootFunc(bulletAttr);

        } else if (bladeCount >= 5) {
            // ==========================================
            // 5+刀口矩阵路径（5%）
            // ==========================================
            node1 = dressup.刀口位置1;
            node2 = dressup.刀口位置2;
            node3 = dressup.刀口位置3;
            node4 = dressup.刀口位置4;
            node5 = dressup.刀口位置5;

            // 矩阵预计算
            p = transP0; p.x = 0; p.y = 0;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            Tx = p.x; Ty = p.y;

            p = transPx; p.x = 1; p.y = 0;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            a = p.x - Tx; b = p.y - Ty;

            p = transPy; p.x = 0; p.y = 1;
            dressup.localToGlobal(p);
            gameworld.globalToLocal(p);
            c = p.x - Tx; d = p.y - Ty;

            // 刀口1
            x = node1._x; y = node1._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node1;
            shootFunc(bulletAttr);

            // 刀口2
            x = node2._x; y = node2._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node2;
            shootFunc(bulletAttr);

            // 刀口3
            x = node3._x; y = node3._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node3;
            shootFunc(bulletAttr);

            // 刀口4
            x = node4._x; y = node4._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node4;
            shootFunc(bulletAttr);

            // 刀口5
            x = node5._x; y = node5._y;
            bulletAttr.shootX = x * a + y * c + Tx;
            bulletAttr.shootY = x * b + y * d + Ty;
            bulletAttr.区域定位area = node5;
            shootFunc(bulletAttr);

            // 刀口6（若存在）
            if (bladeCount >= 6) {
                var node6:MovieClip = dressup.刀口位置6;
                x = node6._x; y = node6._y;
                bulletAttr.shootX = x * a + y * c + Tx;
                bulletAttr.shootY = x * b + y * d + Ty;
                bulletAttr.区域定位area = node6;
                shootFunc(bulletAttr);
            }

        } else if (bladeCount == 2) {
            // ==========================================
            // 2刀口快速路径（罕见）
            // ==========================================
            pt = pointCache;
            node1 = dressup.刀口位置1;
            node2 = dressup.刀口位置2;

            // 刀口1
            pt.x = node1._x;
            pt.y = node1._y;
            dressup.localToGlobal(pt);
            gameworld.globalToLocal(pt);
            bulletAttr.shootX = pt.x;
            bulletAttr.shootY = pt.y;
            bulletAttr.区域定位area = node1;
            shootFunc(bulletAttr);

            // 刀口2
            pt.x = node2._x;
            pt.y = node2._y;
            dressup.localToGlobal(pt);
            gameworld.globalToLocal(pt);
            bulletAttr.shootX = pt.x;
            bulletAttr.shootY = pt.y;
            bulletAttr.区域定位area = node2;
            shootFunc(bulletAttr);

        } else {
            // ==========================================
            // 回退路径：无预设或异常情况
            // 运行时检测（兼容未标记的武器）
            // ==========================================
            node1 = dressup.刀口位置1;
            node2 = dressup.刀口位置2;
            node3 = dressup.刀口位置3;
            node4 = dressup.刀口位置4;

            if (!node4 || node4._x == undefined) {
                // ≤3刀口快速路径
                pt = pointCache;

                x = node1._x;
                if (x != undefined) {
                    pt.x = x;
                    pt.y = node1._y;
                    dressup.localToGlobal(pt);
                    gameworld.globalToLocal(pt);
                    bulletAttr.shootX = pt.x;
                    bulletAttr.shootY = pt.y;
                    bulletAttr.区域定位area = node1;
                    shootFunc(bulletAttr);
                }

                x = node2._x;
                if (x != undefined) {
                    pt.x = x;
                    pt.y = node2._y;
                    dressup.localToGlobal(pt);
                    gameworld.globalToLocal(pt);
                    bulletAttr.shootX = pt.x;
                    bulletAttr.shootY = pt.y;
                    bulletAttr.区域定位area = node2;
                    shootFunc(bulletAttr);
                }

                x = node3._x;
                if (x != undefined) {
                    pt.x = x;
                    pt.y = node3._y;
                    dressup.localToGlobal(pt);
                    gameworld.globalToLocal(pt);
                    bulletAttr.shootX = pt.x;
                    bulletAttr.shootY = pt.y;
                    bulletAttr.区域定位area = node3;
                    shootFunc(bulletAttr);
                }
            } else {
                // 4+刀口矩阵路径
                p = transP0; p.x = 0; p.y = 0;
                dressup.localToGlobal(p);
                gameworld.globalToLocal(p);
                Tx = p.x; Ty = p.y;

                p = transPx; p.x = 1; p.y = 0;
                dressup.localToGlobal(p);
                gameworld.globalToLocal(p);
                a = p.x - Tx; b = p.y - Ty;

                p = transPy; p.x = 0; p.y = 1;
                dressup.localToGlobal(p);
                gameworld.globalToLocal(p);
                c = p.x - Tx; d = p.y - Ty;

                // 刀口1-3
                x = node1._x;
                if (x != undefined) {
                    y = node1._y;
                    bulletAttr.shootX = x * a + y * c + Tx;
                    bulletAttr.shootY = x * b + y * d + Ty;
                    bulletAttr.区域定位area = node1;
                    shootFunc(bulletAttr);
                }

                x = node2._x;
                if (x != undefined) {
                    y = node2._y;
                    bulletAttr.shootX = x * a + y * c + Tx;
                    bulletAttr.shootY = x * b + y * d + Ty;
                    bulletAttr.区域定位area = node2;
                    shootFunc(bulletAttr);
                }

                x = node3._x;
                if (x != undefined) {
                    y = node3._y;
                    bulletAttr.shootX = x * a + y * c + Tx;
                    bulletAttr.shootY = x * b + y * d + Ty;
                    bulletAttr.区域定位area = node3;
                    shootFunc(bulletAttr);
                }

                // 刀口4
                x = node4._x; y = node4._y;
                bulletAttr.shootX = x * a + y * c + Tx;
                bulletAttr.shootY = x * b + y * d + Ty;
                bulletAttr.区域定位area = node4;
                shootFunc(bulletAttr);

                // 刀口5（运行时检测）
                node5 = dressup.刀口位置5;
                if (node5 && (x = node5._x) != undefined) {
                    y = node5._y;
                    bulletAttr.shootX = x * a + y * c + Tx;
                    bulletAttr.shootY = x * b + y * d + Ty;
                    bulletAttr.区域定位area = node5;
                    shootFunc(bulletAttr);
                }
            }
        }

        // 调试输出
        if (debug) {
            _root.服务器.发布服务器消息("[BladeShootCore] " + debugUnitName + " | 预设:" + debugBladeCount + " | 实际:" + bulletCount);
        }
    }
}
