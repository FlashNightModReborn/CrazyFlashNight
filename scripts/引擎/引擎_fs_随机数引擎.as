import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.Delegate;

// 获取随机数引擎实例并存储为全局变量
_root.linearEngine = LinearCongruentialEngine.getInstance();
_root.mersenneEngine = MersenneTwister.getInstance();

PinkNoiseEngine.getInstance();
// 初始化引擎，使用当前时间作为种子
_root.linearEngine.init(1192433993, 1013904223, 4294967296, new Date().getTime());
_root.mersenneEngine.initialize(new Date().getTime());

// 绑定重置随机数种子的方法，使用自定义函数以处理复杂逻辑
_root.重置随机数种子 = Delegate.create(_root, function() {
    _root.random_seed = new Date().getTime() + this._currentframe + this._parent._currentframe + this._parent._currentframe;
    _root.linearEngine.setSeed(_root.random_seed);
    return _root.random_seed;
});

// 绑定设置随机数种子的方法，使用自定义函数以处理复杂逻辑
_root.srand_seed = Delegate.create(_root, function() {
    _root.random_seed = new Date().getTime() + this._currentframe;
    _root.mersenneEngine.initialize(_root.random_seed);
    _root.linearEngine.setSeed(_root.random_seed);
    return _root.random_seed;
});

// 绑定线性同余引擎的方法
_root.basic_random = Delegate.create(_root.linearEngine, _root.linearEngine.nextFloat);
_root.成功率 = Delegate.create(_root.linearEngine, _root.linearEngine.successRate);
_root.随机整数 = Delegate.create(_root.linearEngine, _root.linearEngine.randomInteger);
_root.随机浮点 = Delegate.create(_root.linearEngine, _root.linearEngine.randomFloat);
_root.随机偏移 = Delegate.create(_root.linearEngine, _root.linearEngine.randomOffset);
_root.随机浮点偏移 = Delegate.create(_root.linearEngine, _root.linearEngine.randomFloatOffset);
_root.随机波动 = Delegate.create(_root.linearEngine, _root.linearEngine.randomFluctuation);
_root.获取随机数组成员 = Delegate.create(_root.linearEngine, _root.linearEngine.getRandomArrayElement);
_root.数组洗牌 = Delegate.create(_root.linearEngine, _root.linearEngine.shuffleArray);

// 绑定梅森旋转器引擎的方法
_root.advance_random = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.nextFloat);
_root.random_integer = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.randomInteger);
_root.random_float = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.randomFloat);
_root.random_offset = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.randomOffset);
_root.random_float_offset = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.randomFloatOffset);
_root.random_fluctuation = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.randomFluctuation);
_root.rate_of_success = Delegate.create(_root.mersenneEngine, _root.mersenneEngine.successRate);
