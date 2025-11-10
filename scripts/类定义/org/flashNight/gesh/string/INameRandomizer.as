import org.flashNight.naki.RandomNumberEngine.*;

/**
 * 名称随机器接口
 *
 * 定义所有名称随机器的统一行为规范，用于：
 * - 统一API，便于多态使用和扩展
 * - 解耦具体实现与使用方
 * - 支持依赖注入和单元测试
 *
 * 实现类包括：
 * - HexagramRandomizer：六十四卦随机器
 * - MansionRandomizer：二十八宿随机器
 * - JuntaRandomizer：军阀部队名称随机器
 *
 * 设计原则：
 * - 接口隔离：仅定义必要的公共方法
 * - 依赖倒置：依赖于 BaseRandomNumberEngine 抽象
 *
 * @interface INameRandomizer
 * @package org.flashNight.gesh.string
 * @author [作者]
 * @version 1.0
 */
interface org.flashNight.gesh.string.INameRandomizer {
    /**
     * 设置原始名称池
     *
     * 用途：
     * - 初始化或更新名称数据源
     * - 实现类应自动复制数组以防外部修改
     *
     * @param names 名称数组，传入null时应清空
     */
    function setNames(names:Array):Void;

    /**
     * 设置随机数引擎
     *
     * 用途：
     * - 注入不同的随机数生成器（策略模式）
     * - 可选：PCGEngine、MersenneTwister、LinearCongruentialEngine等
     *
     * @param engine 随机引擎实例，传入null时应忽略
     */
    function setRandomEngine(engine:BaseRandomNumberEngine):Void;

    /**
     * 配置是否在耗尽前保持唯一
     *
     * true（推荐）：
     * - 使用池化机制，Fisher-Yates 洗牌后逐个取出
     * - 保证在池耗尽前不会出现重复
     * - 适用于需要公平分配的场景
     *
     * false：
     * - 每次从原始数组随机选择
     * - 可能出现连续重复
     * - 适用于完全随机的场景
     *
     * @param unique true=池化不重复，false=完全随机
     */
    function setUniqueUntilExhaustion(unique:Boolean):Void;

    /**
     * 重置当前可用名称池
     *
     * 操作：
     * - 从原始名称数组重新复制一份
     * - 使用配置的随机引擎重新洗牌
     * - 常用于强制刷新池或测试场景
     */
    function resetPool():Void;

    /**
     * 获取一个随机名称
     *
     * 核心方法，实现类应保证：
     * - 线程安全（AS2单线程环境下通常不需要）
     * - 边界处理（空池、空数组等）
     * - 自动重置（池耗尽时）
     *
     * @return 随机名称字符串，无可用名称时返回空字符串
     */
    function getRandomName():String;
}
