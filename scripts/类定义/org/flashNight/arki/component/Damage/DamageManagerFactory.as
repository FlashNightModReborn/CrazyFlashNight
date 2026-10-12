import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.func.*;

/**
 * DamageManagerFactory 是用于创建和管理 DamageManager 实例的工厂类。
 * 主要功能包括：
 * - 动态构建 DamageManager，根据子弹属性选择合适的伤害处理器。
 * - 通过最多 8 位的掩码与直接数组缓存惰性创建。
 * - 支持实例化工厂和静态全局工厂，适配不同的使用场景。
 */
class org.flashNight.arki.component.Damage.DamageManagerFactory {

    // ========== 静态区域（全局工厂管理） ==========

    // 存储具名工厂的映射表（名称 -> 工厂实例）
    private static var _namedFactories:Object = {};

    // 默认的基础工厂，预置了常用的伤害处理器
    public static var Basic:DamageManagerFactory;

    // 实际命中即终结的冷路径工厂：只做分类，不装载会改资源/护盾的附加处理器。
    public static var ActualTerminal:DamageManagerFactory;

    /**
     * 创建一个默认的基础伤害工厂，内置常用处理器。
     * 该工厂包含以下处理器：
     * - CritDamageHandle：暴击处理器
     * - UniversalDamageHandle：通用处理器
     * - DodgeStateDamageHandle：躲闪状态处理器
     * - MultiShotDamageHandle：联弹处理器
     * - NanoToxicDamageHandle：毒素处理器
     * - LifeStealDamageHandle：吸血处理器
     * - CrumbleDamageHandle：击溃处理器
     * - ExecuteDamageHandle：斩杀处理器
     *
     * @return 创建好的 DamageManagerFactory 实例
     * @throws 如果处理器数量超过8个，将抛出异常
     */
    public static function createBasic():DamageManagerFactory {
        var handles:Array = [CritDamageHandle.getInstance(), // 暴击处理器
            UniversalDamageHandle.getInstance(), // 通用处理器
            DodgeStateDamageHandle.getInstance(), // 躲闪状态处理器
            MultiShotDamageHandle.getInstance(), // 联弹处理器
            NanoToxicDamageHandle.getInstance(), // 毒素处理器
            LifeStealDamageHandle.getInstance(), // 吸血处理器
            CrumbleDamageHandle.getInstance(), // 击溃处理器
            ExecuteDamageHandle.getInstance() // 斩杀处理器
            ];

        if (handles.length > 8) {
            throw "DamageManagerFactory 支持的处理器数量最多为 8 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, 64);
        registerExistingFactory("Basic", factory);
        return factory;
    }

    /** 创建“分类后终结”专用工厂；顺序必须与 Basic 的前四个分类处理器一致。 */
    public static function createActualTerminal():DamageManagerFactory {
        var handles:Array = [
            CritDamageHandle.getInstance(),
            UniversalDamageHandle.getInstance(),
            DodgeStateDamageHandle.getInstance(),
            MultiShotDamageHandle.getInstance(),
            ActualTerminalDamageHandle.getInstance()
        ];
        var factory:DamageManagerFactory = new DamageManagerFactory(handles, 16);
        registerExistingFactory("ActualTerminal", factory);
        return factory;
    }

    /**
     * 初始化默认的基础工厂。
     * 调用此方法后，可以通过 DamageManagerFactory.Basic 访问默认工厂。
     */
    public static function init():Void {
        Basic = createBasic();
        ActualTerminal = createActualTerminal();
    }

    /** 子弹创建期唯一 manager 选择点；实际命中强制终结只付一次冷路径分支。 */
    public static function resolveForBullet(bullet:Object):DamageManager {
        if (bullet != null && bullet.实际命中强制击杀 === true && ActualTerminal != null) {
            return ActualTerminal.getDamageManager(bullet);
        }
        return Basic.getDamageManager(bullet);
    }

    /**
     * 注册一个具名工厂到全局映射中。
     *
     * @param name          工厂名称（唯一标识）
     * @param handles       处理器数组
     * @param cacheCapacity 缓存容量
     * @throws 如果工厂名称已存在或处理器数量超过8个，则抛出异常
     */
    public static function registerFactory(name:String, handles:Array, cacheCapacity:Number):Void {
        if (_namedFactories[name] != undefined) {
            throw "工厂名称 '" + name + "' 已存在，无法重复注册。";
        }

        if (handles.length > 8) {
            throw "DamageManagerFactory 支持的处理器数量最多为 8 个。";
        }

        var factory:DamageManagerFactory = new DamageManagerFactory(handles, cacheCapacity);
        _namedFactories[name] = factory;
    }

    /**
     * 注册一个已构建好的 DamageManagerFactory 实例到全局映射中。
     *
     * @param name    工厂名称（唯一标识）
     * @param factory 已实例化的 DamageManagerFactory 对象
     * @throws 如果工厂名称已存在或 factory 不是 DamageManagerFactory 实例，则抛出异常
     */
    public static function registerExistingFactory(name:String, factory:DamageManagerFactory):Void {
        if (_namedFactories[name] != undefined) {
            throw "工厂名称 '" + name + "' 已存在，无法重复注册。";
        }

        if (factory == null || !(factory instanceof DamageManagerFactory)) {
            throw "提供的 factory 不是有效的 DamageManagerFactory 实例。";
        }

        _namedFactories[name] = factory;
    }

    /**
     * 获取已注册的具名工厂。
     *
     * @param name 工厂名称
     * @return 对应的 DamageManagerFactory 实例
     * @throws 如果工厂未注册，则抛出异常
     */
    public static function getFactory(name:String):DamageManagerFactory {
        var factory:DamageManagerFactory = _namedFactories[name];
        if (factory == undefined) {
            throw "工厂 '" + name + "' 未注册，请先调用 registerFactory 注册。";
        }
        return factory;
    }

    /**
     * 移除已注册的具名工厂。
     *
     * @param name 工厂名称
     * @throws 如果工厂不存在，则抛出异常
     */
    public static function removeFactory(name:String):Void {
        if (_namedFactories[name] == undefined) {
            throw "工厂 '" + name + "' 不存在，无法移除。";
        }
        delete _namedFactories[name];
    }

    /**
     * 清空所有已注册的具名工厂。
     */
    public static function clearAllFactories():Void {
        for (var name:String in _namedFactories) {
            delete _namedFactories[name];
        }
    }

    // 生产只有 Basic(8) 与 ActualTerminal(5)；过滤后仍保持原始处理顺序。
    private var _handles:Array;
    private var _directCache:Array;
    private var _evaluator:Function;
    public var _resolve:Function;
    private var _skipCheckBitmask:Number;
    private var _conditionalHandlerIndices:Array;

    public function DamageManagerFactory(handles:Array, cacheCapacity:Number) {
        configureHandles(handles);
        _setupDirectResolve(createEvaluator(_handles), null);
    }

    private function configureHandles(handles:Array):Void {
        if (handles == null || handles.length == 0 || handles.length > 8) {
            throw "生产伤害工厂只支持 1 到 8 个处理器；扩展实验使用 dev.LegacyDamageManagerFactory。";
        }
        var skip:Number = 0;
        var indices:Array = [];
        for (var i:Number = 0; i < handles.length; i++) {
            if (handles[i].skipCheck) skip |= (1 << i);
            else indices.push(i);
        }
        if (skip == 0) throw "至少需要一个处理器标记为 skipCheck = true。";
        _handles = handles.concat();
        _skipCheckBitmask = skip;
        _conditionalHandlerIndices = indices;
        // 按实际条件数特化；不再调用不存在的条件槽。
        this.getDamageManager = (indices.length == 0) ? getDamageManager0 : this["getDamageManager" + indices.length];
    }

    private function _setupDirectResolve(evaluator:Function, existingCache:Array):Void {
        var dc:Array = (existingCache != null) ? existingCache : [];
        var self:DamageManagerFactory = this;
        _directCache = dc;
        _evaluator = evaluator;
        _resolve = function(bitmask:Number):DamageManager {
            var mgr:DamageManager = dc[bitmask];
            if (mgr != undefined) return mgr;
            mgr = self._evaluator(bitmask);
            dc[bitmask] = mgr;
            return mgr;
        };
    }

    // 仅在缓存缺失时按原始顺序组装，掩码域限定为低 8 位。
    private function createEvaluator(h:Array):Function {
        return function(bitmask:Number):DamageManager {
            var selected:Array = [];
            for (var i:Number = 0; i < h.length; i++) {
                if ((bitmask & (1 << i)) != 0) selected.push(h[i]);
            }
            return new DamageManager(selected);
        };
    }

    public function getDamageManager(bullet:Object):DamageManager {
        return getDamageManager0(bullet);
    }
    public function getDamageManager0(bullet:Object):DamageManager {
        return _resolve(_skipCheckBitmask);
    }
    public function getDamageManager1(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var index:Number;

        if (this._handles[index = this._conditionalHandlerIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager2(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager3(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager4(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager5(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager6(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function getDamageManager7(bullet:Object):DamageManager {
        var bitmask:Number = this._skipCheckBitmask;
        var handles:Array = this._handles;
        var conditionalIndices:Array = this._conditionalHandlerIndices;
        var index:Number;

        if (handles[index = conditionalIndices[0]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[1]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[2]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[3]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[4]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[5]].canHandle(bullet))
            bitmask |= (1 << index);
        if (handles[index = conditionalIndices[6]].canHandle(bullet))
            bitmask |= (1 << index);

        return this._resolve(bitmask);
    }

    public function resetFactory(newHandles:Array, newEvaluator:Function, clearCache:Boolean):Void {
        if (newHandles != null) {
            configureHandles(newHandles);
            _setupDirectResolve(createEvaluator(_handles), (clearCache !== false) ? null : _directCache);
        } else if (newEvaluator != null) {
            if (typeof(newEvaluator) != "function") throw "newEvaluator 必须是一个函数。";
            _evaluator = newEvaluator;
            if (clearCache !== false) _directCache.length = 0;
        } else if (clearCache !== false) _directCache.length = 0;
    }

    public function toString():String {
        return "[DamageManagerFactory] DirectArray handles=" + _handles.length +
            " conditional=" + _conditionalHandlerIndices.join(",") +
            " skip=" + _skipCheckBitmask.toString(2);
    }
}
