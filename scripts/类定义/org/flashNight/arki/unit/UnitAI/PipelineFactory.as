import org.flashNight.arki.unit.UnitAI.scoring.ScoringPipeline;
import org.flashNight.arki.unit.UnitAI.scoring.StanceAffinityMod;
import org.flashNight.arki.unit.UnitAI.scoring.TacticalBiasMod;
import org.flashNight.arki.unit.UnitAI.scoring.RigidStateMod;
import org.flashNight.arki.unit.UnitAI.scoring.RangePressureMod;
import org.flashNight.arki.unit.UnitAI.scoring.ReactiveDodgeMod;
import org.flashNight.arki.unit.UnitAI.scoring.AmmoReloadMod;
import org.flashNight.arki.unit.UnitAI.scoring.SkillHierarchyMod;
import org.flashNight.arki.unit.UnitAI.scoring.SurvivalUrgencyMod;
import org.flashNight.arki.unit.UnitAI.scoring.DecisionNoiseMod;
import org.flashNight.arki.unit.UnitAI.scoring.BulletPressureMod;
import org.flashNight.arki.unit.UnitAI.scoring.ComboDepthMod;
import org.flashNight.arki.unit.UnitAI.scoring.CrowdAwarenessMod;
import org.flashNight.arki.unit.UnitAI.scoring.ReflexBoostMod;
import org.flashNight.arki.unit.UnitAI.scoring.MomentumPost;
import org.flashNight.arki.unit.UnitAI.scoring.FreqAdjustPost;
import org.flashNight.arki.unit.UnitAI.strategies.OffenseStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.ReloadStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.PreBuffStrategy;
import org.flashNight.arki.unit.UnitAI.strategies.AnimLockFilter;
import org.flashNight.arki.unit.UnitAI.strategies.InterruptFilter;
import org.flashNight.arki.unit.UnitAI.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.WeaponEvaluator;
import org.flashNight.arki.unit.UnitAI.ActionExecutor;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * PipelineFactory — ModifierRegistry + StrategyRegistry
 *
 * key -> factory 的声明式管线构建器。
 * ActionArbiter 构造时调用 build*() 系列方法，从注册表实例化组件。
 *
 * 内置组件使用直接 if/else 工厂方法（AS2 closure 兼容性最优）。
 * 运行时扩展通过 registerMod/registerSource 注册自定义 factory。
 *
 * deps 对象结构：
 *   { personality, scorer, weaponEval, rng, jitterState, executor }
 *
 * 所有 build 方法：keys==null 则使用 DEFAULT_* 默认配置。
 */
class org.flashNight.arki.unit.UnitAI.PipelineFactory {

    // ── 运行时扩展注册表（仅自定义组件使用）──
    private static var _customMods:Object    = {};
    private static var _customPosts:Object   = {};
    private static var _customSources:Object = {};
    private static var _customFilters:Object = {};

    // ── 默认有序列表 ──
    public static var DEFAULT_MODS:Array = [
        "StanceAffinity", "TacticalBias", "RigidState", "RangePressure",
        "ReactiveDodge", "AmmoReload", "SkillHierarchy", "SurvivalUrgency",
        "BulletPressure", "ComboDepth", "CrowdAwareness", "ReflexBoost", "DecisionNoise"
    ];
    public static var DEFAULT_POSTS:Array = ["Momentum", "FreqAdjust"];
    public static var DEFAULT_FILTERS:Array = ["AnimLock", "Interrupt"];

    // DEFAULT_SOURCES 需要在静态初始化中赋值（AS2 对象字面量在 static var 上不可靠）
    public static var DEFAULT_SOURCES:Object;
    private static var _ready:Boolean = _initSources();
    private static function _initSources():Boolean {
        DEFAULT_SOURCES = {};
        DEFAULT_SOURCES["engage"]   = ["Offense", "Reload"];
        DEFAULT_SOURCES["chase"]    = ["PreBuff", "Reload"];
        DEFAULT_SOURCES["selector"] = [];
        DEFAULT_SOURCES["retreat"]  = ["PreBuff"]; // 撤退不换弹：避免跑步状态换弹失败导致发呆，换弹延到 chase 阶段
        return true;
    }

    // ═══════ 内置工厂方法（无 closure，AS2 安全）═══════

    private static function _createMod(key:String, deps:Object) {
        if (key == "StanceAffinity")  return new StanceAffinityMod();
        if (key == "TacticalBias")    return new TacticalBiasMod();
        if (key == "RigidState")      return new RigidStateMod();
        if (key == "RangePressure")   return new RangePressureMod();
        if (key == "ReactiveDodge")   return new ReactiveDodgeMod();
        if (key == "AmmoReload")      return new AmmoReloadMod();
        if (key == "SkillHierarchy")  return new SkillHierarchyMod();
        if (key == "SurvivalUrgency") return new SurvivalUrgencyMod();
        if (key == "BulletPressure")  return new BulletPressureMod();
        if (key == "DecisionNoise")   return new DecisionNoiseMod(deps.rng);
        if (key == "ComboDepth")      return new ComboDepthMod();
        if (key == "CrowdAwareness")  return new CrowdAwarenessMod();
        if (key == "ReflexBoost")    return new ReflexBoostMod(deps.executor);
        // 自定义扩展
        var f:Function = _customMods[key];
        if (f != null) return f(deps);
        return null;
    }

    private static function _createPost(key:String, deps:Object) {
        if (key == "Momentum")  return new MomentumPost(deps.jitterState);
        if (key == "FreqAdjust") return new FreqAdjustPost();
        var f:Function = _customPosts[key];
        if (f != null) return f(deps);
        return null;
    }

    private static function _createSource(key:String, deps:Object) {
        if (key == "Offense") return new OffenseStrategy(deps.personality);
        if (key == "Reload")  return new ReloadStrategy(deps.personality, deps.weaponEval);
        if (key == "PreBuff") return new PreBuffStrategy(deps.personality);
        var f:Function = _customSources[key];
        if (f != null) return f(deps);
        return null;
    }

    private static function _createFilter(key:String, deps:Object) {
        if (key == "AnimLock")  return new AnimLockFilter();
        if (key == "Interrupt") return new InterruptFilter(deps.executor);
        var f:Function = _customFilters[key];
        if (f != null) return f(deps);
        return null;
    }

    // ═══════ Build Methods ═══════

    /**
     * buildMods — 构建评分修正器数组
     * @param keys  有序 key 列表（null -> DEFAULT_MODS）
     * @param deps  依赖对象
     */
    public static function buildMods(keys:Array, deps:Object):Array {
        if (keys == null) keys = DEFAULT_MODS;
        var result:Array = [];
        for (var i:Number = 0; i < keys.length; i++) {
            var inst = _createMod(keys[i], deps);
            if (inst != null) result.push(inst);
        }
        return result;
    }

    /**
     * buildPosts — 构建后处理器数组
     * @param keys  有序 key 列表（null -> DEFAULT_POSTS）
     * @param deps  依赖对象
     */
    public static function buildPosts(keys:Array, deps:Object):Array {
        if (keys == null) keys = DEFAULT_POSTS;
        var result:Array = [];
        for (var i:Number = 0; i < keys.length; i++) {
            var inst = _createPost(keys[i], deps);
            if (inst != null) result.push(inst);
        }
        return result;
    }

    /**
     * buildSources — 构建策略源映射 { context -> Strategy[] }
     *
     * 同 key 的策略实例在各上下文间共享（保留有状态策略的跨上下文行为，
     * 如 PreBuffStrategy._preBuffCooldownFrame 在 chase/retreat 间同步）。
     *
     * 增量覆盖：sourceSpec 非 null 时，先以 DEFAULT_SOURCES 为基础，
     * 再用 sourceSpec 中的条目覆盖对应 context。
     * 这样调用方只需声明想要覆盖的 context，其余自动继承默认配置。
     *
     * @param sourceSpec  { context: [key, ...] }（null -> DEFAULT_SOURCES 全盘采用）
     * @param deps        依赖对象
     */
    public static function buildSources(sourceSpec:Object, deps:Object):Object {
        // 合并：DEFAULT_SOURCES 为基础，sourceSpec 覆盖
        var merged:Object = {};
        for (var dk:String in DEFAULT_SOURCES) {
            merged[dk] = DEFAULT_SOURCES[dk];
        }
        if (sourceSpec != null) {
            for (var sk:String in sourceSpec) {
                merged[sk] = sourceSpec[sk];
            }
        }

        var cache:Object = {};
        var result:Object = {};
        for (var ctx:String in merged) {
            var keys:Array = merged[ctx];
            var arr:Array = [];
            for (var i:Number = 0; i < keys.length; i++) {
                var key:String = keys[i];
                if (cache[key] == undefined) {
                    var inst = _createSource(key, deps);
                    if (inst != null) cache[key] = inst;
                }
                if (cache[key] != undefined) arr.push(cache[key]);
            }
            result[ctx] = arr;
        }
        return result;
    }

    /**
     * buildFilters — 构建过滤器数组
     * @param keys  有序 key 列表（null -> DEFAULT_FILTERS）
     * @param deps  依赖对象
     */
    public static function buildFilters(keys:Array, deps:Object):Array {
        if (keys == null) keys = DEFAULT_FILTERS;
        var result:Array = [];
        for (var i:Number = 0; i < keys.length; i++) {
            var inst = _createFilter(keys[i], deps);
            if (inst != null) result.push(inst);
        }
        return result;
    }

    // ═══════ Runtime Extension ═══════

    public static function registerMod(key:String, factory:Function):Void {
        _customMods[key] = factory;
    }

    public static function registerPost(key:String, factory:Function):Void {
        _customPosts[key] = factory;
    }

    public static function registerSource(key:String, factory:Function):Void {
        _customSources[key] = factory;
    }

    public static function registerFilter(key:String, factory:Function):Void {
        _customFilters[key] = factory;
    }
}
