_root.打击数字坐标偏离 = 60;

_root.创建打击伤害数字 = function(效果种类, 数字, myX, myY) {
    var 控制字符串 = 效果种类;
    效果种类 = "打击伤害数字";
    var 游戏世界 = _root.gameworld; // 缓存全局对象
    var 世界效果 = 游戏世界.效果;
    var 效果深度 = 世界效果.getNextHighestDepth();
    var 效果名 = 效果种类 + " " + 效果深度;
    var 打击显示文字 = isNaN(数字) ? "miss" : Math.floor(数字).toString();
    if (typeof(数字) == "string" && 数字.length > 0) {
        打击显示文字 = 数字;
    }

    // 创建特效
    var 数字偏移 = _root.打击数字坐标偏离;
    var x偏移 = _root.随机偏移(数字偏移); // 缓存计算值
    var y偏移 = _root.随机偏移(数字偏移);

    var 创建的效果 = 世界效果.attachMovie(效果种类, 效果名, 效果深度, { _x: myX + x偏移, _y: myY + y偏移, 数字: 打击显示文字, 控制字符串: 控制字符串 });

    // 添加 unload 事件处理器
    创建的效果.onUnload = function() {
        _root.当前打击数字特效总数--;
    };

    return 创建的效果;
};

// 初始化打击伤害数字池
_root.初始化打击伤害数字池 = function(池大小) {
    var 游戏世界 = _root.gameworld;
    游戏世界.可用数字池 = [];
    _root.当前打击数字特效总数 = 0;

    for (var i = 0; i < 池大小; ++i) {
        var 效果种类 = "初始化子弹";
        var 数字 = 0;
        var 打击伤害数字 = _root.创建打击伤害数字(效果种类, 数字, 0, 0);
        游戏世界.可用数字池.push(打击伤害数字); // 创建数字并存储到池中
    }

    // 设置 `可用数字池` 为不可枚举
    _global.ASSetPropFlags(游戏世界, ["可用数字池"], 1, false);
};

// 获取或创建打击伤害数字（使用懒加载和原型模式）
_root.获取或创建打击伤害数字 = function(效果种类, 数字, myX, myY) {
    var 游戏世界 = _root.gameworld;
    if (!游戏世界.打击伤害数字原型) {
        // 如果没有创建过原型，使用懒加载创建原型
        游戏世界.打击伤害数字原型 = _root.创建打击伤害数字(效果种类, 数字, myX, myY);
        _global.ASSetPropFlags(游戏世界, ["打击伤害数字原型"], 1, false);
        游戏世界.打击伤害数字原型._visible = false;
    }

    var 效果深度 = 游戏世界.效果.getNextHighestDepth();
    var 新打击数字 = 游戏世界.打击伤害数字原型.duplicateMovieClip(效果种类 + " " + 效果深度, 效果深度);
    新打击数字.控制字符串 = 效果种类;
    新打击数字._x = myX + _root.随机偏移(_root.打击数字坐标偏离);
    新打击数字._y = myY + _root.随机偏移(_root.打击数字坐标偏离);
    新打击数字.数字 = isNaN(数字) ? "miss" : Math.floor(数字).toString();
    if (typeof(数字) == "string" && 数字.length > 0) {
        新打击数字.数字 = 数字;
    }
    新打击数字._visible = true;
    新打击数字.gotoAndPlay(1);

    return 新打击数字;
};

// 获取可用数字
_root.获取可用数字 = function(控制字符串, 数字, myX, myY) {
    var 打击伤害数字;
    var 数字池 = _root.gameworld.可用数字池;
    myX += _root.随机偏移(_root.打击数字坐标偏离);
    myY += _root.随机偏移(_root.打击数字坐标偏离);

    if (数字池.length > 0) {
        // 从池中取出可用数字
        打击伤害数字 = 数字池.pop();
        打击伤害数字.控制字符串 = 控制字符串;
        打击伤害数字._x = myX;
        打击伤害数字._y = myY;
        打击伤害数字.数字 = isNaN(数字) ? "miss" : Math.floor(数字).toString();
        if (typeof(数字) == "string" && 数字.length > 0) {
            打击伤害数字.数字 = 数字;
        }
        _root.重置色彩(打击伤害数字);
    } else {
        // 如果没有可用对象，则懒加载创建一个新的
        打击伤害数字 = _root.获取或创建打击伤害数字(控制字符串, 数字, myX, myY);
    }

    打击伤害数字._visible = true;
    打击伤害数字.gotoAndPlay(1);

    return 打击伤害数字;
};

// 处理打击数字特效（对外接口，保持向后兼容）
_root.打击数字特效 = function(控制字符串, 数字, myX, myY, 必然触发) {
    // 视野渲染剔除
    var gameWorld:MovieClip = _root.gameworld;
    var sx:Number = gameWorld._xscale * 0.01;
    var locX:Number = gameWorld._x + myX * sx;
    var locY:Number = gameWorld._y + myY * sx;

    // 视野外剔除
    if (locX < 0 || locX > Stage.width || locY < 0 || locY > Stage.height) {
        return;
    }

    if (_root.是否打击数字特效 && (_root.当前打击数字特效总数 <= _root.同屏打击数字特效上限 || _root.成功率(_root.同屏打击数字特效上限 / 5)) || 必然触发) {
        if (gameWorld.可用数字池 == undefined) {
            _root.初始化打击伤害数字池(5);
        }

        _root.获取可用数字(控制字符串, 数字, myX, myY);
        _root.当前打击数字特效总数++;
    }

    // _root.发布消息(控制字符串 + " " + 数字 + " " + myX + " " + myY + " " + 必然触发)
};

/**
 * 打击数字特效内部渲染函数
 *
 * 供 HitNumberBatchProcessor.flush() 调用，跳过节流判断，只负责：
 * 1. 池初始化检查
 * 2. 获取/创建数字对象
 * 3. 更新计数器
 *
 * 注意：视野剔除和节流决策已由 HitNumberBatchProcessor 完成，此处不再重复判断。
 *
 * @param 控制字符串 效果种类（如"暴击"、"能"等）
 * @param 数字 数值或已格式化的字符串
 * @param myX 世界坐标 X
 * @param myY 世界坐标 Y
 * @param 必然触发 是否强制显示（此参数在内部函数中仅用于兼容，实际不影响行为）
 */
_root.打击数字特效内部 = function(控制字符串, 数字, myX, myY, 必然触发) {
    var gameWorld:MovieClip = _root.gameworld;

    // 池初始化检查
    if (gameWorld.可用数字池 == undefined) {
        _root.初始化打击伤害数字池(5);
    }

    // 直接获取/创建数字对象并显示
    _root.获取可用数字(控制字符串, 数字, myX, myY);
    _root.当前打击数字特效总数++;
};
