import org.flashNight.aven.Coordinator.*;

/**
 * @class DepthManager
 * @description 基于 Twip Trick 模运算的战斗单位深度管理器
 *
 *   核心公式: depth = bandLow + (int((Y - yMin) * S) * N) + entityID
 *   其中 entityID ∈ [0, N-1] 唯一，保证 depth % N == entityID → 零内部碰撞
 *
 *   契约:
 *   - 专用于战斗场景中单位的 Y 轴深度排序，不管理任意深度值
 *   - 同 Y 实体按 entityID（注册顺序）排序，非时间戳——保证帧间稳定无闪烁
 *   - 调用方必须保证传入 MC 是绑定容器的直接子级（热路径不做 _parent === _container 检查）
 *   - 容量有限：超过 maxEntities 时 updateDepth 返回 false
 *
 * @package org.flashNight.gesh.depth
 */
class org.flashNight.gesh.depth.DepthManager {

    // ── 平行数组（SoA） ──
    private var _mcs:Array;       // [idx] → MovieClip
    private var _names:Array;     // [idx] → mc._name 注册快照（MC 销毁后仍可清理 _idxMap）
    private var _ids:Array;       // [idx] → entityID (0..N-1)
    private var _curD:Array;      // [idx] → 上次 flush 已应用的深度
    private var _targetD:Array;   // [idx] → 本帧计算的目标深度
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
     * @param bandLow    深度带下界（默认 10000，高于时间轴原生层级）
     * @param bandHigh   深度带上界（默认 1048575，Flash 最大深度）
     * @param maxEntities 容量上限（默认 64）
     */
    public function DepthManager(container:MovieClip, bandLow:Number, bandHigh:Number, maxEntities:Number) {
        if (bandLow == undefined) bandLow = 10000;
        if (bandHigh == undefined) bandHigh = 1048575;
        if (maxEntities == undefined) maxEntities = 64;

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
        _curD = new Array(maxEntities);
        _targetD = new Array(maxEntities);
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
        // 强制下次 flush 全量更新；同时失效 _targetD 防止旧场景深度值被误用
        // 未被 re-feed 的实体在 flush 时 _targetD == _curD == -1，跳过 swapDepths
        var i:Number = _count;
        while (i--) {
            _curD[i] = -1;
            _targetD[i] = -1;
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
        if (mc._parent == undefined) return false;  // stale MC 防护
        if ((targetY - targetY) != 0) return false; // NaN guard (H07)

        var name:String = mc._name;
        var idx:Number = _idxMap[name];

        // 同名 MC 复用检测：对象池回收旧 MC 后以同名新建，idxMap 命中但 _mcs[idx] 是旧引用
        // 成本：一次数组读（35ns）+ 一次引用比较（~0ns），可忽略
        if (idx != undefined && _mcs[idx] !== mc) {
            _evict(idx);      // 清理旧槽位
            idx = undefined;  // 落入下方注册分支
        }

        if (idx == undefined) {
            // 自动注册
            if (_count >= _N) return false; // 容量满
            idx = _count;
            _count++;
            _mcs[idx] = mc;
            _names[idx] = name;
            _idxMap[name] = idx;
            if (_freeCount > 0) {
                _ids[idx] = _freeIDs[--_freeCount];
            } else {
                _ids[idx] = _nextID++;
            }
            _curD[idx] = -1; // 强制首次 flush
        }

        // clamp Y 到标定范围（保护不变量 2：深度始终在带内）
        var y:Number = targetY;
        if (y < _yMin) {
            y = _yMin;
        } else if (y > _yMax) {
            y = _yMax;
        }

        // Twip Trick 核心公式
        _targetD[idx] = _bandLow + (((y - _yMin) * _S) | 0) * _N + _ids[idx];
        return true;
    }

    /**
     * 批量执行 swapDepths（每帧调用一次）
     * 包含惰性剔除：检测已销毁的 MC 并自动清理
     */
    public function flush():Void {
        var mcs:Array = _mcs;
        var curD:Array = _curD;
        var tgtD:Array = _targetD;
        var i:Number = 0;
        // 正序遍历 + 手动递增：evict 后不 i++，重检 swap-and-pop 搬入的元素
        while (i < _count) {
            if (mcs[i]._name == undefined) {
                _evict(i);
                // 不递增 i：_evict 将末尾搬到 i，需要重检
                // 若 evict 的是末尾元素，_count-- 后 i >= _count，循环自然结束
                continue;
            }
            var d:Number = tgtD[i];
            if (d !== curD[i]) {
                mcs[i].swapDepths(d);
                curD[i] = d;
            }
            i++;
        }
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
        _evict(idx);
        return true;
    }

    /**
     * 查询实体当前生效的深度值
     * @return flush 后的实际深度，未注册返回 undefined
     */
    public function getDepth(mc:MovieClip):Number {
        if (!mc) return undefined;
        var idx:Number = _idxMap[mc._name];
        if (idx == undefined) return undefined;
        return _curD[idx];
    }

    /** 当前注册实体数 */
    public function size():Number {
        return _count;
    }

    /** 清空所有管理数据（保留标定参数） */
    public function clear():Void {
        var i:Number = _count;
        while (i--) {
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
        _curD = null;
        _targetD = null;
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
        // S08: 避免 delete 修改哈希结构，用 undefined 置空（语义等价：_idxMap[name] == undefined）
        _idxMap[_names[idx]] = undefined;
        // 手动栈写入替代 push（1340ns → 35ns）
        _freeIDs[_freeCount++] = _ids[idx];

        var last:Number = _count - 1;
        _count = last;
        if (idx !== last) {
            _mcs[idx] = _mcs[last];
            _names[idx] = _names[last];
            _ids[idx] = _ids[last];
            _curD[idx] = _curD[last];
            _targetD[idx] = _targetD[last];
            _idxMap[_names[idx]] = idx;
        }
        _mcs[last] = null;
        _names[last] = null;
    }
}
