import org.flashNight.aven.Coordinator.*;

/**
 * @class DepthManager
 * @description 基于 Twip Trick 模运算的战斗单位深度管理器
 *
 *   核心公式: depth = bandLow + (int((Y - yMin) * S) * N) + entityID
 *   其中 entityID ∈ [0, N-1] 唯一，保证 depth % N == entityID → 零内部碰撞
 *
 *   契约:
 *   - 管理 gameworld 直接子级中所有参与 Y 轴排序的对象（单位、元件、拾取物等）
 *   - 同 Y 实体按 entityID（注册顺序）排序，非时间戳——保证帧间稳定无闪烁
 *   - 调用方必须保证传入 MC 是绑定容器的直接子级（热路径不做 _parent === _container 检查）
 *   - 容量有限：超过 maxEntities 时 updateDepth 返回 false
 *
 * @package org.flashNight.gesh.depth
 */
class org.flashNight.gesh.depth.DepthManager {

    /** 全局单例，由 SceneManager.initGameWorld 创建/销毁 */
    public static var instance:DepthManager;

    /** 原生 swapDepths 引用，绕过实例级劫持 */
    private static var _nativeSD:Function = MovieClip.prototype.swapDepths;

    // ── 平行数组（SoA） ──
    private var _mcs:Array;       // [idx] → MovieClip
    private var _names:Array;     // [idx] → mc._name 注册快照（MC 销毁后仍可清理 _idxMap）
    private var _ids:Array;       // [idx] → entityID (0..N-1)
    private var _baseD:Array;     // [idx] → _bandLow + entityID（预折叠常量，减少热路径成员读取）
    private var _curD:Array;      // [idx] → 最近一次已应用的深度
    private var _count:Number;    // 当前注册实体数

    // ── 查找 ──
    private var _idxMap:Object;   // mc._name → idx（proto-null 字典）

    // ── ID 管理 ──
    private var _freeIDs:Array;   // 回收的 entityID 栈（手动索引，避免 push/pop 的 1340ns 方法调用税）
    private var _freeCount:Number;// _freeIDs 栈顶指针
    private var _nextID:Number;   // 下一个未用 ID

    // ── Twip Trick 参数 ──
    private var _container:MovieClip;
    private var _bandLow:Number;
    private var _bandHigh:Number;
    private var _S:Number;        // 量化比例
    private var _N:Number;        // 最大实体数
    private var _yMin:Number;
    private var _yMax:Number;
    private var _calibrated:Boolean;

    // ── 生命周期 ──
    private var _unloadID:String; // addUnloadCallback 返回的监听器 ID，dispose 时解绑

    /**
     * 构造函数
     * @param container  父容器（所有受管 MC 必须是其直接子级）
     * @param bandLow    深度带下界（默认 0）
     * @param bandHigh   深度带上界（默认 1048575，Flash 最大深度）
     * @param maxEntities 容量上限（默认 256）
     */
    public function DepthManager(container:MovieClip, bandLow:Number, bandHigh:Number, maxEntities:Number) {
        if (bandLow == undefined) bandLow = 0;
        if (bandHigh == undefined) bandHigh = 1048575;
        if (maxEntities == undefined) maxEntities = 256;

        _container = container;
        _bandLow = bandLow;
        _bandHigh = bandHigh;
        _N = maxEntities;
        _count = 0;
        _nextID = 0;
        _freeCount = 0;
        _calibrated = false;

        _mcs = new Array(maxEntities);
        _names = new Array(maxEntities);
        _ids = new Array(maxEntities);
        _baseD = new Array(maxEntities);
        _curD = new Array(maxEntities);
        _freeIDs = new Array(maxEntities);

        var map:Object = {};
        map.__proto__ = null;
        _idxMap = map;

        // 容器卸载时自动清理（保存 handlerID 供 dispose 解绑）
        var self:DepthManager = this;
        _unloadID = EventCoordinator.addUnloadCallback(container, function():Void {
            self.dispose();
        });
    }

    /**
     * 标定 Y 范围（场景切换时调用）
     * calibrate 可能自动扩展 bandHigh 以容纳 yRange × N
     * @return 是否标定成功（false 表示参数不可满足，调用方需减少 maxEntities）
     */
    public function calibrate(yMin:Number, yMax:Number):Boolean {
        var yRange:Number = yMax - yMin;
        if (yRange < 1) yRange = 1;
        var bandSpan:Number = _bandHigh - _bandLow;
        var s:Number = ((bandSpan - _N + 1) / (yRange * _N)) | 0;
        if (s < 1) {
            // 尝试自动扩展 bandHigh
            var needed:Number = _bandLow + yRange * _N + _N - 1;
            if (needed <= 1048575) {
                _bandHigh = needed;
                s = 1;
            } else {
                _calibrated = false;
                return false;
            }
        }
        _S = s;
        _yMin = yMin;
        _yMax = yMax;
        _calibrated = true;
        // 失效当前已知深度；未 re-feed 的实体对外表现为 undefined，
        // 调用方重新 updateDepth 后会立即应用新深度。
        var i:Number = _count;
        while (i--) {
            _curD[i] = -1;
        }
        return true;
    }

    /**
     * 更新实体的目标 Y 坐标（自动注册新实体）
     *
     * 契约: mc._parent === _container（调用方保证，热路径不检查）
     * 错误容器的 MC 传入属于调用方违约，不做生产防御。
     *
     * @param mc      要排序的影片剪辑
     * @param targetY 目标 Y 坐标
     * @return 是否成功
     */
    public function updateDepth(mc:MovieClip, targetY:Number):Boolean {
        if (!mc || !_calibrated) return false;
        if ((targetY - targetY) != 0) return false; // NaN guard (H07)

        // 热路径优先走 MC 自带槽位缓存，避免每帧 _name → _idxMap 查找。
        // 契约：同一 MC 同时只被一个 DepthManager 管理；同名重建仍走下方 name-map 回退路径。
        var idx:Number = mc["__dmIdx"];
        if (idx == undefined || _mcs[idx] !== mc) {
            // 活着的 MC 的 _name 必为非空 String（AS2 创建时强制指定）；
            // 仅 removeMovieClip 后的 stale 引用返回 undefined（引用本身仍 truthy，通过 !mc）。
            // 所以此检查等价于 stale MC 防护，同时取得 idxMap 查找键。
            var name:String = mc._name;
            if (name == undefined) return false;
            idx = _idxMap[name];

            // 同名异引用检测：覆盖"销毁+同名重建"的池模式（idxMap 命中但 _mcs[idx] 是旧引用）。
            if (idx != undefined && _mcs[idx] !== mc) {
                _evict(idx);
                idx = undefined;
            }

            if (idx == undefined) {
                // 自动注册；容量已满时先做一次非热路径死对象回收兜底
                if (_count >= _N) {
                    _sweepDead();
                    if (_count >= _N) return false;
                }
                _mcs[idx = _count++] = mc;
                _names[idx] = name;
                _idxMap[name] = idx;
                var id:Number = (_freeCount > 0) ? _freeIDs[--_freeCount] : _nextID++;
                _ids[idx] = id;
                _baseD[idx] = _bandLow + id;
                _curD[idx] = -1; // 强制首次应用
            }
            mc["__dmIdx"] = idx;
        }

        // clamp Y 到标定范围（防御性，正常流中 enforceScreenBounds 已保证 Y ∈ [yMin, yMax]）
        // 放在 updateDepth 而非 flush：updateDepth 是入口守卫，flush 是纯热路径不做校验
        var lo:Number = _yMin;
        var hi:Number = _yMax;
        var y:Number = (targetY < lo) ? lo : ((targetY > hi) ? hi : targetY);
        var d:Number = (((y - lo) * _S) | 0) * _N + _baseD[idx];
        if (d !== _curD[idx]) {
            _nativeSD.call(mc, d);
            _curD[idx] = d;
        }
        return true;
    }

    /**
     * 批量更新实体深度。
     * 设计目的：把 50 次 updateDepth 方法调用税压缩为 1 次，供稳态主循环使用。
     *
     * @param mcs    MovieClip 数组，使用前 count 个元素
     * @param ys     Y 数组，从 yOffset 开始连续读取 count 个值
     * @param yOffset ys 起始偏移
     * @param count  处理实体数
     * @return 成功处理的实体数
     */
    public function updateDepthBatch(mcs:Array, ys:Array, yOffset:Number, count:Number):Number {
        if (!_calibrated) return 0;

        var managed:Array = _mcs;
        var names:Array = _names;
        var ids:Array = _ids;
        var baseD:Array = _baseD;
        var curD:Array = _curD;
        var idxMap:Object = _idxMap;
        var lo:Number = _yMin;
        var hi:Number = _yMax;
        var s:Number = _S;
        var n:Number = _N;
        var i:Number = 0;
        var yi:Number = yOffset;
        var end:Number = yOffset + count;
        var updated:Number = 0;
        var mc:MovieClip, idx:Number, name:String, y:Number, d:Number, id:Number;

        while (yi < end) {
            mc = mcs[i++];
            y = ys[yi++];
            if (!mc) continue;
            if ((y - y) != 0) continue; // NaN guard

            idx = mc["__dmIdx"];
            if (idx == undefined) {
                name = mc._name;
                if (name == undefined) continue;
                idx = idxMap[name];

                if (idx != undefined && managed[idx] !== mc) {
                    _evict(idx);
                    idx = undefined;
                }

                if (idx == undefined) {
                    if (_count >= _N) {
                        _sweepDead();
                        if (_count >= _N) continue;
                    }
                    managed[idx = _count++] = mc;
                    names[idx] = name;
                    idxMap[name] = idx;
                    id = (_freeCount > 0) ? _freeIDs[--_freeCount] : _nextID++;
                    ids[idx] = id;
                    baseD[idx] = _bandLow + id;
                    curD[idx] = -1;
                }
                mc["__dmIdx"] = idx;
            }

            y = (y < lo) ? lo : ((y > hi) ? hi : y);
            d = (((y - lo) * s) | 0) * n + baseD[idx];
            if (d !== curD[idx]) {
                _nativeSD.call(mc, d);
                curD[idx] = d;
            }
            updated++;
        }
        return updated;
    }

    /**
     * 兼容保留：steady-state 热路径已在 updateDepth 中立即应用深度。
     * flush 不再承担每帧惰性剔除，避免为所有实体支付 native 属性检测税。
     */
    public function flush():Void {
    }

    /**
     * 显式回收被外部 removeMovieClip 销毁的实体。
     * 非热路径调用：场景维护、容量压力兜底、或对象池批量回收后统一调用。
     */
    public function sweepDead():Void {
        _sweepDead();
    }

    /**
     * 注销实体
     * @param mc 要移除的影片剪辑
     * @return 是否成功移除
     */
    public function removeMovieClip(mc:MovieClip):Boolean {
        if (!mc) return false;
        var idx:Number = _idxMap[mc._name];
        if (idx == undefined) return false;
        // 引用比对：同名异引用（外部 clip / stale 引用）不得误删受管对象
        if (_mcs[idx] !== mc) return false;
        _evict(idx);
        return true;
    }

    /**
     * 安装 swapDepths 劫持：将 mc.swapDepths 重定向到 updateDepth，
     * 使帧脚本中的原生 swapDepths 调用走 DepthManager 统一管线。
     * 非热路径，仅在单位初始化时调用一次。
     */
    public function installHijack(mc:MovieClip):Void {
        mc.swapDepths = function(y:Number):Void {
            DepthManager.instance.updateDepth(this, y);
        };
    }

    /**
     * 移除 swapDepths 劫持，恢复原型链上的原生方法。
     * 非热路径，仅在单位反初始化时调用。
     */
    public function removeHijack(mc:MovieClip):Void {
        delete mc.swapDepths;
    }

    /**
     * 查询管理器最近一次成功写入显示列表的深度值
     *
     * 返回值语义：
     *   - 有效深度值：最近一次 updateDepth 成功写入的深度
     *   - undefined：未注册，或已注册但 calibrate 后尚未 re-feed
     *     （此时 MC 仍停在显示列表旧深度，但管理器不保证该值）
     */
    public function getDepth(mc:MovieClip):Number {
        if (!mc) return undefined;
        var idx:Number = _idxMap[mc._name];
        if (idx == undefined) return undefined;
        // 引用比对：同名异引用返回 undefined 而非被管对象的深度
        if (_mcs[idx] !== mc) return undefined;
        var d:Number = _curD[idx];
        // -1 是内部哨兵（未 flush / calibrate 后待定），对外暴露为 undefined
        if (d == -1) return undefined;
        return d;
    }

    /** 当前注册实体数 */
    public function size():Number {
        return _count;
    }

    /** 清空所有管理数据（保留标定参数） */
    public function clear():Void {
        var i:Number = _count;
        while (i--) {
            if (_mcs[i] != null) _mcs[i]["__dmIdx"] = undefined;
            _mcs[i] = null;
            _names[i] = null;
        }
        _count = 0;
        _nextID = 0;
        _freeCount = 0;
        // 重建 proto-null 字典（比逐个置 undefined 更干净，clear 非热路径）
        var map:Object = {};
        map.__proto__ = null;
        _idxMap = map;
    }

    /** 释放所有资源（容器卸载时自动调用，手动调用时解绑 onUnload 防止泄漏） */
    public function dispose():Void {
        // 解绑 onUnload 回调，防止 dispose 后旧闭包继续持有已废弃实例
        if (_unloadID != undefined && _container != undefined) {
            EventCoordinator.removeEventListener(_container, "onUnload", _unloadID);
            _unloadID = undefined;
        }
        clear();
        _container = null;
        _mcs = null;
        _names = null;
        _ids = null;
        _baseD = null;
        _curD = null;
        _freeIDs = null;
        _idxMap = null;
        _calibrated = false;
    }

    // ── 私有方法 ──

    /**
     * 惰性剔除：swap-and-pop 移除指定槽位
     * 使用 _names[idx]（注册快照）清理 _idxMap，因为 MC 销毁后 _mcs[idx]._name 为 undefined
     */
    private function _evict(idx:Number):Void {
        // 用 delete 而非 tombstone（= undefined）：
        // tombstone 会让 _idxMap 键空间在高 churn 场景下无限增长，
        // 降低后续 for-in（如果有）和哈希查找性能。
        // delete 166ns 在 evict 路径上可接受（evict 只在 MC 销毁/移除时触发，非每帧热路径）。
        if (_mcs[idx] != null) _mcs[idx]["__dmIdx"] = undefined;
        delete _idxMap[_names[idx]];
        // 手动栈写入替代 push（1340ns → 35ns）
        _freeIDs[_freeCount++] = _ids[idx];

        var last:Number = _count - 1;
        _count = last;
        if (idx !== last) {
            _mcs[idx] = _mcs[last];
            _names[idx] = _names[last];
            _ids[idx] = _ids[last];
            _baseD[idx] = _baseD[last];
            _curD[idx] = _curD[last];
            _mcs[idx]["__dmIdx"] = idx;
            _idxMap[_names[idx]] = idx;
        }
        _mcs[last] = null;
        _names[last] = null;
    }

    /**
     * 正序遍历 + swap-and-pop：evict 后不递增 i，重检搬入元素。
     * 只做死对象回收，不承担每帧排序。
     */
    private function _sweepDead():Void {
        var mcs:Array = _mcs;
        var i:Number = 0;
        while (i < _count) {
            if (mcs[i]._name == undefined) {
                _evict(i);
                continue;
            }
            i++;
        }
    }
}
