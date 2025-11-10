import org.flashNight.naki.RandomNumberEngine.*;
 
/**
 * 名称随机器接口，统一随机命名行为
 * @interface INameRandomizer
 * @package org.flashNight.gesh.string
 */
interface org.flashNight.gesh.string.INameRandomizer {
    /**
     * 设置原始名称池
     * @param {Array} names 名称数组
     */
    function setNames(names:Array):Void;

    /**
     * 设置随机数引擎
     * @param {BaseRandomNumberEngine} engine 随机引擎实例
     */
    function setRandomEngine(engine:BaseRandomNumberEngine):Void;

    /**
     * 是否在耗尽前保持唯一
     * @param {Boolean} unique true 则使用 Fisher-Yates 打乱后逐个取出
     */
    function setUniqueUntilExhaustion(unique:Boolean):Void;

    /**
     * 重置当前可用名称池
     */
    function resetPool():Void;

    /**
     * 获取一个随机名称
     * @returns {String} 名称
     */
    function getRandomName():String;
}
