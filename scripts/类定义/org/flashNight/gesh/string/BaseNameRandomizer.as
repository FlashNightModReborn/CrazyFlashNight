import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * 通用名称随机器基类
 *
 * 核心功能：
 * - 提供基于池化的名称随机选择机制
 * - 使用 Fisher-Yates 洗牌算法确保随机性
 * - 支持"耗尽前不重复"模式（池耗尽后自动重置）
 * - 可配置随机数引擎（支持 PCG、MT19937 等高质量PRNG）
 *
 * 设计模式：
 * - 模板方法模式：定义通用流程，子类可重写关键方法
 * - 策略模式：可注入不同的随机数引擎
 * - 依赖倒置：依赖于 BaseRandomNumberEngine 抽象
 *
 * 使用示例：
 * <code>
 * var randomizer:HexagramRandomizer = HexagramRandomizer.getInstance();
 * var name:String = randomizer.getRandomName(); // "乾为天"
 * </code>
 *
 * @class BaseNameRandomizer
 * @package org.flashNight.gesh.string
 * @implements INameRandomizer
 * @author [作者]
 * @version 1.0
 */
class org.flashNight.gesh.string.BaseNameRandomizer implements INameRandomizer {
    /** 原始名称数组（不可变源数据） */
    private var _names:Array;

    /** 当前可用名称池（每次获取会从此池中pop） */
    private var _pool:Array;

    /** 随机数引擎（默认使用 LinearCongruentialEngine） */
    private var _randomEngine:BaseRandomNumberEngine;

    /** 是否在耗尽前保持唯一（true则使用池化机制） */
    private var _uniqueUntilExhaustion:Boolean;

    /**
     * 构造函数
     * 初始化空数组并设置默认配置
     */
    public function BaseNameRandomizer() {
        _names = [];
        _pool = [];
        _uniqueUntilExhaustion = true;
        _randomEngine = LinearCongruentialEngine.getInstance();
    }

    /**
     * 设置随机数引擎
     *
     * @param engine 随机引擎实例（如 PCGEngine、MersenneTwister）
     *               传入 null 则忽略
     */
    public function setRandomEngine(engine:BaseRandomNumberEngine):Void {
        if (engine != null) {
            _randomEngine = engine;
        }
    }

    /**
     * 设置原始名称池
     *
     * 注意：
     * - 会自动复制传入数组以防止外部修改
     * - 设置后会立即重置并洗牌当前池
     *
     * @param names 名称数组，传入 null 则清空
     */
    public function setNames(names:Array):Void {
        if (names == null) {
            _names = [];
        } else {
            _names = names.slice();
        }
        resetPool();
    }

    /**
     * 设置是否在耗尽前保持唯一
     *
     * @param unique true：使用池化机制，耗尽前不重复（推荐）
     *               false：每次都从原始数组随机选择（可能重复）
     */
    public function setUniqueUntilExhaustion(unique:Boolean):Void {
        _uniqueUntilExhaustion = unique;
    }

    /**
     * 重置当前可用名称池
     *
     * 操作：
     * 1. 从原始名称数组复制一份新池
     * 2. 使用 Fisher-Yates 算法洗牌
     */
    public function resetPool():Void {
        _pool = _names.slice();
        shufflePool();
    }

    /**
     * 洗牌当前池（Fisher-Yates 算法）
     *
     * 算法特点：
     * - 时间复杂度 O(n)
     * - 保证等概率分布
     * - 倒序遍历，每次与 [0, i] 区间内随机位置交换
     */
    private function shufflePool():Void {
        var length:Number = _pool.length;
        while (--length > 0) {
            var swapIndex:Number = _randomEngine.random(length + 1);
            var temp = _pool[length];
            _pool[length] = _pool[swapIndex];
            _pool[swapIndex] = temp;
        }
    }

    /**
     * 获取一个随机名称
     *
     * 行为：
     * - 如果池为空且启用"耗尽前不重复"，自动重置池
     * - 如果池为空且未启用，则重新洗牌原始数组
     * - 使用 pop() 从池尾取出名称
     *
     * 边界情况：
     * - 如果名称数组为空，返回空字符串
     *
     * @return 随机名称，无可用名称时返回空字符串
     */
    public function getRandomName():String {
        if (_pool.length < 1) {
            if (_uniqueUntilExhaustion) {
                resetPool();
            } else if (_names.length > 0) {
                _pool = _names.slice();
                shufflePool();
            } else {
                return "";
            }
        }

        if (_pool.length < 1) {
            return "";
        }

        return String(_pool.pop());
    }

    /**
     * 当前剩余可用名称数量
     * @returns {Number} 数量
     */
    public function getRemainingCount():Number {
        return _pool.length;
    }

    /**
     * 是否已经配置名称池
     * @returns {Boolean} true 表示可用
     */
    public function hasNamesConfigured():Boolean {
        return _names.length > 0;
    }
}
