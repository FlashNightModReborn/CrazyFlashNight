import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;

/** 
 * 通用名称随机器基类，负责池化与 Fisher-Yates 打乱
 * @class BaseNameRandomizer
 * @package org.flashNight.gesh.string
 */
class org.flashNight.gesh.string.BaseNameRandomizer implements INameRandomizer {
    private var _names:Array;
    private var _pool:Array;
    private var _randomEngine:BaseRandomNumberEngine;
    private var _uniqueUntilExhaustion:Boolean;

    public function BaseNameRandomizer() {
        _names = [];
        _pool = [];
        _uniqueUntilExhaustion = true;
        _randomEngine = LinearCongruentialEngine.getInstance();
    }

    public function setRandomEngine(engine:BaseRandomNumberEngine):Void {
        if (engine != null) {
            _randomEngine = engine;
        }
    }

    public function setNames(names:Array):Void {
        if (names == null) {
            _names = [];
        } else {
            _names = names.slice();
        }
        resetPool();
    }

    public function setUniqueUntilExhaustion(unique:Boolean):Void {
        _uniqueUntilExhaustion = unique;
    }

    public function resetPool():Void {
        _pool = _names.slice();
        shufflePool();
    }

    private function shufflePool():Void {
        var length:Number = _pool.length;
        while (--length > 0) {
            var swapIndex:Number = _randomEngine.random(length + 1);
            var temp = _pool[length];
            _pool[length] = _pool[swapIndex];
            _pool[swapIndex] = temp;
        }
    }

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
